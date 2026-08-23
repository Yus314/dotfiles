#!/usr/bin/env python3
"""Append-only, redacted, cross-node archive for Hermes sessions."""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import math
import os
import re
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Iterator, Sequence

DEFAULT_SOURCES = ("cli", "discord", "telegram")
ARCHIVE_SCHEMA_VERSION = 1
# Bump whenever the Hermes redaction/export policy or archive payload contract changes.
EXPORT_POLICY_VERSION = 2
ARCHIVE_RECORD_FIELDS = frozenset(
    {
        "id",
        "source",
        "model",
        "started_at",
        "ended_at",
        "end_reason",
        "message_count",
        "tool_call_count",
        "input_tokens",
        "output_tokens",
        "cache_read_tokens",
        "cache_write_tokens",
        "reasoning_tokens",
        "estimated_cost_usd",
        "actual_cost_usd",
        "cost_status",
        "cost_source",
        "pricing_version",
        "api_call_count",
        "rewind_count",
        "archived",
        "profile_name",
        "messages",
        "segments",
    }
)


def default_data_dir() -> Path:
    return (
        Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
        / "hermes-session-archive"
    )


def default_state_dir() -> Path:
    return (
        Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
        / "hermes-session-archive"
    )


def profile_home(hermes_home: Path, profile: str) -> Path:
    return hermes_home if profile == "default" else hermes_home / "profiles" / profile


def safe_component(value: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9._-]+", "_", value).strip("._")
    if not safe:
        raise ValueError(f"unsafe empty path component derived from {value!r}")
    return safe


def atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    except BaseException:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temporary)
        raise


@contextlib.contextmanager
def exclusive_lock(path: Path) -> Iterator[None]:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+", encoding="utf-8") as stream:
        os.chmod(path, 0o600)
        fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
        yield


def load_manifest(path: Path) -> dict[str, dict[str, Any]]:
    if not path.exists():
        return {}
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"manifest must be a JSON object: {path}")
    return value


