import subprocess
import sys
from pathlib import Path

import yaml

SCRIPT = Path(__file__).parents[1] / "scripts" / "phase_context_config.py"


def run_script(config_path: Path) -> None:
    subprocess.run(
        [sys.executable, str(SCRIPT), str(config_path)],
        check=True,
    )


def test_phase_context_config_preserves_existing_settings(tmp_path: Path) -> None:
    config_path = tmp_path / "config.yaml"
    config_path.write_text(
        yaml.safe_dump(
            {
                "model": {"default": "openai-codex/gpt-5.6-sol"},
                "compression": {"threshold": 0.42, "protect_last_n": 12},
                "agent": {"gateway_timeout": 3600, "max_turns": 90},
                "context": {"custom": "kept"},
                "plugins": {"enabled": ["web-exa"]},
            }
        ),
        encoding="utf-8",
    )

    run_script(config_path)

    config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    assert config["model"]["default"] == "openai-codex/gpt-5.6-sol"
    assert config["context"] == {"custom": "kept", "engine": "phase_checkpoint"}
    assert config["plugins"] == {"enabled": ["phase_checkpoint", "web-exa"]}
    assert config["compression"] == {
        "threshold": 0.42,
        "protect_last_n": 12,
        "enabled": True,
        "in_place": True,
        "codex_app_server_auto": "hermes",
    }
    assert config["agent"] == {"gateway_timeout": 3600, "max_turns": 120}


def test_phase_context_config_is_idempotent(tmp_path: Path) -> None:
    config_path = tmp_path / "config.yaml"

    run_script(config_path)
    first = config_path.read_text(encoding="utf-8")
    run_script(config_path)

    assert config_path.read_text(encoding="utf-8") == first
