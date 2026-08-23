"""Phase-boundary context compaction for Hermes Agent.

The engine keeps the built-in compressor's pressure-based behavior and adds an
agent-callable ``phase_transition`` checkpoint.  A successful checkpoint forces
one compaction before the next model call, so completed research or
implementation history is replaced by a bounded, verified handoff.
"""

from __future__ import annotations

import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

from agent.context_compressor import ContextCompressor  # type: ignore[import-not-found]
from agent.redact import redact_sensitive_text  # type: ignore[import-not-found]
from hermes_constants import get_hermes_home  # type: ignore[import-not-found]

_ENGINE_NAME = "phase_checkpoint"
_MAX_ITEMS = 12
_MAX_ITEM_CHARS = 600
_MAX_TEXT_CHARS = 1_200


def _clean_text(value: Any, *, limit: int = _MAX_TEXT_CHARS) -> str:
    text = str(value or "").strip()
    text = redact_sensitive_text(
        text,
        force=True,
        redact_url_credentials=True,
    )
    if len(text) > limit:
        text = text[: limit - 16].rstrip() + " …[truncated]"
    return text


def _clean_list(value: Any) -> List[str]:
    if not isinstance(value, list):
        return []
    cleaned: List[str] = []
    for item in value[:_MAX_ITEMS]:
        text = _clean_text(item, limit=_MAX_ITEM_CHARS)
        if text:
            cleaned.append(text)
    return cleaned


