import importlib.util
import json
import sqlite3
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "session_archive.py"
SPEC = importlib.util.spec_from_file_location("session_archive", SCRIPT)
assert SPEC and SPEC.loader
archive = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(archive)


def create_state_db(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path)
    connection.executescript(
        """
        CREATE TABLE sessions (
          id TEXT PRIMARY KEY, source TEXT NOT NULL, title TEXT, started_at REAL,
          ended_at REAL, end_reason TEXT, rewind_count INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE messages (
          id INTEGER PRIMARY KEY, session_id TEXT NOT NULL, role TEXT NOT NULL,
          content TEXT, timestamp REAL NOT NULL, active INTEGER NOT NULL DEFAULT 1,
          compacted INTEGER NOT NULL DEFAULT 0
        );
        """
    )
    connection.execute(
        "INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?, ?)",
        ("session-one", "cli", "Shared design", 2_000_000_000, None, None, 0),
    )
    connection.executemany(
        "INSERT INTO messages VALUES (?, ?, ?, ?, ?, ?, ?)",
        [
            (1, "session-one", "user", "selection first undo", 2_000_000_001, 1, 0),
            (
                2,
                "session-one",
                "assistant",
                "Use one undo episode",
                2_000_000_002,
                1,
                0,
            ),
        ],
    )
    connection.execute(
        "INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?, ?)",
        (
            "subagent-one",
            "subagent",
            "Excluded",
            2_000_000_000,
            2_000_000_010,
            "agent_close",
            0,
        ),
    )
    connection.executemany(
        "INSERT INTO messages VALUES (?, ?, ?, ?, ?, ?, ?)",
        [
            (3, "subagent-one", "user", "hidden worker", 2_000_000_003, 1, 0),
            (4, "subagent-one", "assistant", "not archived", 2_000_000_004, 1, 0),
        ],
    )
    connection.commit()
    connection.close()


def create_fake_hermes(path: Path) -> None:
    path.write_text(
        """#!/usr/bin/env python3
import json, pathlib, sys
args = sys.argv[1:]
out = pathlib.Path(args[args.index('jsonl') + 1])
sid = args[args.index('--session-id') + 1]
assert '--redact' in args
assert args[args.index('--format') + 1] == 'jsonl'
messages_path = pathlib.Path(__file__).with_name('fake-messages.json')
messages = [
    {'role': 'user', 'content': 'selection first undo', 'timestamp': 2000000001},
    {'role': 'assistant', 'content': 'Use one undo episode', 'timestamp': 2000000002},
]
if messages_path.exists():
    messages = json.loads(messages_path.read_text(encoding='utf-8'))
record = {
    'id': sid,
    'source': 'cli',
    'title': 'TOP_LEVEL_SECRET_TITLE',
    'system_prompt': 'TOP_LEVEL_SECRET_PROMPT',
    'model_config': {'api_key': 'TOP_LEVEL_SECRET_CONFIG'},
    'started_at': 2000000000,
    'ended_at': None,
    'messages': messages,
}
out.write_text(json.dumps(record) + '\\n', encoding='utf-8')
""",
        encoding="utf-8",
    )
    path.chmod(0o755)


def run_cli(*arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *arguments],
        check=True,
        capture_output=True,
        text=True,
    )


def seal_record(
    record: dict,
    *,
    node: str,
    profile: str,
    fingerprint: str,
    sequence: int,
    rewind_count: int = 0,
) -> dict:
    record = archive.sanitize_export_record(record)
    messages = record.get("messages", [])
    metadata = {
        "schema": archive.ARCHIVE_SCHEMA_VERSION,
        "export_policy": archive.EXPORT_POLICY_VERSION,
        "node": node,
        "profile": profile,
        "fingerprint": fingerprint,
        "sequence": sequence,
        "exported_at": 100 + sequence,
        "source_revision": {
            "rewind_count": rewind_count,
            "max_message_id": len(messages),
            "message_rows": len(messages),
            "active_rows": len(messages),
            "compacted_rows": 0,
            "ended_at": record.get("ended_at"),
            "source_session_digest": "0" * 64,
            "source_message_digest": "1" * 64,
        },
        "payload_digest": archive.payload_digest(record),
    }
    record["_hermes_session_archive"] = metadata
    return record


def test_candidates_include_one_message_session_with_recent_activity(
    tmp_path: Path,
) -> None:
    db_path = tmp_path / "state.db"
    create_state_db(db_path)
    connection = sqlite3.connect(db_path)
    connection.execute(
        "INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?, ?)",
        ("old-active", "cli", "Old active", 1, None, None, 0),
    )
    connection.execute(
        "INSERT INTO messages VALUES (?, ?, ?, ?, ?, ?, ?)",
        (10, "old-active", "user", "one message", 2_000_000_010, 1, 0),
    )
    connection.commit()
    connection.close()

    candidates = archive.candidate_sessions(db_path, ["cli"], 365, 100)
    assert "old-active" in {row["id"] for row in candidates}


