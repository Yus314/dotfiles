import importlib.util
import json
import os
import sys
import types
from pathlib import Path
from typing import Any

import pytest

PLUGIN = (
    Path(__file__).parents[1]
    / "plugins"
    / "context_engine"
    / "phase_checkpoint"
    / "__init__.py"
)


class StubContextCompressor:
    def __init__(self, **kwargs: Any) -> None:
        self.init_kwargs = kwargs
        self.threshold_tokens = 100
        self.context_length = 200
        self.compression_count = 0
        self.last_prompt_tokens = 0
        self._session_id = ""
        self._last_compress_aborted = False
        self.base_should_compress = False
        self.last_focus = None

    def bind_session_state(self, session_db: Any = None, session_id: str = "") -> None:
        self._session_id = session_id

    def on_session_reset(self) -> None:
        self.compression_count = 0

    def should_compress(self, prompt_tokens: int | None = None) -> bool:
        return self.base_should_compress

    def compress(self, messages: list[dict], **kwargs: Any) -> list[dict]:
        self.last_focus = kwargs.get("focus_topic")
        self.record_completed_compaction(used_fallback=False)
        return messages[-2:]

    def record_completed_compaction(self, *, used_fallback: bool = False) -> None:
        self.compression_count += 1


def load_plugin(monkeypatch: pytest.MonkeyPatch, home: Path):
    agent_module = types.ModuleType("agent")
    compressor_module = types.ModuleType("agent.context_compressor")
    setattr(compressor_module, "ContextCompressor", StubContextCompressor)
    redact_module = types.ModuleType("agent.redact")
    setattr(redact_module, "redact_sensitive_text", (
        lambda text, **kwargs: str(text).replace("secret-token", "[REDACTED]")
    ))
    constants_module = types.ModuleType("hermes_constants")
    setattr(constants_module, "get_hermes_home", lambda: home)

    monkeypatch.setitem(sys.modules, "agent", agent_module)
    monkeypatch.setitem(sys.modules, "agent.context_compressor", compressor_module)
    monkeypatch.setitem(sys.modules, "agent.redact", redact_module)
    monkeypatch.setitem(sys.modules, "hermes_constants", constants_module)

    module_name = "phase_checkpoint_test_plugin"
    sys.modules.pop(module_name, None)
    spec = importlib.util.spec_from_file_location(module_name, PLUGIN)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def transition_args(**overrides: Any) -> dict[str, Any]:
    args: dict[str, Any] = {
        "completed_phase": "research",
        "next_phase": "implementation",
        "objective": "Implement the verified design without secret-token.",
        "verified_facts": ["Definition is in src/example.py"],
        "decisions": ["Use the existing adapter"],
        "artifacts": ["/tmp/example.md"],
        "verification": ["pytest -q: 4 passed"],
        "open_risks": [],
        "next_action": "Patch src/example.py",
        "safety": {
            "background_work_active": False,
            "approval_pending": False,
            "user_decision_required": False,
        },
    }
    args.update(overrides)
    return args


def test_transition_forces_compaction_and_persists_redacted_checkpoint(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    module = load_plugin(monkeypatch, tmp_path)
    engine = module.PhaseCheckpointEngine()
    engine.bind_session_state(session_id="discord:channel/thread")

    result = json.loads(engine.handle_tool_call("phase_transition", transition_args()))

    assert result["status"] == "queued"
    assert engine.should_compress(1) is True
    checkpoint_path = Path(result["checkpoint_path"])
    assert checkpoint_path.is_file()
    assert oct(os.stat(checkpoint_path).st_mode & 0o777) == "0o600"
    queued = json.loads(checkpoint_path.read_text(encoding="utf-8"))
    assert queued["status"] == "queued"
    assert "secret-token" not in queued["objective"]

    compacted = engine.compress(
        [
            {"role": "system", "content": "system"},
            {"role": "user", "content": "old research"},
            {"role": "assistant", "content": "phase tool call"},
            {"role": "tool", "content": "queued"},
        ],
        current_tokens=50,
    )

    assert len(compacted) == 2
    assert engine._pending_checkpoint is None
    assert "Next phase: implementation" in engine.last_focus
    applied = json.loads(checkpoint_path.read_text(encoding="utf-8"))
    assert applied["status"] == "applied"
    assert "finished_at" in applied


def test_transition_rejects_unsafe_or_unverified_boundaries(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    module = load_plugin(monkeypatch, tmp_path)
    engine = module.PhaseCheckpointEngine()
    engine.bind_session_state(session_id="unsafe")

    unsafe = transition_args()
    unsafe["safety"]["approval_pending"] = True
    rejected = json.loads(engine.handle_tool_call("phase_transition", unsafe))
    assert rejected["status"] == "rejected"
    assert "approval_pending" in rejected["error"]

    unverified = json.loads(
        engine.handle_tool_call(
            "phase_transition",
            transition_args(verification=[]),
        )
    )
    assert unverified["status"] == "rejected"
    assert "verification" in unverified["error"]
    assert engine._pending_checkpoint is None


def test_phase_status_survives_engine_recreation(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    module = load_plugin(monkeypatch, tmp_path)
    first = module.PhaseCheckpointEngine()
    first.bind_session_state(session_id="persistent")
    first.handle_tool_call("phase_transition", transition_args())
    first.compress([{"role": "user", "content": "x"}, {"role": "tool", "content": "y"}])

    second = module.PhaseCheckpointEngine()
    second.bind_session_state(session_id="persistent")
    status = json.loads(second.handle_tool_call("phase_status", {}))

    assert status["checkpoint"]["status"] == "applied"
    assert status["checkpoint"]["next_phase"] == "implementation"


def test_normal_pressure_policy_is_preserved_without_checkpoint(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    module = load_plugin(monkeypatch, tmp_path)
    engine = module.PhaseCheckpointEngine()
    engine.base_should_compress = True

    assert engine.should_compress(150) is True