def _safe_session_id(session_id: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", session_id or "unknown")
    return safe[:160] or "unknown"


class PhaseCheckpointEngine(ContextCompressor):
    """Built-in compressor plus explicit, safety-gated phase checkpoints."""

    def __init__(self) -> None:
        # agent_init calls update_model() with the real runtime immediately after
        # loading the engine.  These values mirror the default-profile settings
        # and make discovery/testing safe before that binding occurs.
        super().__init__(
            model="gpt-5.6-sol",
            threshold_percent=0.50,
            protect_first_n=3,
            protect_last_n=20,
            summary_target_ratio=0.20,
            quiet_mode=True,
            abort_on_summary_failure=True,
        )
        self._pending_checkpoint: Optional[Dict[str, Any]] = None
        self._last_checkpoint: Optional[Dict[str, Any]] = None
        self._checkpoint_path: Optional[Path] = None

    @property
    def name(self) -> str:
        return _ENGINE_NAME

    def bind_session_state(self, session_db: Any = None, session_id: str = "") -> None:
        super().bind_session_state(session_db=session_db, session_id=session_id)
        self._checkpoint_path = self._path_for_session(session_id)
        self._last_checkpoint = self._load_checkpoint()

    def on_session_reset(self) -> None:
        super().on_session_reset()
        self._pending_checkpoint = None
        self._last_checkpoint = None
        self._checkpoint_path = None

    def get_tool_schemas(self) -> List[Dict[str, Any]]:
        return [
            {
                "type": "function",
                "function": {
                    "name": "phase_transition",
                    "description": (
                        "Create a verified checkpoint and compact completed-phase context before "
                        "starting a materially different phase (for example research→implementation, "
                        "implementation→verification, or a new repository/domain). Call only after "
                        "the current phase acceptance criteria are evidenced. Do not call for a "
                        "minor next step, while background/subagent work is active, while approval "
                        "or a user decision is pending, or before an external side effect."
                    ),
                    "parameters": {
                        "type": "object",
                        "additionalProperties": False,
                        "properties": {
                            "completed_phase": {"type": "string"},
                            "next_phase": {"type": "string"},
                            "objective": {
                                "type": "string",
                                "description": "The exact active objective for the next phase.",
                            },
                            "verified_facts": {
                                "type": "array",
                                "items": {"type": "string"},
                                "maxItems": _MAX_ITEMS,
                            },
                            "decisions": {
                                "type": "array",
                                "items": {"type": "string"},
                                "maxItems": _MAX_ITEMS,
                            },
                            "artifacts": {
                                "type": "array",
                                "items": {"type": "string"},
                                "maxItems": _MAX_ITEMS,
                                "description": "Inspectable paths, URLs, IDs, or other handles only.",
                            },
                            "verification": {
                                "type": "array",
                                "items": {"type": "string"},
                                "minItems": 1,
                                "maxItems": _MAX_ITEMS,
                                "description": "Commands/checks already run and their real results.",
                            },
                            "open_risks": {
                                "type": "array",
                                "items": {"type": "string"},
                                "maxItems": _MAX_ITEMS,
                            },
                            "next_action": {
                                "type": "string",
                                "description": "The next exact action or command; not a vague plan.",
                            },
                            "safety": {
                                "type": "object",
                                "additionalProperties": False,
                                "properties": {
                                    "background_work_active": {"type": "boolean"},
                                    "approval_pending": {"type": "boolean"},
                                    "user_decision_required": {"type": "boolean"},
                                },
                                "required": [
                                    "background_work_active",
                                    "approval_pending",
                                    "user_decision_required",
                                ],
                            },
                        },
                        "required": [
                            "completed_phase",
                            "next_phase",
                            "objective",
                            "verified_facts",
                            "decisions",
                            "artifacts",
                            "verification",
                            "open_risks",
                            "next_action",
                            "safety",
                        ],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "phase_status",
                    "description": "Show the latest phase checkpoint for the active Hermes session.",
                    "parameters": {
                        "type": "object",
                        "additionalProperties": False,
                        "properties": {},
                    },
                },
            },
        ]

    def handle_tool_call(self, name: str, args: Dict[str, Any], **kwargs: Any) -> str:
        if name == "phase_status":
            checkpoint = self._last_checkpoint or self._load_checkpoint()
            return json.dumps(
                {"status": "ok", "checkpoint": checkpoint},
                ensure_ascii=False,
            )
        if name != "phase_transition":
            return json.dumps({"error": f"Unknown context engine tool: {name}"})

        error = self._validate_transition(args)
        if error:
            return json.dumps({"status": "rejected", "error": error}, ensure_ascii=False)

        checkpoint = self._build_checkpoint(args)
        self._pending_checkpoint = checkpoint
        self._last_checkpoint = checkpoint
        path = self._persist_checkpoint(checkpoint)
        return json.dumps(
            {
                "status": "queued",
                "transition": f"{checkpoint['completed_phase']} → {checkpoint['next_phase']}",
                "checkpoint_path": str(path) if path else None,
                "message": "The completed phase will be compacted before the next model call.",
            },
            ensure_ascii=False,
        )

    def should_compress(self, prompt_tokens: Optional[int] = None) -> bool:
        if self._pending_checkpoint is not None:
            return True
        return super().should_compress(prompt_tokens)

    def compress(
        self,
        messages: List[Dict[str, Any]],
        current_tokens: Optional[int] = None,
        focus_topic: Optional[str] = None,
        force: bool = False,
        memory_context: str = "",
    ) -> List[Dict[str, Any]]:
        checkpoint = self._pending_checkpoint
        effective_focus = self._checkpoint_focus(checkpoint) if checkpoint else focus_topic
        result = super().compress(
            messages,
            current_tokens=current_tokens,
            focus_topic=effective_focus,
            force=force or checkpoint is not None,
            memory_context=memory_context,
        )
        # Successful compaction calls record_completed_compaction(), including
        # Codex-native compaction.  Clear a pending no-op/abort here to avoid a
        # retry loop while preserving the full original transcript.
        if checkpoint is not None and self._pending_checkpoint is checkpoint:
            status = "failed" if getattr(self, "_last_compress_aborted", False) else "skipped"
            self._finish_checkpoint(status=status)
        return result

    def record_completed_compaction(self, *, used_fallback: bool = False) -> None:
        super().record_completed_compaction(used_fallback=used_fallback)
        if self._pending_checkpoint is not None:
            self._finish_checkpoint(
                status="applied_with_fallback" if used_fallback else "applied"
            )

    def _validate_transition(self, args: Dict[str, Any]) -> Optional[str]:
        completed = _clean_text(args.get("completed_phase"))
        next_phase = _clean_text(args.get("next_phase"))
        if not completed or not next_phase:
            return "completed_phase and next_phase are required"
        if completed.casefold() == next_phase.casefold():
            return "completed_phase and next_phase must differ"
        if not _clean_text(args.get("objective")):
            return "objective is required"
        if not _clean_text(args.get("next_action")):
            return "next_action is required"
        if not _clean_list(args.get("verification")):
            return "at least one real verification result is required"

        safety = args.get("safety")
        if not isinstance(safety, dict):
            return "safety attestation is required"
        blockers = [
            key
            for key in (
                "background_work_active",
                "approval_pending",
                "user_decision_required",
            )
            if safety.get(key) is not False
        ]
        if blockers:
            return "transition blocked by safety state: " + ", ".join(blockers)
        return None

    def _build_checkpoint(self, args: Dict[str, Any]) -> Dict[str, Any]:
        return {
            "schema_version": 1,
            "engine": _ENGINE_NAME,
            "session_id": _clean_text(getattr(self, "_session_id", ""), limit=200),
            "created_at": datetime.now(timezone.utc).isoformat(),
            "status": "queued",
            "completed_phase": _clean_text(args.get("completed_phase")),
            "next_phase": _clean_text(args.get("next_phase")),
            "objective": _clean_text(args.get("objective")),
            "verified_facts": _clean_list(args.get("verified_facts")),
            "decisions": _clean_list(args.get("decisions")),
            "artifacts": _clean_list(args.get("artifacts")),
            "verification": _clean_list(args.get("verification")),
            "open_risks": _clean_list(args.get("open_risks")),
            "next_action": _clean_text(args.get("next_action")),
        }

    def _checkpoint_focus(self, checkpoint: Dict[str, Any]) -> str:
        def section(label: str, values: List[str]) -> str:
            body = "\n".join(f"- {value}" for value in values) or "- none"
            return f"{label}:\n{body}"

        return "\n".join(
            [
                "Create a phase-transition handoff. Preserve the following verified checkpoint exactly; "
                "treat earlier raw exploration and tool output as historical unless needed to support it.",
                f"Completed phase: {checkpoint['completed_phase']}",
                f"Next phase: {checkpoint['next_phase']}",
                f"Active objective: {checkpoint['objective']}",
                section("Verified facts", checkpoint["verified_facts"]),
                section("Decisions", checkpoint["decisions"]),
                section("Artifacts", checkpoint["artifacts"]),
                section("Verification", checkpoint["verification"]),
                section("Open risks", checkpoint["open_risks"]),
                f"Next exact action: {checkpoint['next_action']}",
                "Do not resume the completed phase or copy long raw logs into the handoff.",
            ]
        )

    def _path_for_session(self, session_id: str) -> Path:
        return (
            get_hermes_home()
            / "state"
            / "phase-checkpoints"
            / f"{_safe_session_id(session_id)}.json"
        )

    def _load_checkpoint(self) -> Optional[Dict[str, Any]]:
        path = self._checkpoint_path
        if path is None or not path.is_file():
            return None
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        return loaded if isinstance(loaded, dict) else None

    def _persist_checkpoint(self, checkpoint: Dict[str, Any]) -> Optional[Path]:
        path = self._checkpoint_path
        if path is None:
            path = self._path_for_session(getattr(self, "_session_id", ""))
            self._checkpoint_path = path
        try:
            path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            os.chmod(path.parent, 0o700)
            temporary = path.with_suffix(".json.tmp")
            temporary.write_text(
                json.dumps(checkpoint, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            os.chmod(temporary, 0o600)
            temporary.replace(path)
            return path
        except OSError:
            return None

    def _finish_checkpoint(self, *, status: str) -> None:
        checkpoint = self._pending_checkpoint
        if checkpoint is None:
            return
        checkpoint["status"] = status
        checkpoint["finished_at"] = datetime.now(timezone.utc).isoformat()
        self._last_checkpoint = checkpoint
        self._pending_checkpoint = None
        self._persist_checkpoint(checkpoint)


def register(ctx: Any) -> None:
    # A fresh instance is required for every AIAgent; context engines hold
    # session-specific token and checkpoint state.
    ctx.register_context_engine(PhaseCheckpointEngine())