def test_fingerprint_detects_same_length_content_role_and_policy_changes(
    tmp_path: Path, monkeypatch
) -> None:
    db_path = tmp_path / "state.db"
    create_state_db(db_path)

    first = archive.candidate_sessions(db_path, ["cli"], 0, 100)[0]
    first_fingerprint = archive.session_fingerprint(first)
    connection = sqlite3.connect(db_path)
    connection.execute(
        "UPDATE messages SET content = ?, role = ? WHERE id = ?",
        ("undo selection first", "assistant", 1),
    )
    connection.commit()
    connection.close()
    second = archive.candidate_sessions(db_path, ["cli"], 0, 100)[0]
    second_fingerprint = archive.session_fingerprint(second)
    assert second_fingerprint != first_fingerprint

    monkeypatch.setattr(
        archive, "EXPORT_POLICY_VERSION", archive.EXPORT_POLICY_VERSION + 1
    )
    assert archive.session_fingerprint(second) != second_fingerprint


def test_sync_is_redacted_immutable_and_searchable(tmp_path: Path) -> None:
    hermes_home = tmp_path / "hermes"
    archive_dir = tmp_path / "archive"
    state_dir = tmp_path / "state"
    fake_hermes = tmp_path / "hermes-command"
    create_state_db(hermes_home / "state.db")
    create_fake_hermes(fake_hermes)

    result = run_cli(
        "sync",
        "--hermes-home",
        str(hermes_home),
        "--hermes-command",
        str(fake_hermes),
        "--archive-dir",
        str(archive_dir),
        "--state-dir",
        str(state_dir),
        "--index",
        str(state_dir / "index.db"),
        "--node",
        "watari",
        "--newer-than-days",
        "3650",
    )
    assert "exported=1" in result.stdout
    exports = list(archive_dir.glob("watari/default/session-one/*.jsonl"))
    assert len(exports) == 1
    assert exports[0].stat().st_mode & 0o777 == 0o600
    assert not list(archive_dir.glob("watari/default/subagent-one/*.jsonl"))
    exported_text = exports[0].read_text(encoding="utf-8")
    assert "TOP_LEVEL_SECRET" not in exported_text
    exported_record = json.loads(exported_text)
    assert "title" not in exported_record
    assert "system_prompt" not in exported_record
    assert "model_config" not in exported_record

    second = run_cli(
        "sync",
        "--hermes-home",
        str(hermes_home),
        "--hermes-command",
        str(fake_hermes),
        "--archive-dir",
        str(archive_dir),
        "--state-dir",
        str(state_dir),
        "--index",
        str(state_dir / "index.db"),
        "--node",
        "watari",
        "--newer-than-days",
        "3650",
    )
    assert "exported=0" in second.stdout
    assert len(list(archive_dir.glob("watari/default/session-one/*.jsonl"))) == 1

    exports[0].unlink()
    repaired = run_cli(
        "sync",
        "--hermes-home",
        str(hermes_home),
        "--hermes-command",
        str(fake_hermes),
        "--archive-dir",
        str(archive_dir),
        "--state-dir",
        str(state_dir),
        "--index",
        str(state_dir / "index.db"),
        "--node",
        "watari",
        "--newer-than-days",
        "3650",
    )
    assert "exported=1" in repaired.stdout
    assert len(list(archive_dir.glob("watari/default/session-one/*.jsonl"))) == 1

    repaired_export = next(archive_dir.glob("watari/default/session-one/*.jsonl"))
    repaired_export.write_text("{}\n", encoding="utf-8")
    dry_run = run_cli(
        "export",
        "--hermes-home",
        str(hermes_home),
        "--hermes-command",
        str(fake_hermes),
        "--archive-dir",
        str(archive_dir),
        "--state-dir",
        str(state_dir),
        "--index",
        str(state_dir / "index.db"),
        "--node",
        "watari",
        "--newer-than-days",
        "3650",
        "--dry-run",
    )
    assert "would be quarantined" in dry_run.stderr
    assert repaired_export.read_text(encoding="utf-8") == "{}\n"
    assert not list(repaired_export.parent.glob("*.bad"))

    corrupt_repair = run_cli(
        "sync",
        "--hermes-home",
        str(hermes_home),
        "--hermes-command",
        str(fake_hermes),
        "--archive-dir",
        str(archive_dir),
        "--state-dir",
        str(state_dir),
        "--index",
        str(state_dir / "index.db"),
        "--node",
        "watari",
        "--newer-than-days",
        "3650",
    )
    assert "exported=1" in corrupt_repair.stdout
    assert "quarantined invalid archive" in corrupt_repair.stderr
    assert len(list(repaired_export.parent.glob("*.bad"))) == 1
    assert (
        json.loads(repaired_export.read_text(encoding="utf-8"))["id"] == "session-one"
    )

    search = run_cli(
        "search",
        "selection undo",
        "--archive-dir",
        str(archive_dir),
        "--state-dir",
        str(state_dir),
        "--index",
        str(state_dir / "index.db"),
        "--json",
    )
    row = json.loads(search.stdout)
    assert row["node"] == "watari"
    assert row["profile"] == "default"
    assert row["session_id"] == "session-one"
    assert "[selection]" in row["snippet"]


