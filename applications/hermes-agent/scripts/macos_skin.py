"""Watari's opt-in, default-profile-only macOS skin selection.

Selection is process-local: never rewrite config.yaml, restart sessions, or
probe macOS from gateway/cron invocations. A custom saved skin wins; default
and the two Modus skins opt into appearance following in interactive chats.
"""

from functools import lru_cache
import os
from pathlib import Path
import plistlib
import subprocess
import sys

SESSION_HOME = "_HERMES_MACOS_SKIN_SESSION_HOME"
# Chat eligibility survives manual selection in both renderers. This is not
# an active-sync flag and never authorizes a sibling profile. The startup
# skin_engine selection continues to use SESSION_HOME exclusively.
CAPABILITY_HOME = "_HERMES_MACOS_SKIN_CAPABILITY_HOME"
_live_policy = None


def manual_skin_selected() -> None:
    """A manual TUI selection wins for the rest of this process/session."""
    os.environ.pop(SESSION_HOME, None)


def prepare_chat(args, home: Path) -> None:
    """Called after profile resolution, before either CLI renderer starts."""
    global _live_policy
    _live_policy = None
    os.environ.pop(SESSION_HOME, None)
    os.environ.pop(CAPABILITY_HOME, None)
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
    os.environ[CAPABILITY_HOME] = str(home.resolve())


def live_authorized(home: Path) -> bool:
    """Revalidate chat capability for either interactive renderer.

    No TTY check here: the backend's stdin/stdout are JSON-RPC pipes. This
    classic renderer has already passed the TTY gate in prepare_chat.
    """
    target = os.environ.get("HERMES_MACOS_SKIN_HOME", "")
    capability = os.environ.get(CAPABILITY_HOME, "")
    return bool(
        sys.platform == "darwin"
        and target and capability
        and os.environ.get("HERMES_MACOS_SKIN_SYNC") != "0"
        and os.environ.get("HERMES_IGNORE_USER_CONFIG") != "1"
        and not any(os.environ.get(k) for k in ("SSH_CONNECTION", "SSH_TTY", "SSH_CLIENT"))
        and home.resolve() == Path(target).resolve() == Path(capability).resolve()
    )


def probe_live_appearance() -> str | None:
    """Read only AppleInterfaceStyle, uncached, with a bounded subprocess.

    Foundation distinguishes a missing key (light) from a failed subprocess.
    JXA uses no application automation, preference export, logging, or writes.
    A fresh process also avoids NSUserDefaults' long-lived preference cache.
    """
    script = (
        "ObjC.import('Foundation'); "
        "var style = $.NSUserDefaults.standardUserDefaults.objectForKey('AppleInterfaceStyle'); "
        "var value = style.isNil() ? null : ObjC.unwrap(style); "
        "value === null || value === 'Light' ? 'light' : value === 'Dark' ? 'dark' : 'unknown';"
    )
    try:
        result = subprocess.run(
            ["/usr/bin/osascript", "-l", "JavaScript", "-e", script],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            check=True, timeout=1, text=True,
        )
        value = result.stdout.strip()
        return value if value in ("dark", "light") else None
    except (OSError, subprocess.SubprocessError, ValueError):
        return None


class LiveSkinPolicy:
    """Process-local NEW TUI override; RPC dispatch serializes mutations."""

    def __init__(self, saved: str, home: Path):
        self.home = home.resolve()
        self.selected = saved
        self.mode = "auto" if saved in ("default", "modus-vivendi", "modus-operandi") else "manual"
        self.appearance = None
        self.refresh()

    def metadata(self) -> dict:
        return {"mode": self.mode, "appearance": self.appearance, "source": "macos"}

    def refresh(self) -> None:
        if self.mode != "auto" or not live_authorized(self.home):
            return
        appearance = probe_live_appearance()
        selected = {"dark": "modus-vivendi", "light": "modus-operandi"}.get(appearance)
        if selected and (self.home / "skins" / f"{selected}.yaml").is_file():
            self.selected = selected
            self.appearance = appearance

    def select(self, value: str) -> None:
        if not live_authorized(self.home):
            raise ValueError("/skin auto requires an authorized default-profile NEW TUI chat")
        if value == "auto":
            self.mode = "auto"
            os.environ[SESSION_HOME] = str(self.home)
            self.refresh()
        else:
            self.mode = "manual"
            self.selected = value
            self.appearance = None
            manual_skin_selected()


def effective_skin_changed(before: dict, after: dict) -> bool:
    """Mode-only transitions are returned to the caller, not palette events."""
    metadata = {"mode", "appearance", "source"}
    return ({k: v for k, v in before.items() if k not in metadata}
            != {k: v for k, v in after.items() if k not in metadata})


def live_policy(saved: str, home: Path) -> LiveSkinPolicy | None:
    """Called only by NEW TUI; merely reading an existing policy never polls."""
    global _live_policy
    if not live_authorized(home):
        return None
    if _live_policy is None or _live_policy.home != home.resolve():
        _live_policy = LiveSkinPolicy(saved, home)
    return _live_policy


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