def session_fingerprint(row: sqlite3.Row) -> str:
    fields = {
        "export_policy": EXPORT_POLICY_VERSION,
        "id": row["id"],
        "title": row["title"],
        "ended_at": row["ended_at"],
        "end_reason": row["end_reason"],
        "message_rows": row["message_rows"],
        "max_message_id": row["max_message_id"],
        "max_message_timestamp": row["max_message_timestamp"],
        "active_rows": row["active_rows"],
        "compacted_rows": row["compacted_rows"],
        "rewind_count": row["rewind_count"],
        "source_session_digest": row["source_session_digest"],
        "source_message_digest": row["source_message_digest"],
    }
    encoded = json.dumps(fields, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()[:24]


def payload_digest(record: dict[str, Any]) -> str:
    payload = {
        key: value for key, value in record.items() if key != "_hermes_session_archive"
    }
    encoded = json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def digest_values(*values: Any) -> str:
    normalized = [
        {"bytes": value.hex()} if isinstance(value, bytes) else value
        for value in values
    ]
    encoded = json.dumps(
        normalized,
        ensure_ascii=False,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


class XorDigest:
    """Order-independent aggregate over rows that include a unique message ID."""

    def __init__(self) -> None:
        self.value = 0

    def step(self, *values: Any) -> None:
        self.value ^= int(digest_values(*values), 16)

    def finalize(self) -> str:
        return f"{self.value:064x}"


def quoted_identifier(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def candidate_sessions(
    db_path: Path,
    sources: Sequence[str],
    newer_than_days: int,
    scan_limit: int,
) -> list[sqlite3.Row]:
    if not db_path.exists():
        return []
    if not sources:
        raise ValueError("at least one source is required")
    connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        session_columns = [
            row[1] for row in connection.execute("PRAGMA table_info(sessions)")
        ]
        message_columns = [
            row[1] for row in connection.execute("PRAGMA table_info(messages)")
        ]
        if not session_columns or not message_columns:
            raise ValueError("Hermes session database schema is incomplete")
        connection.create_function(
            "archive_row_digest", -1, digest_values, deterministic=True
        )
        connection.create_aggregate(
            "archive_xor_digest",
            -1,
            XorDigest,  # type: ignore[arg-type]
        )
        session_digest_expression = ", ".join(
            f"s.{quoted_identifier(column)}" for column in session_columns
        )
        message_digest_expression = ", ".join(
            f"m.{quoted_identifier(column)}" for column in message_columns
        )
        cutoff = time.time() - newer_than_days * 86400
        placeholders = ",".join("?" for _ in sources)
        activity_filter = ""
        parameters: list[Any] = [*sources]
        if newer_than_days > 0:
            activity_filter = "AND MAX(COALESCE(m.timestamp, s.started_at)) >= ?"
            parameters.append(cutoff)
        query = f"""
        SELECT
          s.id, s.source, s.title, s.started_at, s.ended_at, s.end_reason,
          s.rewind_count,
          archive_row_digest({session_digest_expression}) AS source_session_digest,
          archive_xor_digest({message_digest_expression}) AS source_message_digest,
          COUNT(m.id) AS message_rows,
          COALESCE(MAX(m.id), 0) AS max_message_id,
          COALESCE(MAX(m.timestamp), 0) AS max_message_timestamp,
          COALESCE(SUM(CASE WHEN m.active = 1 THEN 1 ELSE 0 END), 0) AS active_rows,
          COALESCE(SUM(CASE WHEN m.compacted = 1 THEN 1 ELSE 0 END), 0) AS compacted_rows
        FROM sessions AS s
        LEFT JOIN messages AS m ON m.session_id = s.id
        WHERE s.source IN ({placeholders})
        GROUP BY s.id
        HAVING COUNT(m.id) >= 1 {activity_filter}
        ORDER BY MAX(COALESCE(m.timestamp, s.started_at)) DESC
        LIMIT ?
        """
        parameters.append(scan_limit)
        return list(connection.execute(query, parameters))
    finally:
        connection.close()


def validate_export(path: Path, expected_session_id: str) -> dict[str, Any]:
    with path.open(encoding="utf-8") as stream:
        rows = [json.loads(line) for line in stream if line.strip()]
    if len(rows) != 1:
        raise ValueError(f"expected one exported session, got {len(rows)}")
    record = rows[0]
    if record.get("id") != expected_session_id:
        raise ValueError(
            f"exported session ID {record.get('id')!r} does not match {expected_session_id!r}"
        )
    if not isinstance(record.get("messages"), list):
        raise ValueError("exported session has no messages list")
    if any(not isinstance(message, dict) for message in record["messages"]):
        raise ValueError("exported session contains a non-object message")
    for message in record["messages"]:
        timestamp = message.get("timestamp")
        if timestamp is not None and (
            not isinstance(timestamp, (int, float))
            or isinstance(timestamp, bool)
            or not math.isfinite(float(timestamp))
        ):
            raise ValueError(
                "exported session contains a non-finite numeric message timestamp"
            )
    return record


def sanitize_export_record(record: dict[str, Any]) -> dict[str, Any]:
    """Keep only fields whose free text is covered by Hermes' --redact pass.

    Hermes v0.19 recursively redacts ``messages`` and ``segments`` but leaves
    top-level strings such as ``system_prompt`` and ``title`` untouched. Those
    unredacted fields are intentionally omitted from the synchronized archive.
    """
    return {key: value for key, value in record.items() if key in ARCHIVE_RECORD_FIELDS}


def validate_archive_identity(
    record: dict[str, Any],
    *,
    node: str,
    profile: str,
    fingerprint: str,
    required: bool,
) -> None:
    unexpected_fields = (
        set(record) - ARCHIVE_RECORD_FIELDS - {"_hermes_session_archive"}
    )
    if unexpected_fields:
        raise ValueError(
            f"archive contains disallowed top-level fields: {sorted(unexpected_fields)}"
        )
    metadata = record.get("_hermes_session_archive")
    if metadata is None and not required:
        return
    if not isinstance(metadata, dict):
        raise ValueError("archive metadata is missing or invalid")
    if metadata.get("schema") != ARCHIVE_SCHEMA_VERSION:
        raise ValueError("archive metadata schema is unsupported")
    if metadata.get("export_policy") != EXPORT_POLICY_VERSION:
        raise ValueError("archive export policy is unsupported")
    expected = {
        "node": node,
        "profile": profile,
        "fingerprint": fingerprint,
    }
    for key, value in expected.items():
        if metadata.get(key) != value:
            raise ValueError(
                f"archive metadata {key} {metadata.get(key)!r} does not match {value!r}"
            )
    sequence = metadata.get("sequence")
    if type(sequence) is not int or sequence < 1:
        raise ValueError("archive sequence must be a positive integer")
    exported_at = metadata.get("exported_at")
    if (
        not isinstance(exported_at, (int, float))
        or isinstance(exported_at, bool)
        or not math.isfinite(float(exported_at))
    ):
        raise ValueError("archive exported_at must be finite")
    revision = metadata.get("source_revision")
    if not isinstance(revision, dict):
        raise ValueError("archive source_revision must be an object")
    for key in (
        "rewind_count",
        "max_message_id",
        "message_rows",
        "active_rows",
        "compacted_rows",
    ):
        value = revision.get(key)
        if type(value) is not int or value < 0:
            raise ValueError(f"archive source_revision {key} must be non-negative")
    for key in ("source_session_digest", "source_message_digest"):
        value = revision.get(key)
        if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value):
            raise ValueError(f"archive source_revision {key} is invalid")
    expected_payload_digest = metadata.get("payload_digest")
    if not isinstance(expected_payload_digest, str) or not re.fullmatch(
        r"[0-9a-f]{64}", expected_payload_digest
    ):
        raise ValueError("archive payload digest is invalid")
    if payload_digest(record) != expected_payload_digest:
        raise ValueError("archive payload digest mismatch")


def export_one(
    hermes_command: str,
    profile: str,
    session_id: str,
    destination: Path,
    archive_metadata: dict[str, Any],
) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Syncthing intentionally ignores its own .syncthing.*.tmp convention.
    # Keep the in-progress export invisible to the peer until the atomic rename.
    fd, temporary_name = tempfile.mkstemp(
        prefix=".syncthing.", suffix=".tmp", dir=destination.parent
    )
    os.close(fd)
    temporary = Path(temporary_name)
    try:
        command = [hermes_command]
        if profile != "default":
            command.extend(["--profile", profile])
        command.extend(
            [
                "sessions",
                "export",
                "--format",
                "jsonl",
                str(temporary),
                "--session-id",
                session_id,
                "--redact",
                "--yes",
            ]
        )
        subprocess.run(command, check=True, capture_output=True, text=True)
        record = sanitize_export_record(validate_export(temporary, session_id))
        archive_metadata = dict(archive_metadata)
        archive_metadata["payload_digest"] = payload_digest(record)
        record["_hermes_session_archive"] = archive_metadata
        with temporary.open("w", encoding="utf-8") as stream:
            json.dump(record, stream, ensure_ascii=False, separators=(",", ":"))
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, destination)
    except BaseException:
        with contextlib.suppress(FileNotFoundError):
            temporary.unlink()
        raise


def next_sequence(
    session_dir: Path, manifest_entry: dict[str, Any], session_id: str
) -> int:
    maximum = manifest_entry.get("sequence", 0)
    if type(maximum) is not int or maximum < 0:
        maximum = 0
    if session_dir.exists():
        for path in session_dir.glob("*.jsonl"):
            try:
                record = validate_export(path, session_id)
                metadata = record.get("_hermes_session_archive") or {}
                sequence = metadata.get("sequence", 0)
                if type(sequence) is int and sequence > maximum:
                    maximum = sequence
            except (OSError, TypeError, ValueError, json.JSONDecodeError):
                continue
    return maximum + 1


def export_sessions(args: argparse.Namespace) -> int:
    archive_dir = args.archive_dir.expanduser().resolve()
    state_dir = args.state_dir.expanduser().resolve()
    hermes_home = args.hermes_home.expanduser().resolve()
    node = safe_component(args.node)
    profiles = [safe_component(part) for part in args.profiles.split(",") if part]
    sources = [part for part in args.sources.split(",") if part]
    manifest_path = state_dir / node / "manifest.json"
    lock_path = state_dir / node / "export.lock"
    exported = 0

    with exclusive_lock(lock_path):
        manifest = load_manifest(manifest_path)
        for profile in profiles:
            db_path = profile_home(hermes_home, profile) / "state.db"
            for row in candidate_sessions(
                db_path, sources, args.newer_than_days, args.scan_limit
            ):
                fingerprint = session_fingerprint(row)
                session_id = str(row["id"])
                key = f"{profile}:{session_id}"
                current = manifest.get(key, {})
                relative = (
                    Path(node)
                    / profile
                    / safe_component(session_id)
                    / f"{fingerprint}.jsonl"
                )
                destination = archive_dir / relative
                if destination.exists():
                    try:
                        record = validate_export(destination, session_id)
                        validate_archive_identity(
                            record,
                            node=node,
                            profile=profile,
                            fingerprint=fingerprint,
                            required=True,
                        )
                    except (
                        OSError,
                        TypeError,
                        ValueError,
                        json.JSONDecodeError,
                    ) as error:
                        if args.dry_run:
                            print(
                                f"warning: invalid archive would be quarantined "
                                f"{destination}: {error}",
                                file=sys.stderr,
                            )
                        else:
                            quarantine = destination.with_name(
                                f"{destination.stem}.corrupt-{time.time_ns()}.jsonl.bad"
                            )
                            os.replace(destination, quarantine)
                            print(
                                f"warning: quarantined invalid archive {destination} as "
                                f"{quarantine.name}: {error}",
                                file=sys.stderr,
                            )
                    else:
                        sequence = record["_hermes_session_archive"]["sequence"]
                        manifest[key] = {
                            "fingerprint": fingerprint,
                            "path": str(relative),
                            "sequence": sequence,
                        }
                        continue
                if exported >= args.max_exports:
                    break
                if args.dry_run:
                    print(
                        json.dumps(
                            {
                                "node": node,
                                "profile": profile,
                                "session_id": session_id,
                                "source": row["source"],
                                "title": row["title"],
                                "fingerprint": fingerprint,
                            },
                            ensure_ascii=False,
                        )
                    )
                else:
                    sequence = next_sequence(destination.parent, current, session_id)
                    export_one(
                        args.hermes_command,
                        profile,
                        session_id,
                        destination,
                        {
                            "schema": ARCHIVE_SCHEMA_VERSION,
                            "export_policy": EXPORT_POLICY_VERSION,
                            "node": node,
                            "profile": profile,
                            "fingerprint": fingerprint,
                            "sequence": sequence,
                            "exported_at": time.time(),
                            "source_revision": {
                                "rewind_count": row["rewind_count"],
                                "max_message_id": row["max_message_id"],
                                "message_rows": row["message_rows"],
                                "active_rows": row["active_rows"],
                                "compacted_rows": row["compacted_rows"],
                                "ended_at": row["ended_at"],
                                "source_session_digest": row["source_session_digest"],
                                "source_message_digest": row["source_message_digest"],
                            },
                        },
                    )
                    manifest[key] = {
                        "fingerprint": fingerprint,
                        "path": str(relative),
                        "sequence": sequence,
                    }
                    atomic_json(manifest_path, manifest)
                exported += 1
            if exported >= args.max_exports:
                break
        if not args.dry_run:
            atomic_json(manifest_path, manifest)

    print(f"exported={exported} node={node} archive={archive_dir}")
    return exported


def record_rank(
    record: dict[str, Any], path: Path
) -> tuple[int, int, int, int, float, float, int, int, str]:
    messages = record.get("messages") or []
    message_times = [float(message.get("timestamp") or 0) for message in messages]
    logical_time = max(
        [
            float(record.get("started_at") or 0),
            float(record.get("ended_at") or 0),
            *message_times,
        ]
    )
    metadata = record.get("_hermes_session_archive") or {}
    revision = metadata.get("source_revision") or {}
    return (
        int(metadata.get("schema") == ARCHIVE_SCHEMA_VERSION),
        int(metadata.get("sequence") or 0),
        int(revision.get("rewind_count") or 0),
        int(revision.get("max_message_id") or 0),
        float(metadata.get("exported_at") or 0),
        logical_time,
        len(messages),
        path.stat().st_mtime_ns,
        str(metadata.get("payload_digest") or ""),
    )


def archive_records(
    archive_dir: Path,
) -> dict[str, tuple[Path, dict[str, Any], str]]:
    selected: dict[str, tuple[Path, dict[str, Any], str]] = {}
    if not archive_dir.exists():
        return selected
    for path in archive_dir.glob("*/*/*/*.jsonl"):
        try:
            relative = path.relative_to(archive_dir)
            node, profile, session_id, _version = relative.parts
            record = validate_export(path, session_id)
            validate_archive_identity(
                record,
                node=node,
                profile=profile,
                fingerprint=path.stem,
                required=True,
            )
            archive_digest = file_digest(path)
            current_rank = record_rank(record, path)
            key = f"{node}:{profile}:{session_id}"
            previous = selected.get(key)
            if previous is None or current_rank > record_rank(previous[1], previous[0]):
                selected[key] = (path, record, archive_digest)
        except (OSError, TypeError, ValueError, json.JSONDecodeError) as error:
            print(f"warning: skipping invalid archive {path}: {error}", file=sys.stderr)
    return selected


def initialize_index(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS sessions (
          session_key TEXT PRIMARY KEY,
          node TEXT NOT NULL,
          profile TEXT NOT NULL,
          session_id TEXT NOT NULL,
          version_path TEXT NOT NULL,
          archive_digest TEXT NOT NULL DEFAULT '',
          title TEXT,
          source TEXT,
          started_at REAL,
          ended_at REAL,
          message_count INTEGER NOT NULL
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
          session_key UNINDEXED,
          role UNINDEXED,
          timestamp UNINDEXED,
          content,
          tokenize='unicode61'
        );
        """
    )
    columns = {row[1] for row in connection.execute("PRAGMA table_info(sessions)")}
    if "archive_digest" not in columns:
        connection.execute(
            "ALTER TABLE sessions ADD COLUMN archive_digest TEXT NOT NULL DEFAULT ''"
        )


def reindex(args: argparse.Namespace) -> int:
    archive_dir = args.archive_dir.expanduser().resolve()
    index_path = args.index.expanduser().resolve()
    index_path.parent.mkdir(parents=True, exist_ok=True)
    selected = archive_records(archive_dir)
    connection = sqlite3.connect(index_path)
    initialize_index(connection)
    changed = 0
    try:
        existing = {
            row[0]: (row[1], row[2])
            for row in connection.execute(
                "SELECT session_key, version_path, archive_digest FROM sessions"
            )
        }
        for key in set(existing) - set(selected):
            connection.execute("DELETE FROM messages_fts WHERE session_key = ?", (key,))
            connection.execute("DELETE FROM sessions WHERE session_key = ?", (key,))
            changed += 1
        for key, (path, record, archive_digest) in selected.items():
            version_path = str(path.relative_to(archive_dir))
            if existing.get(key) == (version_path, archive_digest):
                continue
            node, profile, session_id, _version = Path(version_path).parts
            messages = record.get("messages") or []
            connection.execute("DELETE FROM messages_fts WHERE session_key = ?", (key,))
            connection.execute(
                """
                INSERT INTO sessions(
                  session_key, node, profile, session_id, version_path,
                  archive_digest, title, source, started_at, ended_at,
                  message_count
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(session_key) DO UPDATE SET
                  version_path=excluded.version_path,
                  archive_digest=excluded.archive_digest,
                  title=excluded.title,
                  source=excluded.source,
                  started_at=excluded.started_at,
                  ended_at=excluded.ended_at,
                  message_count=excluded.message_count
                """,
                (
                    key,
                    node,
                    profile,
                    session_id,
                    version_path,
                    archive_digest,
                    record.get("title"),
                    record.get("source"),
                    record.get("started_at"),
                    record.get("ended_at"),
                    len(messages),
                ),
            )
            for message in messages:
                content = message.get("content")
                if isinstance(content, str) and content.strip():
                    connection.execute(
                        "INSERT INTO messages_fts(session_key, role, timestamp, content) VALUES (?, ?, ?, ?)",
                        (key, message.get("role"), message.get("timestamp"), content),
                    )
            changed += 1
        connection.commit()
        os.chmod(index_path, 0o600)
    finally:
        connection.close()
    print(f"indexed={len(selected)} changed={changed} index={index_path}")
    return changed


def fts_query(text: str) -> str:
    terms = re.findall(r"[^\W_]+", text, flags=re.UNICODE)
    if not terms:
        raise ValueError("search query contains no searchable terms")
    return " AND ".join('"' + term.replace('"', '""') + '"' for term in terms)


def search(args: argparse.Namespace) -> int:
    index_path = args.index.expanduser().resolve()
    if not index_path.exists():
        raise FileNotFoundError(
            f"index does not exist; run reindex first: {index_path}"
        )
    connection = sqlite3.connect(f"file:{index_path}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        rows = connection.execute(
            """
            SELECT s.node, s.profile, s.session_id, s.title, s.source,
                   s.started_at, s.version_path, messages_fts.role,
                   snippet(messages_fts, 3, '[', ']', ' … ', 24) AS snippet,
                   bm25(messages_fts) AS score
            FROM messages_fts
            JOIN sessions AS s ON s.session_key = messages_fts.session_key
            WHERE messages_fts MATCH ?
            ORDER BY score, s.started_at DESC
            LIMIT ?
            """,
            (fts_query(args.query), args.limit),
        ).fetchall()
    finally:
        connection.close()
    for row in rows:
        value = dict(row)
        if args.json:
            print(json.dumps(value, ensure_ascii=False))
        else:
            title = value["title"] or "(untitled)"
            print(
                f"{value['node']}/{value['profile']} {value['source']} "
                f"{value['session_id']} {title}\n  {value['role']}: {value['snippet']}\n"
                f"  archive: {value['version_path']}"
            )
    return len(rows)


def add_common_paths(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--archive-dir", type=Path, default=default_data_dir())
    parser.add_argument("--state-dir", type=Path, default=default_state_dir())
    parser.add_argument("--index", type=Path, default=default_state_dir() / "index.db")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    export_parser = subparsers.add_parser("export", help="export changed sessions")
    add_common_paths(export_parser)
    export_parser.add_argument(
        "--hermes-home", type=Path, default=Path.home() / ".hermes"
    )
    export_parser.add_argument("--hermes-command", default="hermes")
    export_parser.add_argument("--node", default=socket.gethostname().split(".")[0])
    export_parser.add_argument("--profiles", default="default")
    export_parser.add_argument("--sources", default=",".join(DEFAULT_SOURCES))
    export_parser.add_argument("--newer-than-days", type=int, default=0)
    export_parser.add_argument("--scan-limit", type=int, default=50000)
    export_parser.add_argument("--max-exports", type=int, default=50)
    export_parser.add_argument("--dry-run", action="store_true")

    index_parser = subparsers.add_parser("reindex", help="refresh the local FTS index")
    add_common_paths(index_parser)

    search_parser = subparsers.add_parser("search", help="search the local FTS index")
    add_common_paths(search_parser)
    search_parser.add_argument("query")
    search_parser.add_argument("--limit", type=int, default=20)
    search_parser.add_argument("--json", action="store_true")

    sync_parser = subparsers.add_parser(
        "sync", help="export changed sessions and reindex"
    )
    add_common_paths(sync_parser)
    sync_parser.add_argument(
        "--hermes-home", type=Path, default=Path.home() / ".hermes"
    )
    sync_parser.add_argument("--hermes-command", default="hermes")
    sync_parser.add_argument("--node", default=socket.gethostname().split(".")[0])
    sync_parser.add_argument("--profiles", default="default")
    sync_parser.add_argument("--sources", default=",".join(DEFAULT_SOURCES))
    sync_parser.add_argument("--newer-than-days", type=int, default=0)
    sync_parser.add_argument("--scan-limit", type=int, default=50000)
    sync_parser.add_argument("--max-exports", type=int, default=50)
    sync_parser.add_argument("--dry-run", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "export":
            export_sessions(args)
        elif args.command == "reindex":
            reindex(args)
        elif args.command == "search":
            search(args)
        elif args.command == "sync":
            export_sessions(args)
            if not args.dry_run:
                reindex(args)
        else:
            parser.error(f"unknown command: {args.command}")
    except (OSError, ValueError, sqlite3.Error, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
