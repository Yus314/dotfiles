"""Live macOS appearance for the classic prompt_toolkit CLI.

Only the appearance probe runs off the UI thread. Selection and repainting
are serialized with manual /skin commands; a late probe cannot undo one.
The application's task lifecycle owns polling and cancels it on exit.
"""

import asyncio
import logging
import os
from pathlib import Path
from threading import RLock

from hermes_cli import macos_skin, skin_engine

logger = logging.getLogger(__name__)
AUTOMATIC_SKINS = {"default", "modus-vivendi", "modus-operandi"}


class ClassicSkinSync:
    def __init__(self, cli, app, home: Path):
        self.cli = cli
        self.app = app
        self.home = home
        self.selected = skin_engine.get_active_skin_name()
        self.mode = "auto" if self.selected in AUTOMATIC_SKINS else "manual"
        self.appearance = None
        self._revision = 0
        self._lock = RLock()
        self._loop = None
        self._stopped = False
        self._applied = None

    def start(self):
        self._loop = asyncio.get_running_loop()
        self.app.create_background_task(self._watch())

    def _eligible(self):
        return not self._stopped and macos_skin.live_authorized(self.home)

    def select(self, value: str):
        with self._lock:
            if not self._eligible():
                return False
            if value != "auto" and value not in {s["name"] for s in skin_engine.list_skins()}:
                return False
            self._revision += 1
            if value == "auto":
                self.mode = "auto"
                os.environ[macos_skin.SESSION_HOME] = str(self.home)
            else:
                self.mode = "manual"
                self.selected = value
                self.appearance = None
                macos_skin.manual_skin_selected()
                if self._loop is not None:
                    self._loop.call_soon_threadsafe(self._apply)
            return True

    def _apply(self):
        with self._lock:
            if not self._eligible() or not self.app.is_running:
                return
            palette = (self.selected, self.appearance)
            if palette == self._applied:
                return
            # Do not clear the detection cache: a fresh OSC 11 read while
            # prompt_toolkit owns stdin can consume actual user keystrokes.
            import cli as cli_module

            skin = skin_engine.set_active_skin(self.selected)
            if self.appearance is not None:
                cli_module._LIGHT_MODE_CACHE = self.appearance == "light"
            else:
                # Raw colors bypass the CLI's cached light-mode remap hook.
                background = skin.colors.get("completion_menu_bg", "")
                if len(background) == 7 and background.startswith("#"):
                    try:
                        red, green, blue = (int(background[i:i + 2], 16) for i in (1, 3, 5))
                        cli_module._LIGHT_MODE_CACHE = (0.2126 * red + 0.7152 * green + 0.0722 * blue) >= 127.5
                    except ValueError:
                        pass
            cli_module._ACCENT.reset()
            if self.cli._apply_tui_skin_style():
                self._applied = palette

    async def refresh(self):
        with self._lock:
            if not self._eligible() or self.mode != "auto":
                return
            revision = self._revision
        appearance = await asyncio.to_thread(macos_skin.probe_live_appearance)
        with self._lock:
            if not self._eligible() or self.mode != "auto" or revision != self._revision:
                return
            selected = {"dark": "modus-vivendi", "light": "modus-operandi"}.get(appearance)
            if selected and (self.home / "skins" / f"{selected}.yaml").is_file():
                self.selected = selected
                self.appearance = appearance
                self._apply()

    async def _watch(self):
        try:
            while self._eligible():
                try:
                    await self.refresh()
                except Exception:
                    logger.debug("macOS CLI skin refresh failed", exc_info=True)
                await asyncio.sleep(3)
        finally:
            self._stopped = True


def install_classic_skin_sync(cli, app):
    from hermes_constants import get_hermes_home

    home = get_hermes_home().resolve()
    if macos_skin.live_authorized(home):
        sync = ClassicSkinSync(cli, app, home)
        cli._macos_skin_sync = sync
        app.pre_run_callables.append(sync.start)


def select_classic_skin(cli, value: str) -> bool:
    sync = getattr(cli, "_macos_skin_sync", None)
    if sync is None or not sync.select(value):
        return False
    if value == "auto":
        print("  Skin follows macOS appearance (auto, session only).")
    else:
        print(f"  Skin set to: {value} (manual, session only)")
    return True
