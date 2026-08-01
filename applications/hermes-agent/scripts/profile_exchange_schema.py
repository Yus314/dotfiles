#!/usr/bin/env python3
"""Deterministic metadata validators for cross-profile exchange artifacts.

The validators intentionally inspect metadata only. They do not open source
references, read artifact bodies, mutate replay state, or claim that narrative
content is semantically correct.
"""
from __future__ import annotations

import datetime as dt
import re
from collections.abc import Iterable, Mapping
from urllib.parse import urlsplit


WEEKLY_SUMMARY_FAMILY = "weekly_summary"
WEEKLY_SUMMARY_VERSION = 1
HANDOFF_FAMILY = "cross_profile_handoff"
HANDOFF_VERSION = 2
HANDOFF_ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._:-]{0,127}$")
OPAQUE_HANDLE_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$")
RETENTION_CLASSES = {"transient", "promotable", "durable"}
SOURCE_HEALTH_VALUES = {"healthy", "degraded", "unknown"}
HANDOFF_REQUIRED_FIELDS = {
    "schema_family",
    "schema_version",
    "handoff_id",
    "source_profile",
    "target_profiles",
    "purpose",
    "generated_at",
    "valid_until",
    "scope",
    "status",
    "source_refs",
    "source_health",
    "sensitivity",
    "raw_data_included",
    "retention_class",
    "supersedes",
    "assumptions",
    "uncertainties",
}
HANDOFF_OPTIONAL_FIELDS = {
    "in_reply_to",
    "requested_fields",
    "returned_fields",
    "response_deadline",
    "hop_count",
    "max_hops",
}
HANDOFF_FIELDS = HANDOFF_REQUIRED_FIELDS | HANDOFF_OPTIONAL_FIELDS
WEEKLY_SUMMARY_FIELDS = {
    "schema_family",
    "schema_version",
    "owner_profile",
    "generated_at",
    "coverage_start",
    "coverage_end",
    "source_watermark",
    "status",
}