def test_changed_session_creates_new_version_and_replaces_index(tmp_path: Path) -> None:
    hermes_home = tmp_path / "hermes"
    archive_dir = tmp_path / "archive"
    state_dir = tmp_path / "state"
    fake_hermes = tmp_path / "hermes-command"
    create_state_db(hermes_home / "state.db")
    create_fake_hermes(fake_hermes)
    common = [
        "--hermes-home",
        str(hermes_home),
        "--hermes-command",
        str(fake_hermes),
        "--archive-dir",
        str(archive_dir),
        "--state-dir",
        str(state_dir),
        "--index",
        str(state_dir / "index.db"),
        "--node",
        "lawliet",
        "--newer-than-days",
        "3650",
    ]
    run_cli("sync", *common)

    connection = sqlite3.connect(hermes_home / "state.db")
    connection.execute(
        "INSERT INTO messages VALUES (?, ?, ?, ?, ?, ?, ?)",
        (5, "session-one", "user", "new continuation", 2_000_000_005, 1, 0),
    )
    connection.commit()
    connection.close()
    (tmp_path / "fake-messages.json").write_text(
        json.dumps(
            [
                {
                    "role": "user",
                    "content": "selection first undo",
                    "timestamp": 2_000_000_001,
                },
                {
                    "role": "assistant",
                    "content": "Use one undo episode",
                    "timestamp": 2_000_000_002,
                },
                {
                    "role": "user",
                    "content": "new continuation",
                    "timestamp": 2_000_000_005,
                },
            ]
        ),
        encoding="utf-8",
    )
    run_cli("sync", *common)

    assert len(list(archive_dir.glob("lawliet/default/session-one/*.jsonl"))) == 2
    connection = sqlite3.connect(state_dir / "index.db")
    assert connection.execute("SELECT message_count FROM sessions").fetchone()[0] == 3
    connection.close()
    search = run_cli(
        "search",
        "new continuation",
        "--archive-dir",
        str(archive_dir),
        "--state-dir",
        str(state_dir),
        "--index",
        str(state_dir / "index.db"),
        "--json",
    )
    assert json.loads(search.stdout)["session_id"] == "session-one"


def test_invalid_export_does_not_publish_or_advance_manifest(tmp_path: Path) -> None:
    hermes_home = tmp_path / "hermes"
    archive_dir = tmp_path / "archive"
    state_dir = tmp_path / "state"
    bad_hermes = tmp_path / "bad-hermes"
    create_state_db(hermes_home / "state.db")
    bad_hermes.write_text(
        "#!/usr/bin/env python3\nimport pathlib,sys\np=pathlib.Path(sys.argv[sys.argv.index('jsonl')+1]);p.write_text('{}\\n')\n",
        encoding="utf-8",
    )
    bad_hermes.chmod(0o755)

    result = subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "export",
            "--hermes-home",
            str(hermes_home),
            "--hermes-command",
            str(bad_hermes),
            "--archive-dir",
            str(archive_dir),
            "--state-dir",
            str(state_dir),
            "--node",
            "lawliet",
            "--newer-than-days",
            "3650",
        ],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 1
    assert not list(archive_dir.glob("**/*.jsonl"))
    manifest = state_dir / "lawliet" / "manifest.json"
    assert not manifest.exists() or "session-one" not in manifest.read_text(
        encoding="utf-8"
    )


