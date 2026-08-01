#!/usr/bin/env python3
"""Create and pair bounded cross-profile consultation handoffs.

This tool does not dispatch agents, inspect domain data, or promote memory. It
creates metadata-bounded request/response artifacts for owner-profile use.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import secrets
import stat
import sys
from pathlib import Path
from typing import Any, Mapping

import yaml

from profile_exchange_schema import HANDOFF_ID_PATTERN, validate_handoff
from profile_handoff_check import HandoffCheckError, _load_frontmatter, _load_registry_policy

DEFAULT_ROOT = Path("~/.local/state/hermes/profile-consult").expanduser()
DEFAULT_REGISTRY = Path("~/.local/share/hermes/profile-registry.json").expanduser()
FIELD_PATTERN = re.compile(r"^[a-z][a-z0-9_]{0,63}$")
MAX_SCOPE_LENGTH = 160
MAX_FIELD_VALUE_BYTES = 4096


class ConsultError(RuntimeError):
    """Expected fail-closed consultation error with a stable reason code."""


def _load_registry(registry_path: Path) -> dict[str, Any]:
    try:
        value = json.loads(registry_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ConsultError("registry_unavailable") from error
    if not isinstance(value, dict) or value.get("schema_version") != 2:
        raise ConsultError("registry_schema_invalid")
    return value


def _consultation_route(
    registry: Mapping[str, Any], *, source: str, target: str
) -> dict[str, Any]:
    exchange = registry.get("information_exchange")
    consultation = exchange.get("consultation") if isinstance(exchange, dict) else None
    if not isinstance(consultation, dict) or consultation.get("schema_version") != 1:
        raise ConsultError("consultation_policy_invalid")
    if consultation.get("max_hops") != 1:
        raise ConsultError("consultation_max_hops_invalid")
    routes = consultation.get("routes")
    if not isinstance(routes, list):
        raise ConsultError("consultation_routes_invalid")
    matches = [
        row
        for row in routes
        if isinstance(row, dict)
        and row.get("source") == source
        and row.get("target") == target
    ]
    if len(matches) != 1:
        raise ConsultError("consultation_route_not_allowed")
    route = matches[0]
    fields = route.get("allowed_requested_fields")
    ttl = route.get("max_ttl_hours")
    if (
        not isinstance(fields, list)
        or not fields
        or any(not isinstance(item, str) or not FIELD_PATTERN.fullmatch(item) for item in fields)
        or len(set(fields)) != len(fields)
        or isinstance(ttl, bool)
        or not isinstance(ttl, int)
        or ttl <= 0
    ):
        raise ConsultError("consultation_route_invalid")
    return route


def _validate_field_names(fields: list[str], *, code: str) -> None:
    if (
        not fields
        or any(not isinstance(item, str) or not FIELD_PATTERN.fullmatch(item) for item in fields)
        or len(set(fields)) != len(fields)
    ):
        raise ConsultError(code)


def _validate_scope(scope: str) -> None:
    if not isinstance(scope, str) or not scope.strip() or len(scope) > MAX_SCOPE_LENGTH:
        raise ConsultError("scope_invalid")
    if "\n" in scope or "\r" in scope:
        raise ConsultError("scope_invalid")


def _metadata_errors(
    metadata: Mapping[str, Any], *, registry_path: Path, target: str, now: dt.datetime
) -> list[str]:
    try:
        profiles, purposes, sensitivity = _load_registry_policy(
            registry_path, target=target
        )
    except HandoffCheckError as error:
        raise ConsultError(str(error)) from error
    return validate_handoff(
        metadata,
        expected_target=target,
        now=now,
        registered_profiles=profiles,
        allowed_purposes=purposes,
        allowed_sensitivity=sensitivity,
    )


def _render(metadata: Mapping[str, Any], body: str) -> bytes:
    frontmatter = yaml.safe_dump(
        dict(metadata), sort_keys=False, allow_unicode=True, default_flow_style=False
    )
    return f"---\n{frontmatter}---\n\n{body.rstrip()}\n".encode("utf-8")


def _ensure_private_directory(path: Path) -> None:
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or path.is_symlink():
        raise ConsultError("state_directory_unsafe")
    if stat.S_IMODE(info.st_mode) & 0o077:
        raise ConsultError("state_directory_permissions_unsafe")


def _exclusive_write(path: Path, payload: bytes) -> None:
    _ensure_private_directory(path.parent)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(path, flags, 0o600)
    except FileExistsError as error:
        raise ConsultError("artifact_exists") from error
    except OSError as error:
        raise ConsultError("artifact_create_failed") from error
    created = True
    try:
        view = memoryview(payload)
        while view:
            written = os.write(fd, view)
            if written <= 0:
                raise ConsultError("artifact_write_failed")
            view = view[written:]
        os.fsync(fd)
    except Exception:
        os.close(fd)
        if created:
            try:
                path.unlink()
            except OSError:
                pass
        raise
    else:
        os.close(fd)
    directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)


def _new_id(source: str, now: dt.datetime, suffix: str) -> str:
    stamp = now.astimezone(dt.timezone.utc).strftime("%Y%m%dt%H%M%Sz").lower()
    return f"{source}:{stamp}:{suffix}-{secrets.token_hex(4)}"


def create_request(
    *,
    root: Path,
    registry_path: Path,
    source: str,
    target: str,
    scope: str,
    requested_fields: list[str],
    now: dt.datetime,
    ttl_hours: int,
    handoff_id: str | None = None,
) -> dict[str, Any]:
    if now.tzinfo is None or now.utcoffset() is None:
        raise ConsultError("now_requires_timezone")
    _validate_scope(scope)
    _validate_field_names(requested_fields, code="requested_fields_invalid")
    registry = _load_registry(registry_path)
    route = _consultation_route(registry, source=source, target=target)
    allowed = set(route["allowed_requested_fields"])
    if set(requested_fields) - allowed:
        raise ConsultError("requested_field_not_allowed")
    if isinstance(ttl_hours, bool) or not isinstance(ttl_hours, int) or ttl_hours <= 0:
        raise ConsultError("ttl_invalid")
    if ttl_hours > route["max_ttl_hours"]:
        raise ConsultError("ttl_exceeds_route_limit")
    identifier = handoff_id or _new_id(source, now, "request")
    if not HANDOFF_ID_PATTERN.fullmatch(identifier):
        raise ConsultError("handoff_id_invalid")
    valid_until = now + dt.timedelta(hours=ttl_hours)
    metadata: dict[str, Any] = {
        "schema_family": "cross_profile_handoff",
        "schema_version": 2,
        "handoff_id": identifier,
        "source_profile": source,
        "target_profiles": [target],
        "purpose": "review-request",
        "generated_at": now.isoformat(),
        "valid_until": valid_until.isoformat(),
        "scope": scope,
        "status": "ready",
        "source_refs": [{"type": "opaque-handle", "value": identifier}],
        "source_health": "healthy",
        "sensitivity": "ordinary",
        "raw_data_included": False,
        "retention_class": "transient",
        "supersedes": None,
        "assumptions": [],
        "uncertainties": [],
        "in_reply_to": None,
        "requested_fields": requested_fields,
        "response_deadline": valid_until.isoformat(),
        "hop_count": 0,
        "max_hops": 1,
    }
    errors = _metadata_errors(metadata, registry_path=registry_path, target=target, now=now)
    if errors:
        raise ConsultError("generated_request_invalid:" + ",".join(errors))
    path = root / "requests" / f"{identifier}.md"
    body = "# Consultation request\n\nNo domain raw data is included. Return only the requested fields."
    _exclusive_write(path, _render(metadata, body))
    return {
        "ok": True,
        "path": str(path),
        "handoff_id": identifier,
        "source": source,
        "target": target,
        "purpose": "review-request",
        "requested_fields": requested_fields,
        "response_deadline": valid_until.isoformat(),
    }


def _bounded_response_fields(values: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(values, Mapping) or not values:
        raise ConsultError("response_fields_invalid")
    names = list(values)
    _validate_field_names(names, code="response_fields_invalid")
    result: dict[str, Any] = {}
    for name, value in values.items():
        encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        if len(encoded) > MAX_FIELD_VALUE_BYTES:
            raise ConsultError("response_field_too_large")
        result[name] = value
    return result


def create_response(
    *,
    root: Path,
    registry_path: Path,
    request_path: Path,
    source: str,
    response_fields: Mapping[str, Any],
    now: dt.datetime,
    handoff_id: str | None = None,
) -> dict[str, Any]:
    if now.tzinfo is None or now.utcoffset() is None:
        raise ConsultError("now_requires_timezone")
    try:
        request = _load_frontmatter(request_path)
    except HandoffCheckError as error:
        raise ConsultError(str(error)) from error
    if request.get("purpose") != "review-request":
        raise ConsultError("request_purpose_invalid")
    targets = request.get("target_profiles")
    if targets != [source]:
        raise ConsultError("response_source_mismatch")
    requester = request.get("source_profile")
    if not isinstance(requester, str):
        raise ConsultError("request_source_invalid")
    registry = _load_registry(registry_path)
    _consultation_route(registry, source=requester, target=source)
    request_errors = _metadata_errors(
        request, registry_path=registry_path, target=source, now=now
    )
    if request_errors:
        raise ConsultError("request_invalid:" + ",".join(request_errors))
    deadline = request.get("response_deadline")
    try:
        parsed_deadline = dt.datetime.fromisoformat(str(deadline).replace("Z", "+00:00"))
    except ValueError as error:
        raise ConsultError("request_deadline_invalid") from error
    if parsed_deadline <= now:
        raise ConsultError("request_deadline_expired")
    fields = _bounded_response_fields(response_fields)
    requested = request.get("requested_fields")
    if not isinstance(requested, list):
        raise ConsultError("request_fields_invalid")
    if set(fields) - set(requested):
        raise ConsultError("returned_field_not_requested")
    identifier = handoff_id or _new_id(source, now, "response")
    if not HANDOFF_ID_PATTERN.fullmatch(identifier):
        raise ConsultError("handoff_id_invalid")
    metadata: dict[str, Any] = {
        "schema_family": "cross_profile_handoff",
        "schema_version": 2,
        "handoff_id": identifier,
        "source_profile": source,
        "target_profiles": [requester],
        "purpose": "consultation-response",
        "generated_at": now.isoformat(),
        "valid_until": str(request["valid_until"]),
        "scope": str(request["scope"]),
        "status": "ready",
        "source_refs": [
            {"type": "opaque-handle", "value": str(request["handoff_id"])}
        ],
        "source_health": "unknown",
        "sensitivity": "ordinary",
        "raw_data_included": False,
        "retention_class": "transient",
        "supersedes": None,
        "assumptions": [],
        "uncertainties": [],
        "in_reply_to": str(request["handoff_id"]),
        "returned_fields": list(fields),
        "hop_count": 1,
        "max_hops": 1,
    }
    errors = _metadata_errors(
        metadata, registry_path=registry_path, target=requester, now=now
    )
    if errors:
        raise ConsultError("generated_response_invalid:" + ",".join(errors))
    path = root / "responses" / f"{identifier}.md"
    body = "# Consultation response\n\n```json\n" + json.dumps(
        fields, ensure_ascii=False, indent=2, sort_keys=True
    ) + "\n```"
    _exclusive_write(path, _render(metadata, body))
    return {
        "ok": True,
        "path": str(path),
        "handoff_id": identifier,
        "in_reply_to": str(request["handoff_id"]),
        "source": source,
        "target": requester,
        "returned_fields": list(fields),
    }


def consultation_status(
    *, root: Path, registry_path: Path, now: dt.datetime
) -> list[dict[str, Any]]:
    requests_dir = root / "requests"
    responses_dir = root / "responses"
    responses_by_parent: dict[str, list[dict[str, Any]]] = {}
    if responses_dir.is_dir() and not responses_dir.is_symlink():
        for path in sorted(responses_dir.glob("*.md")):
            try:
                metadata = _load_frontmatter(path)
            except HandoffCheckError:
                continue
            parent = metadata.get("in_reply_to")
            if isinstance(parent, str):
                responses_by_parent.setdefault(parent, []).append(metadata)

    rows: list[dict[str, Any]] = []
    if not requests_dir.is_dir() or requests_dir.is_symlink():
        return rows
    for path in sorted(requests_dir.glob("*.md")):
        try:
            request = _load_frontmatter(path)
        except HandoffCheckError:
            continue
        request_id = request.get("handoff_id")
        source = request.get("source_profile")
        targets = request.get("target_profiles")
        deadline = request.get("response_deadline")
        if (
            not isinstance(request_id, str)
            or not isinstance(source, str)
            or not isinstance(targets, list)
            or len(targets) != 1
            or not isinstance(targets[0], str)
            or not isinstance(deadline, str)
        ):
            continue
        target = targets[0]
        response_id: str | None = None
        try:
            parsed_deadline = dt.datetime.fromisoformat(deadline.replace("Z", "+00:00"))
            request_errors = _metadata_errors(
                request, registry_path=registry_path, target=target, now=now
            )
        except (ValueError, ConsultError):
            state = "invalid-request"
        else:
            expiry_errors = {
                "handoff_expired",
                "consultation_response_deadline_expired",
            }
            if request_errors and not set(request_errors) <= expiry_errors:
                state = "invalid-request"
            elif parsed_deadline <= now:
                state = "expired"
            else:
                candidates = responses_by_parent.get(request_id, [])
                if not candidates:
                    state = "pending"
                elif len(candidates) != 1:
                    state = "invalid-response"
                else:
                    response = candidates[0]
                    try:
                        response_errors = _metadata_errors(
                            response,
                            registry_path=registry_path,
                            target=source,
                            now=now,
                        )
                    except ConsultError:
                        response_errors = ["response_policy_invalid"]
                    returned = response.get("returned_fields")
                    requested = request.get("requested_fields")
                    generated = response.get("generated_at")
                    try:
                        generated_at = (
                            generated
                            if isinstance(generated, dt.datetime)
                            else dt.datetime.fromisoformat(
                                str(generated).replace("Z", "+00:00")
                            )
                        )
                    except ValueError:
                        generated_at = None
                    pair_valid = (
                        response.get("source_profile") == target
                        and response.get("target_profiles") == [source]
                        and isinstance(returned, list)
                        and isinstance(requested, list)
                        and set(returned) <= set(requested)
                        and response.get("valid_until") == request.get("valid_until")
                        and generated_at is not None
                        and generated_at <= parsed_deadline
                    )
                    candidate_id = response.get("handoff_id")
                    if response_errors or not pair_valid or not isinstance(candidate_id, str):
                        state = "invalid-response"
                    else:
                        state = "answered"
                        response_id = candidate_id
        rows.append(
            {
                "request_id": request_id,
                "source": source,
                "target": target,
                "state": state,
                "response_id": response_id,
                "response_deadline": deadline,
            }
        )
    return rows


def _parse_now(value: str | None) -> dt.datetime:
    if value is None:
        return dt.datetime.now(dt.timezone.utc)
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise ConsultError("now_invalid") from error
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ConsultError("now_requires_timezone")
    return parsed


def _field_assignment(value: str) -> tuple[str, Any]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("field must be NAME=JSON_VALUE")
    name, encoded = value.split("=", 1)
    try:
        decoded = json.loads(encoded)
    except json.JSONDecodeError:
        decoded = encoded
    return name, decoded


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    parser.add_argument("--now")
    subparsers = parser.add_subparsers(dest="command", required=True)

    request_parser = subparsers.add_parser("request")
    request_parser.add_argument("--from", dest="source", required=True)
    request_parser.add_argument("--to", dest="target", required=True)
    request_parser.add_argument("--scope", required=True)
    request_parser.add_argument("--fields", required=True)
    request_parser.add_argument("--ttl-hours", required=True, type=int)

    response_parser = subparsers.add_parser("respond")
    response_parser.add_argument("request", type=Path)
    response_parser.add_argument("--from", dest="source", required=True)
    response_parser.add_argument("--field", action="append", type=_field_assignment, required=True)

    subparsers.add_parser("status")
    args = parser.parse_args(argv)
    now = _parse_now(args.now)
    try:
        if args.command == "request":
            result = create_request(
                root=args.root,
                registry_path=args.registry,
                source=args.source,
                target=args.target,
                scope=args.scope,
                requested_fields=args.fields.split(","),
                now=now,
                ttl_hours=args.ttl_hours,
            )
        elif args.command == "respond":
            response_fields = dict(args.field)
            if len(response_fields) != len(args.field):
                raise ConsultError("response_fields_duplicate")
            result = create_response(
                root=args.root,
                registry_path=args.registry,
                request_path=args.request,
                source=args.source,
                response_fields=response_fields,
                now=now,
            )
        else:
            result = {"ok": True, "consultations": consultation_status(
                root=args.root, registry_path=args.registry, now=now
            )}
    except ConsultError as error:
        print(json.dumps({"ok": False, "reason_code": str(error)}, sort_keys=True, separators=(",", ":")))
        return 1
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
