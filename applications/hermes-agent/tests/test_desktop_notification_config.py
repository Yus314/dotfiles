import subprocess
import sys
from pathlib import Path

import yaml

SCRIPT = Path(__file__).parents[1] / "scripts" / "desktop_notification_config.py"


def run_script(config_path: Path) -> None:
    subprocess.run(
        [sys.executable, str(SCRIPT), str(config_path)],
        check=True,
    )


def test_desktop_notification_config_preserves_existing_settings(tmp_path: Path) -> None:
    config_path = tmp_path / "config.yaml"
    config_path.write_text(
        yaml.safe_dump(
            {
                "model": {"default": "openai-codex/gpt-5.6-sol"},
                "display": {"skin": "modus-vivendi", "streaming": True},
            }
        ),
        encoding="utf-8",
    )

    run_script(config_path)

    config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    assert config["model"]["default"] == "openai-codex/gpt-5.6-sol"
    assert config["display"] == {
        "skin": "modus-vivendi",
        "streaming": True,
        "bell_on_complete": True,
    }


def test_desktop_notification_config_is_idempotent(tmp_path: Path) -> None:
    config_path = tmp_path / "config.yaml"

    run_script(config_path)
    first = config_path.read_text(encoding="utf-8")
    run_script(config_path)

    assert config_path.read_text(encoding="utf-8") == first