def test_reindex_rejects_record_in_wrong_session_directory(tmp_path: Path) -> None:
    archive_dir = tmp_path / "archive"
    state_dir = tmp_path / "state"
    wrong_path = archive_dir / "watari" / "default" / "wrong-id" / "version.jsonl"
    wrong_path.parent.mkdir(parents=True)
    wrong_path.write_text(
        json.dumps(
            {
                "id": "actual-id",
                "source": "cli",
                "messages": [
                    {"role": "user", "content": "must not index", "timestamp": 1}
                ],
            }
        )
        + "\n",
        encoding="utf-8",
    )

    result = run_cli(
        "reindex",
        "--archive-dir",
        str(archive_dir),
        "--state-dir",
        str(state_dir),
        "--index",
        str(state_dir / "index.db"),
    )
    assert "indexed=0" in result.stdout
    assert "does not match" in result.stderr


def test_reindex_prefers_newer_rewind_even_with_fewer_active_messages(
    tmp_path: Path,
) -> None:
    archive_dir = tmp_path / "archive"
    state_dir = tmp_path / "state"
    session_dir = archive_dir / "watari" / "default" / "session-one"
    session_dir.mkdir(parents=True)

    def write_version(name: str, rewind_count: int, messages: list[dict]) -> None:
        record = seal_record(
            {
                "id": "session-one",
                "source": "cli",
                "title": "Rewind test",
                "started_at": 1,
                "messages": messages,
            },
            node="watari",
            profile="default",
            fingerprint=Path(name).stem,
            sequence=rewind_count + 1,
            rewind_count=rewind_count,
        )
        (session_dir / name).write_text(json.dumps(record) + "\n", encoding="utf-8")

    write_version(
        "old.jsonl",
        0,
        [
            {"role": "user", "content": "old user", "timestamp": 10},
            {"role": "assistant", "content": "old answer", "timestamp": 20},
        ],
    )
    write_version(
        "rewound.jsonl",
        1,
        [{"role": "user", "content": "rewound user", "timestamp": 10}],
    )

    run_cli(
        "reindex",
        "--archive-dir",
        str(archive_dir),
        "--state-dir",
        str(state_dir),
        "--index",
        str(state_dir / "index.db"),
    )
    connection = sqlite3.connect(state_dir / "index.db")
    row = connection.execute(
        "SELECT version_path, message_count FROM sessions"
    ).fetchone()
    connection.close()
    assert row == (
        "watari/default/session-one/rewound.jsonl",
        1,
    )


def test_reindex_skips_malformed_timestamp_without_losing_valid_sessions(
    tmp_path: Path,
) -> None:
    archive_dir = tmp_path / "archive"
    state_dir = tmp_path / "state"
    valid_dir = archive_dir / "lawliet" / "default" / "valid"
    invalid_dir = archive_dir / "lawliet" / "default" / "invalid"
    valid_dir.mkdir(parents=True)
    invalid_dir.mkdir(parents=True)
    (valid_dir / "version.jsonl").write_text(
        json.dumps(
            seal_record(
                {
                    "id": "valid",
                    "source": "cli",
                    "messages": [
                        {"role": "user", "content": "searchable", "timestamp": 1}
                    ],
                },
                node="lawliet",
                profile="default",
                fingerprint="version",
                sequence=1,
            )
        )
        + "\n",
        encoding="utf-8",
    )
    (invalid_dir / "version.jsonl").write_text(
        json.dumps(
            {
                "id": "invalid",
                "source": "cli",
                "messages": [{"role": "user", "content": "broken", "timestamp": {}}],
            }
        )
        + "\n",
        encoding="utf-8",
    )

    result = run_cli(
        "reindex",
        "--archive-dir",
        str(archive_dir),
        "--state-dir",
        str(state_dir),
        "--index",
        str(state_dir / "index.db"),
    )
    assert "indexed=1" in result.stdout
    assert "skipping invalid archive" in result.stderr


def test_reindex_refreshes_valid_same_path_replacement(tmp_path: Path) -> None:
    archive_dir = tmp_path / "archive"
    state_dir = tmp_path / "state"
    version = archive_dir / "lawliet" / "default" / "session-one" / "fixed.jsonl"
    version.parent.mkdir(parents=True)

    def write_content(content: str) -> None:
        record = seal_record(
            {
                "id": "session-one",
                "source": "cli",
                "messages": [{"role": "user", "content": content, "timestamp": 1}],
            },
            node="lawliet",
            profile="default",
            fingerprint="fixed",
            sequence=1,
        )
        version.write_text(json.dumps(record) + "\n", encoding="utf-8")

    common = [
        "--archive-dir",
        str(archive_dir),
        "--state-dir",
        str(state_dir),
        "--index",
        str(state_dir / "index.db"),
    ]
    write_content("old searchable phrase")
    run_cli("reindex", *common)
    write_content("new replacement phrase")
    second = run_cli("reindex", *common)
    assert "changed=1" in second.stdout
    assert run_cli("search", "new replacement", *common, "--json").stdout
    assert run_cli("search", "old searchable", *common, "--json").stdout == ""
