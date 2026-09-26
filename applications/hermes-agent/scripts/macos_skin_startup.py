"""Watari's opt-in, default-profile-only skin selection at CLI startup.

Selection is process-local: never rewrite config.yaml, restart sessions, or
probe macOS from gateway/cron invocations. A custom saved skin wins; default
and the two Modus skins opt into appearance following on the next launch.
"""

from functools import lru_cache
import os
from pathlib import Path
import plistlib
import subprocess
import sys

SESSION_HOME = "_HERMES_MACOS_SKIN_SESSION_HOME"


def manual_skin_selected() -> None:
    """A manual TUI selection wins for the rest of this process/session."""
    os.environ.pop(SESSION_HOME, None)


def prepare_chat(args, home: Path) -> None:
    """Called after profile resolution, before either CLI renderer starts."""
    os.environ.pop(SESSION_HOME, None)
    target = os.environ.get("HERMES_MACOS_SKIN_HOME", "")
    if (
        sys.platform != "darwin"
        or not target
        or os.environ.get("HERMES_MACOS_SKIN_SYNC") == "0"
        or any(os.environ.get(key) for key in ("SSH_CONNECTION", "SSH_TTY", "SSH_CLIENT"))
        or not (sys.stdin.isatty() and sys.stdout.isatty())
        or getattr(args, "query", None) is not None
        or getattr(args, "ignore_user_config", False)
        or getattr(args, "safe_mode", False)
        or os.environ.get("HERMES_IGNORE_USER_CONFIG") == "1"
        or home.resolve() != Path(target).resolve()
    ):
        return
    os.environ[SESSION_HOME] = str(home.resolve())


@lru_cache(maxsize=1)
def detect_appearance() -> str | None:
    """A missing AppleInterfaceStyle is light only after a successful read.

    Export avoids mistaking a failed `defaults read` for light mode. Nothing
    from the preferences domain is logged or persisted.
    """
    try:
        result = subprocess.run(
            ["/usr/bin/defaults", "export", "NSGlobalDomain", "-"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=True,
            timeout=2,
        )
        preferences = plistlib.loads(result.stdout)
        if not isinstance(preferences, dict):
            return None
        style = preferences.get("AppleInterfaceStyle")
        if style is None or style == "Light":
            return "light"
        if style == "Dark":
            return "dark"
    except (OSError, subprocess.SubprocessError, plistlib.InvalidFileException, ValueError):
        pass
    return None


def select_skin(saved: str, home: Path) -> str:
    """Recheck profile scope in the TUI child; preserve explicit custom skins."""
    target = os.environ.get("HERMES_MACOS_SKIN_HOME", "")
    session = os.environ.get(SESSION_HOME, "")
    if (
        sys.platform != "darwin"
        or not target
        or not session
        or os.environ.get("HERMES_MACOS_SKIN_SYNC") == "0"
        or home.resolve() != Path(target).resolve()
        or home.resolve() != Path(session).resolve()
        or saved not in ("default", "modus-vivendi", "modus-operandi")
    ):
        return saved
    appearance = detect_appearance()
    if appearance is None:
        return saved
    selected = {"dark": "modus-vivendi", "light": "modus-operandi"}.get(appearance)
    if selected and (home / "skins" / f"{selected}.yaml").is_file():
        return selected
    return saved