def _nonempty_string(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _string_list(value: object) -> bool:
    return isinstance(value, list) and all(_nonempty_string(item) for item in value)


def _parse_datetime(
    value: object, *, field: str, errors: list[str]
) -> dt.datetime | None:
    if isinstance(value, dt.datetime):
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            errors.append(f"{field}_invalid")
            return None
    else:
        errors.append(f"{field}_invalid")
        return None
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        errors.append(f"{field}_requires_timezone")
        return None
    return parsed


def _parse_date(value: object, *, field: str, errors: list[str]) -> dt.date | None:
    if not isinstance(value, str):
        errors.append(f"{field}_invalid")
        return None
    try:
        return dt.date.fromisoformat(value)
    except ValueError:
        errors.append(f"{field}_invalid")
        return None


def _valid_source_ref(value: object) -> bool:
    if not isinstance(value, Mapping) or set(value) != {"type", "value"}:
        return False
    ref_type = value.get("type")
    ref_value = value.get("value")
    if not _nonempty_string(ref_type) or not _nonempty_string(ref_value):
        return False
    assert isinstance(ref_type, str) and isinstance(ref_value, str)
    if ref_type in {"opaque-handle", "local-handle"}:
        return bool(OPAQUE_HANDLE_PATTERN.fullmatch(ref_value))
    if ref_type == "url":
        parsed = urlsplit(ref_value)
        return (
            parsed.scheme in {"http", "https"}
            and bool(parsed.netloc)
            and parsed.username is None
            and parsed.password is None
        )
    return False


def validate_weekly_summary(
    metadata: Mapping[str, object],
    *,
    expected_owner: str,
    expected_week: str,
) -> list[str]:
    """Validate weekly-summary-v1 metadata without inspecting its body."""
    errors: list[str] = []
    for field in sorted(WEEKLY_SUMMARY_FIELDS):
        if field not in metadata:
            errors.append(f"missing_field:{field}")

    if metadata.get("schema_family") != WEEKLY_SUMMARY_FAMILY:
        errors.append("schema_family_invalid")
    if str(metadata.get("schema_version", "")) != str(WEEKLY_SUMMARY_VERSION):
        errors.append("schema_version_unsupported")
    if metadata.get("owner_profile") != expected_owner:
        errors.append("owner_mismatch")
    status = metadata.get("status")
    if not _nonempty_string(status) or not str(status).lower().startswith("domain-owned"):
        errors.append("status_not_domain_owned")
    if not _nonempty_string(metadata.get("source_watermark")):
        errors.append("source_watermark_invalid")

    _parse_datetime(metadata.get("generated_at"), field="generated_at", errors=errors)
    coverage_start = _parse_date(
        metadata.get("coverage_start"), field="coverage_start", errors=errors
    )
    coverage_end = _parse_date(
        metadata.get("coverage_end"), field="coverage_end", errors=errors
    )
    if coverage_start is not None and coverage_end is not None:
        if coverage_start > coverage_end:
            errors.append("invalid_coverage_order")
        try:
            year_text, week_text = expected_week.split("-W", 1)
            week_start = dt.date.fromisocalendar(int(year_text), int(week_text), 1)
            week_end = dt.date.fromisocalendar(int(year_text), int(week_text), 7)
        except (ValueError, TypeError):
            errors.append("expected_week_invalid")
        else:
            if coverage_start > week_start or coverage_end < week_end:
                errors.append("week_not_covered")
    return errors


def validate_handoff(
    metadata: Mapping[str, object],
    *,
    expected_target: str,
    now: dt.datetime,
    registered_profiles: Iterable[str],
    allowed_purposes: Iterable[str],
    allowed_sensitivity: Iterable[str],
    seen_ids: Iterable[str] = (),
) -> list[str]:
    """Validate a cross-profile-handoff-v2 envelope.

    Replay detection is read-only: callers supply previously consumed IDs via
    ``seen_ids`` and remain responsible for atomically recording a successful
    consumption.
    """
    errors: list[str] = []
    registered = set(registered_profiles)
    purposes = set(allowed_purposes)
    sensitivities = set(allowed_sensitivity)
    replayed = set(seen_ids)

    for field in sorted(HANDOFF_REQUIRED_FIELDS):
        if field not in metadata:
            errors.append(f"missing_field:{field}")
    for field in sorted(set(metadata) - HANDOFF_FIELDS):
        errors.append(f"unknown_field:{field}")

    if metadata.get("schema_family") != HANDOFF_FAMILY:
        errors.append("schema_family_invalid")
    if metadata.get("schema_version") != HANDOFF_VERSION:
        errors.append("schema_version_unsupported")

    handoff_id = metadata.get("handoff_id")
    if not isinstance(handoff_id, str) or not HANDOFF_ID_PATTERN.fullmatch(handoff_id):
        errors.append("handoff_id_invalid")
    elif handoff_id in replayed:
        errors.append("handoff_replayed")

    source_profile = metadata.get("source_profile")
    if not _nonempty_string(source_profile):
        errors.append("source_profile_invalid")
    elif source_profile not in registered:
        errors.append("source_profile_unknown")

    target_profiles = metadata.get("target_profiles")
    if (
        not isinstance(target_profiles, list)
        or not target_profiles
        or any(not _nonempty_string(item) for item in target_profiles)
    ):
        errors.append("target_profiles_invalid")
    else:
        targets = [str(item) for item in target_profiles]
        if len(set(targets)) != len(targets):
            errors.append("target_profiles_duplicate")
        if expected_target not in targets:
            errors.append(f"target_profile_missing:{expected_target}")
        for target in sorted(set(targets) - registered):
            errors.append(f"target_profile_unknown:{target}")

    purpose = metadata.get("purpose")
    if not _nonempty_string(purpose):
        errors.append("purpose_invalid")
    elif purpose not in purposes:
        errors.append("purpose_not_allowed")

    generated_at = _parse_datetime(
        metadata.get("generated_at"), field="generated_at", errors=errors
    )
    valid_until = _parse_datetime(
        metadata.get("valid_until"), field="valid_until", errors=errors
    )
    if now.tzinfo is None or now.utcoffset() is None:
        raise ValueError("now must be timezone-aware")
    if generated_at is not None and generated_at > now + dt.timedelta(minutes=5):
        errors.append("generated_at_in_future")
    if valid_until is not None:
        if valid_until <= now:
            errors.append("handoff_expired")
        if generated_at is not None and valid_until <= generated_at:
            errors.append("invalid_validity_order")

    if not _nonempty_string(metadata.get("scope")):
        errors.append("scope_invalid")
    if metadata.get("status") != "ready":
        errors.append("handoff_not_ready")
    if metadata.get("source_health") not in SOURCE_HEALTH_VALUES:
        errors.append("source_health_invalid")

    source_refs = metadata.get("source_refs")
    if not isinstance(source_refs, list) or not source_refs:
        errors.append("source_refs_invalid")
    else:
        for index, ref in enumerate(source_refs):
            if not _valid_source_ref(ref):
                errors.append(f"invalid_source_ref:{index}")

    sensitivity = metadata.get("sensitivity")
    if not _nonempty_string(sensitivity):
        errors.append("sensitivity_invalid")
    elif sensitivity not in sensitivities:
        errors.append("sensitivity_not_allowed")

    if metadata.get("raw_data_included") is not False:
        errors.append("raw_data_forbidden")
    if metadata.get("retention_class") not in RETENTION_CLASSES:
        errors.append("retention_class_invalid")

    supersedes = metadata.get("supersedes")
    if supersedes is not None and (
        not isinstance(supersedes, str) or not HANDOFF_ID_PATTERN.fullmatch(supersedes)
    ):
        errors.append("supersedes_invalid")
    elif supersedes is not None and supersedes == handoff_id:
        errors.append("handoff_supersedes_self")

    for field in ("assumptions", "uncertainties"):
        value = metadata.get(field)
        if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
            errors.append(f"{field}_invalid")

    consultation_fields = HANDOFF_OPTIONAL_FIELDS & set(metadata)
    if purpose in {"review-request", "consultation-response"}:
        hop_count = metadata.get("hop_count")
        max_hops = metadata.get("max_hops")
        if (
            isinstance(hop_count, bool)
            or isinstance(max_hops, bool)
            or not isinstance(hop_count, int)
            or not isinstance(max_hops, int)
        ):
            errors.append("consultation_hop_fields_missing")
        elif max_hops != 1 or hop_count < 0 or hop_count > max_hops:
            errors.append("consultation_hop_limit_exceeded")

        if purpose == "review-request":
            requested = metadata.get("requested_fields")
            if not _string_list(requested) or not requested:
                errors.append("consultation_requested_fields_missing")
            else:
                assert isinstance(requested, list)
                if len(set(requested)) != len(requested):
                    errors.append("consultation_requested_fields_duplicate")
            if metadata.get("in_reply_to") is not None:
                errors.append("consultation_request_has_parent")
            if "returned_fields" in metadata:
                errors.append("consultation_request_has_returned_fields")
            if hop_count != 0:
                errors.append("consultation_request_hop_invalid")
            if "response_deadline" not in metadata:
                errors.append("consultation_response_deadline_missing")
            else:
                deadline = _parse_datetime(
                    metadata.get("response_deadline"),
                    field="response_deadline",
                    errors=errors,
                )
                if deadline is not None:
                    if deadline <= now:
                        errors.append("consultation_response_deadline_expired")
                    if valid_until is not None and deadline > valid_until:
                        errors.append("consultation_response_deadline_after_validity")
        else:
            in_reply_to = metadata.get("in_reply_to")
            if (
                not isinstance(in_reply_to, str)
                or not HANDOFF_ID_PATTERN.fullmatch(in_reply_to)
            ):
                errors.append("consultation_in_reply_to_invalid")
            elif in_reply_to == handoff_id:
                errors.append("consultation_response_self_reference")
            returned = metadata.get("returned_fields")
            if not _string_list(returned) or not returned:
                errors.append("consultation_returned_fields_invalid")
            else:
                assert isinstance(returned, list)
                if len(set(returned)) != len(returned):
                    errors.append("consultation_returned_fields_duplicate")
            if "requested_fields" in metadata:
                errors.append("consultation_response_has_requested_fields")
            if "response_deadline" in metadata:
                errors.append("consultation_response_has_deadline")
            if hop_count != 1:
                errors.append("consultation_response_hop_invalid")
    elif consultation_fields:
        errors.append("consultation_fields_without_consultation_purpose")

    return errors
