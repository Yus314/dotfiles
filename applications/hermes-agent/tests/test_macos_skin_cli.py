"""Classic live appearance: real skin engine, styles and app lifecycle.

Requires the patched source on PYTHONPATH. No user config or real macOS
appearance is changed; probes use disposable palettes and controlled results.
"""

import ast
import asyncio
from contextlib import redirect_stdout
import io
import os
from pathlib import Path
import sys
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

try:
    from hermes_cli import macos_skin, macos_skin_cli, skin_engine
except ImportError as error:
    raise unittest.SkipTest("requires classic-live-patched Hermes on PYTHONPATH") from error

from prompt_toolkit.application import Application
from prompt_toolkit.buffer import Buffer
from prompt_toolkit.document import Document
from prompt_toolkit.input import create_pipe_input
from prompt_toolkit.layout import Layout, Window
from prompt_toolkit.layout.controls import BufferControl
from prompt_toolkit.output import DummyOutput
from prompt_toolkit.selection import SelectionState
from prompt_toolkit.styles import Style


class ClassicLiveTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.home = Path(temp.name).resolve()
        (self.home / "skins").mkdir()
        for name, fg, bg in (("modus-vivendi", "#ffffff", "#110b11"),
                             ("modus-operandi", "#000000", "#f2f2f2")):
            (self.home / "skins" / f"{name}.yaml").write_text(
                f'name: {name}\ncolors:\n  prompt: "{fg}"\n  banner_text: "{fg}"\n'
                f'  status_bar_bg: "{bg}"\n  completion_menu_bg: "{bg}"\n'
            )
        env = {"HERMES_HOME": str(self.home), "HERMES_MACOS_SKIN_HOME": str(self.home),
               macos_skin.SESSION_HOME: str(self.home), macos_skin.CAPABILITY_HOME: str(self.home)}
        self.cli_module = SimpleNamespace(_LIGHT_MODE_CACHE=False, _ACCENT=Mock(), save_config_value=Mock())
        for p in (patch.dict(os.environ, env, clear=True), patch.object(sys, "platform", "darwin"),
                  patch.dict(sys.modules, {"cli": self.cli_module})):
            p.start()
            self.addCleanup(p.stop)
        skin_engine.set_active_skin("modus-vivendi")
        self.source = Path(skin_engine.__file__).parents[1]
        tree = ast.parse((self.source / "cli.py").read_text())
        cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == "HermesCLI")
        scope = {"PTStyle": Style, "_detect_light_mode": lambda: self.cli_module._LIGHT_MODE_CACHE,
                 "_maybe_remap_for_light_mode": lambda value: value}
        for fn in cls.body:
            if isinstance(fn, ast.FunctionDef) and fn.name in {"_build_tui_style_dict", "_apply_tui_skin_style"}:
                exec(compile(ast.Module(body=[fn], type_ignores=[]), str(self.source / "cli.py"), "exec"), scope)
        self.buffer = Buffer(document=Document("draft 日本語\nsecond", 3))
        self.buffer.selection_state = SelectionState(1)
        self.app = SimpleNamespace(is_running=True, style=None, pre_run_callables=[])
        self.cli = SimpleNamespace(_app=self.app, _tui_style_base={"input-area": ""}, _invalidate=Mock())
        self.cli._build_tui_style_dict = lambda: scope["_build_tui_style_dict"](self.cli)
        self.cli._apply_tui_skin_style = lambda: scope["_apply_tui_skin_style"](self.cli)
        self.cli._apply_tui_skin_style()
        self.cli._invalidate.reset_mock()
        macos_skin_cli.install_classic_skin_sync(self.cli, self.app)
        self.sync = self.cli._macos_skin_sync
        self.sync._loop = asyncio.get_event_loop_policy().get_event_loop()

    async def appearance(self, mode):
        with patch.object(macos_skin, "probe_live_appearance", return_value=mode):
            await self.sync.refresh()

    def attrs(self, key):
        return self.cli._app.style.get_attrs_for_style_str("class:" + key)

    async def test_dark_light_dark_updates_styles_and_cache_without_touching_input(self):
        # Attach the same buffer to a real layout; only the style may change.
        self.app.layout = Layout(Window(BufferControl(self.buffer)))
        document, selection, layout = self.buffer.document, self.buffer.selection_state, self.app.layout
        for mode, foreground, background in (("dark", "ffffff", "110b11"),
                                              ("light", "000000", "f2f2f2"),
                                              ("dark", "ffffff", "110b11")):
            await self.appearance(mode)
            self.assertEqual(self.attrs("prompt").color, foreground)
            self.assertEqual(self.attrs("status-bar").bgcolor, background)
            self.assertEqual(self.cli_module._LIGHT_MODE_CACHE, mode == "light")
            self.assertIs(self.buffer.document, document)
            self.assertIs(self.buffer.selection_state, selection)
            self.assertIs(self.app.layout, layout)
        self.assertEqual(self.cli._invalidate.call_count, 3)
        self.assertFalse((self.home / "config.yaml").exists())

    async def test_unchanged_failed_or_missing_palette_does_not_repaint(self):
        await self.appearance("dark")
        self.cli._invalidate.reset_mock()
        await self.appearance("dark")
        await self.appearance(None)
        (self.home / "skins/modus-operandi.yaml").unlink()
        await self.appearance("light")
        self.cli._invalidate.assert_not_called()
        self.assertEqual(skin_engine.get_active_skin_name(), "modus-vivendi")

    async def test_manual_command_wins_over_inflight_probe_then_auto_resumes(self):
        started, release = threading.Event(), threading.Event()
        self.addCleanup(release.set)
        def probe():
            started.set()
            release.wait(timeout=3)
            return "light"
        with patch.object(macos_skin, "probe_live_appearance", side_effect=probe):
            pending = asyncio.create_task(self.sync.refresh())
            await asyncio.to_thread(started.wait, 2)
            self.assertTrue(self.sync.select("slate"))
            release.set()
            await pending
            await asyncio.sleep(0)
        self.assertEqual(skin_engine.get_active_skin_name(), "slate")
        with patch.object(macos_skin, "probe_live_appearance") as probe_mock:
            await self.sync.refresh()
            probe_mock.assert_not_called()
        self.assertTrue(self.sync.select("auto"))
        await self.appearance("light")
        self.assertEqual(skin_engine.get_active_skin_name(), "modus-operandi")
        self.assertFalse(self.sync.select("missing-skin"))

    async def test_manual_palette_updates_light_mode_cache_and_latest_choice_wins(self):
        self.sync.select("modus-operandi")
        await asyncio.sleep(0)
        self.assertTrue(self.cli_module._LIGHT_MODE_CACHE)
        self.sync.select("modus-operandi")
        self.sync.select("modus-vivendi")
        await asyncio.sleep(0)
        self.assertFalse(self.cli_module._LIGHT_MODE_CACHE)
        self.assertEqual(self.attrs("prompt").color, "ffffff")

    async def test_profile_opt_out_and_shutdown_reject_updates(self):
        for env in ({"HERMES_MACOS_SKIN_SYNC": "0"}, {"SSH_TTY": "yes"},
                    {macos_skin.CAPABILITY_HOME: str(self.home / "profiles/math")}):
            with patch.dict(os.environ, env), patch.object(macos_skin, "probe_live_appearance") as probe:
                cli = SimpleNamespace()
                macos_skin_cli.install_classic_skin_sync(cli, self.app)
                self.assertFalse(hasattr(cli, "_macos_skin_sync"))
                await self.sync.refresh()
                self.assertFalse(self.sync.select("slate"))
                probe.assert_not_called()
        self.sync.select("modus-operandi")
        self.app.is_running = False
        await asyncio.sleep(0)
        self.assertEqual(skin_engine.get_active_skin_name(), "modus-vivendi")

    async def test_real_app_owns_polling_and_cancels_on_exit(self):
        with create_pipe_input() as input_pipe:
            app = Application(layout=Layout(Window(BufferControl(self.buffer))), input=input_pipe, output=DummyOutput())
            self.cli._app = app
            macos_skin_cli.install_classic_skin_sync(self.cli, app)
            sync = self.cli._macos_skin_sync
            with patch.object(macos_skin, "probe_live_appearance", return_value="light") as probe:
                async def exit_after_refresh():
                    for _ in range(100):
                        if sync.appearance == "light":
                            break
                        await asyncio.sleep(0.01)
                    app.exit()
                app.pre_run_callables.append(lambda: app.create_background_task(exit_after_refresh()))
                await asyncio.wait_for(app.run_async(), 3)
            self.assertEqual(sync.appearance, "light")
            self.assertEqual(probe.call_count, 1)
            self.assertTrue(sync._stopped)
            self.assertFalse(sync.select("slate"))

    async def test_patched_slash_handler_uses_session_override_without_saving(self):
        tree = ast.parse((self.source / "hermes_cli/cli_commands_mixin.py").read_text())
        fn = next(n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == "_handle_skin_command")
        scope = {"display_hermes_home": lambda: str(self.home)}
        exec(compile(ast.Module(body=[fn], type_ignores=[]), "cli_commands_mixin.py", "exec"), scope)
        with redirect_stdout(io.StringIO()) as output:
            scope[fn.name](self.cli, "/skin modus-operandi")
            await asyncio.sleep(0)
            self.assertEqual(skin_engine.get_active_skin_name(), "modus-operandi")
            scope[fn.name](self.cli, "/skin auto")
            await self.appearance("dark")
            scope[fn.name](self.cli, "/skin")
        self.assertIn("Mode: auto", output.getvalue())
        self.cli_module.save_config_value.assert_not_called()


if __name__ == "__main__":
    unittest.main()
