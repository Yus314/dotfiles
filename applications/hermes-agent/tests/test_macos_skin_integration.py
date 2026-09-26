"""Integration checks run against the patched Hermes source via PYTHONPATH."""

import ast
import importlib
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

try:
    macos_skin = importlib.import_module("hermes_cli.macos_skin")
except ModuleNotFoundError as error:
    if error.name not in ("hermes_cli", "hermes_cli.macos_skin"):
        raise
    raise unittest.SkipTest("requires the patched Hermes source on PYTHONPATH") from error
skin_engine = importlib.import_module("hermes_cli.skin_engine")


class PatchedSkinTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        (self.home / "skins").mkdir()
        for name in ("modus-vivendi", "modus-operandi"):
            (self.home / "skins" / f"{name}.yaml").write_text(
                f'name: {name}\ncolors:\n  prompt: "#123456"\n'
            )
        self.config = {"display": {"skin": "default", "streaming": True}}
        self.env = patch.dict(os.environ, {
            "HERMES_HOME": str(self.home),
            "HERMES_MACOS_SKIN_HOME": str(self.home),
            macos_skin.SESSION_HOME: str(self.home),
        }, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)
        self.platform = patch.object(sys, "platform", "darwin")
        self.platform.start()
        self.addCleanup(self.platform.stop)

    def test_engine_selects_real_user_skin_without_config_mutation(self):
        for mode, name in (("dark", "modus-vivendi"), ("light", "modus-operandi")):
            with patch.object(macos_skin, "detect_appearance", return_value=mode):
                skin_engine.init_skin_from_config(self.config)
                self.assertEqual(skin_engine.get_active_skin().name, name)
                self.assertEqual(skin_engine.get_active_skin().colors["prompt"], "#123456")
        self.assertEqual(self.config, {"display": {"skin": "default", "streaming": True}})
        self.assertFalse((self.home / "config.yaml").exists())

    def test_explicit_skin_switch_works_after_auto_initialization(self):
        with patch.object(macos_skin, "detect_appearance", return_value="dark"):
            skin_engine.init_skin_from_config(self.config)
            skin_engine.set_active_skin("modus-operandi")
            self.assertEqual(skin_engine.get_active_skin().name, "modus-operandi")
            skin_engine.init_skin_from_config({"display": {"skin": "slate"}})
            self.assertEqual(skin_engine.get_active_skin().name, "slate")

    def test_engine_ignores_marker_from_another_profile(self):
        with patch.dict(os.environ, {"HERMES_HOME": str(self.home / "profiles/math")}):
            with patch.object(macos_skin, "detect_appearance") as probe:
                skin_engine.init_skin_from_config(self.config)
                self.assertEqual(skin_engine.get_active_skin().name, "default")
                probe.assert_not_called()

    def test_tui_manual_selection_is_not_overridden(self):
        assert skin_engine.__file__ is not None
        source = Path(skin_engine.__file__).parents[1] / "tui_gateway/server.py"
        tree = ast.parse(source.read_text())
        resolve = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "resolve_skin")
        branch = next(
            n for n in ast.walk(tree)
            if isinstance(n, ast.If)
            and ast.unparse(n.test) == "key == 'skin'"
            and "skin.changed" in ast.unparse(n)
        )
        events = []
        scope = {"_load_cfg": lambda: self.config, "key": "skin", "_emit": lambda *args: events.append(args)}
        exec(compile(ast.Module(body=[resolve], type_ignores=[]), str(source), "exec"), scope)
        with patch.object(macos_skin, "detect_appearance", return_value="dark"):
            self.assertEqual(scope["resolve_skin"]()["name"], "modus-vivendi")
            # The real config.set branch runs after Hermes saves the selection.
            self.config["display"]["skin"] = "modus-operandi"
            exec(compile(ast.Module(body=[branch], type_ignores=[]), str(source), "exec"), scope)
            self.assertEqual(events[-1][2]["name"], "modus-operandi")
            self.assertEqual(scope["resolve_skin"]()["name"], "modus-operandi")
            self.assertNotIn(macos_skin.SESSION_HOME, os.environ)

    def test_engine_without_chat_marker_does_not_probe(self):
        os.environ.pop(macos_skin.SESSION_HOME)
        with patch.object(macos_skin, "detect_appearance") as probe:
            skin_engine.init_skin_from_config(self.config)
            self.assertEqual(skin_engine.get_active_skin().name, "default")
            probe.assert_not_called()

    def test_tui_skin_query_reports_effective_not_saved_skin(self):
        assert skin_engine.__file__ is not None
        source = Path(skin_engine.__file__).parents[1] / "tui_gateway/server.py"
        tree = ast.parse(source.read_text())
        resolve = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "resolve_skin")
        branch = next(
            n for n in ast.walk(tree)
            if isinstance(n, ast.If)
            and ast.unparse(n.test) == "key == 'skin'"
            and "return _ok" in ast.unparse(n)
        )
        wrapper = ast.parse("def read_skin(): pass").body[0]
        assert isinstance(wrapper, ast.FunctionDef)
        wrapper.body = [branch]
        scope = {"_load_cfg": lambda: self.config, "key": "skin", "rid": 1, "_ok": lambda rid, result: result}
        exec(compile(ast.fix_missing_locations(ast.Module(body=[resolve, wrapper], type_ignores=[])), str(source), "exec"), scope)
        with patch.object(macos_skin, "detect_appearance", return_value="dark"):
            self.assertEqual(scope["read_skin"]()["value"], "modus-vivendi")
            self.assertEqual(self.config["display"]["skin"], "default")

    def test_chat_hook_runs_before_renderer_dispatch(self):
        # Execute the real patched function until renderer selection, without
        # loading plugins, user config, credentials, or starting an agent.
        assert skin_engine.__file__ is not None
        source = Path(skin_engine.__file__).with_name("main.py")
        tree = ast.parse(source.read_text())
        fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "cmd_chat")
        class RendererReached(Exception):
            pass

        def renderer(args):
            raise RendererReached

        scope = {
            "get_hermes_home": lambda: self.home,
            "_resolve_use_tui": renderer,
        }
        exec(compile(ast.Module(body=[fn], type_ignores=[]), str(source), "exec"), scope)
        os.environ.pop(macos_skin.SESSION_HOME)
        with patch.object(sys.stdin, "isatty", return_value=True), patch.object(sys.stdout, "isatty", return_value=True):
            with self.assertRaises(RendererReached):
                scope["cmd_chat"](SimpleNamespace())
        self.assertEqual(os.environ[macos_skin.SESSION_HOME], str(self.home))


if __name__ == "__main__":
    unittest.main()
