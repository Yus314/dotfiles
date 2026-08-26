#!/usr/bin/env python3
"""Exercise the approved disposable Honcho topology without touching real math memory."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import secrets
import sys
from pathlib import Path
from typing import Any


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_api_key() -> str:
    key = os.getenv("HONCHO_API_KEY", "").strip()
    if key:
        return key
    try:
        from hermes_cli.config import load_env

        key = load_env().get("HONCHO_API_KEY", "").strip()
    except Exception:
        key = ""
    if not key:
        raise RuntimeError("HONCHO_API_KEY is missing")
    return key


def listed(scope: Any) -> list[Any]:
    return list(scope.list(size=100).items)


def has_exact(scope: Any, content: str) -> bool:
    return any(item.content == content for item in listed(scope))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--suffix", default="")
    parser.add_argument("--canonical-path", action="append", type=Path, default=[])
    args = parser.parse_args()

    suffix = args.suffix or secrets.token_hex(8)
    workspace = f"hermes-math-disposable-{suffix}"
    user_id = f"kaki-math-disposable-{suffix}"
    lawliet_ai_id = f"math-lawliet-disposable-{suffix}"
    watari_ai_id = f"math-watari-disposable-{suffix}"
    shared_token = f"benign-shared-user-{suffix}"
    self_token = f"benign-user-self-{suffix}"
    lawliet_token = f"benign-lawliet-attribution-{suffix}"
    watari_token = f"benign-watari-attribution-{suffix}"
    contradiction_token = f"benign-synthetic-contradiction-{suffix}"

    before = {str(path): sha256_file(path) for path in args.canonical_path}
    report: dict[str, Any] = {
        "schema": "hermes-math-disposable-honcho-topology/v1",
        "workspace": workspace,
        "identities": {
            "shared_user_peer": user_id,
            "lawliet_ai_peer": lawliet_ai_id,
            "watari_ai_peer": watari_ai_id,
            "ai_peers_distinct": lawliet_ai_id != watari_ai_id,
        },
        "secret_readiness": {"HONCHO_API_KEY": "present"},
        "token_sha256": {
            "shared_user": sha256_text(shared_token),
            "user_self": sha256_text(self_token),
            "lawliet_ai": sha256_text(lawliet_token),
            "watari_ai": sha256_text(watari_token),
            "contradiction": sha256_text(contradiction_token),
        },
        "canonical_files_before": before,
        "cleanup": {"conclusions_removed": False, "workspace_deleted": False},
    }
    created: list[tuple[Any, str]] = []
    workspace_client: Any | None = None

    try:
        from honcho import Honcho

        key = load_api_key()
        lawliet = Honcho(api_key=key, workspace_id=workspace, timeout=30)
        watari = Honcho(api_key=key, workspace_id=workspace, timeout=30)
        workspace_client = lawliet

        disposable_metadata = {"purpose": "hermes-math-topology-test", "disposable": True}
        # Supplying metadata forces SDK get/create; bare peer() is lazy and an
        # immediate conclusions_of(...).create(...) would target a missing peer.
        lawliet_user = lawliet.peer(user_id, metadata=disposable_metadata)
        watari_user = watari.peer(user_id, metadata=disposable_metadata)
        lawliet_ai = lawliet.peer(lawliet_ai_id, metadata=disposable_metadata)
        watari_ai = watari.peer(watari_ai_id, metadata=disposable_metadata)

        lawliet_about_user = lawliet_ai.conclusions_of(lawliet_user)
        watari_about_user = watari_ai.conclusions_of(watari_user)
        user_about_self_lawliet = lawliet_user.conclusions_of(lawliet_user)
        user_about_self_watari = watari_user.conclusions_of(watari_user)
        lawliet_about_self = lawliet_ai.conclusions_of(lawliet_ai)
        watari_about_self = watari_ai.conclusions_of(watari_ai)

        item = lawliet_about_user.create([{"content": shared_token}])[0]
        created.append((lawliet_about_user, item.id))
        item = user_about_self_lawliet.create([{"content": self_token}])[0]
        created.append((user_about_self_lawliet, item.id))
        item = lawliet_about_self.create([{"content": lawliet_token}])[0]
        created.append((lawliet_about_self, item.id))
        item = watari_about_self.create([{"content": watari_token}])[0]
        created.append((watari_about_self, item.id))
        contradiction = watari_about_user.create([{"content": contradiction_token}])[0]
        created.append((watari_about_user, contradiction.id))

        report["authoritative_checks"] = {
            "lawliet_observer_sees_own_user_conclusion": has_exact(lawliet_about_user, shared_token),
            "watari_observer_sees_lawliet_user_conclusion": has_exact(watari_about_user, shared_token),
            "shared_user_self_scope_visible_from_watari": has_exact(user_about_self_watari, self_token),
            "lawliet_ai_attribution_isolated": (
                has_exact(lawliet_about_self, lawliet_token)
                and not has_exact(watari_about_self, lawliet_token)
            ),
            "watari_ai_attribution_isolated": (
                has_exact(watari_about_self, watari_token)
                and not has_exact(lawliet_about_self, watari_token)
            ),
            "contradiction_attributed_to_watari": (
                contradiction.observer_id == watari_ai_id
                and contradiction.observed_id == user_id
                and has_exact(watari_about_user, contradiction_token)
            ),
        }
        report["created_object_ids"] = [item_id for _, item_id in created]
    except Exception as exc:
        report["error"] = f"{type(exc).__name__}: {exc}"
    finally:
        cleanup_errors: list[str] = []
        for scope, item_id in reversed(created):
            try:
                scope.delete(item_id)
            except Exception as exc:
                cleanup_errors.append(f"conclusion {item_id}: {type(exc).__name__}")
        report["cleanup"]["conclusions_removed"] = not cleanup_errors
        if workspace_client is not None:
            try:
                workspace_client.delete_workspace(workspace)
                report["cleanup"]["workspace_deleted"] = True
            except Exception as exc:
                cleanup_errors.append(f"workspace: {type(exc).__name__}")
        if cleanup_errors:
            report["cleanup"]["errors"] = cleanup_errors

    after = {str(path): sha256_file(path) for path in args.canonical_path}
    report["canonical_files_after"] = after
    report["canonical_files_unchanged"] = before == after
    checks = report.get("authoritative_checks", {})
    report["result"] = "pass" if (
        checks
        and all(checks.values())
        and report["canonical_files_unchanged"]
        and report["cleanup"]["conclusions_removed"]
        and report["cleanup"]["workspace_deleted"]
        and "error" not in report
    ) else "blocked"

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({
        "result": report["result"],
        "output": str(args.output),
        "workspace": workspace,
        "cleanup": report["cleanup"],
        "checks": checks,
        "error": report.get("error"),
    }, indent=2, sort_keys=True))
    return 0 if report["result"] == "pass" else 2


if __name__ == "__main__":
    sys.exit(main())
