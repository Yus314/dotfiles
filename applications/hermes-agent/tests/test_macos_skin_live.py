"""Live policy plus real patched server AST; all homes/config are disposable.

Set PYTHONPATH to the startup-patched Hermes tree. The server patch is applied
in a temporary directory (unless the tree already contains skin.refresh).
"""
import ast
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location("live_macos_skin", ROOT / "scripts/macos_skin.py")
skin = importlib.util.module_from_spec(spec)
spec.loader.exec_module(skin)


class LivePolicyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name).resolve()
        (self.home / "skins").mkdir()
        for name in ("modus-vivendi", "modus-operandi"):
            (self.home / "skins" / f"{name}.yaml").write_text(f'name: {name}\ncolors:\n  prompt: "#123456"\n')
        for p in (patch.dict(os.environ, {"HERMES_HOME": str(self.home), "HERMES_MACOS_SKIN_HOME": str(self.home)}, clear=True),
                  patch.object(sys, "platform", "darwin"),
                  patch.object(sys.stdin, "isatty", return_value=True),
                  patch.object(sys.stdout, "isatty", return_value=True)):
            p.start()
            self.addCleanup(p.stop)
        skin.prepare_chat(SimpleNamespace(tui=True), self.home)

    def policy(self, saved="default"):
        return skin.live_policy(saved, self.home)

    def test_auto_refresh_last_good_and_manual_auto(self):
        with patch.object(skin, "probe_live_appearance", return_value="dark") as probe:
            p = self.policy()
            self.assertEqual(p.selected, "modus-vivendi")
            self.assertEqual(p.metadata(), {"mode": "auto", "appearance": "dark", "source": "macos"})
            probe.return_value = "light"
            p.refresh()
            self.assertEqual(p.selected, "modus-operandi")
            probe.return_value = None
            p.refresh()
            self.assertEqual(p.selected, "modus-operandi")
            self.assertEqual(p.metadata()["appearance"], "light")
            p.select("slate")
            probe.reset_mock()
            p.refresh()
            self.assertEqual(p.selected, "slate")
            self.assertEqual(p.metadata(), {"mode": "manual", "appearance": None, "source": "macos"})
            probe.assert_not_called()
            self.assertNotIn(skin.SESSION_HOME, os.environ)
            self.assertIn(skin.CAPABILITY_HOME, os.environ)
            probe.return_value = "dark"
            p.select("auto")
            self.assertEqual(p.selected, "modus-vivendi")
            self.assertEqual(p.metadata()["mode"], "auto")
        self.assertFalse((self.home / "config.yaml").exists())

    def test_saved_custom_fixed_until_auto(self):
        with patch.object(skin, "probe_live_appearance", return_value="light") as probe:
            p = self.policy("slate")
            p.refresh()
            self.assertEqual(p.selected, "slate")
            probe.assert_not_called()
            p.select("auto")
            self.assertEqual(p.selected, "modus-operandi")

    def test_missing_palette_and_probe_failures_retain_selection(self):
        with patch.object(skin, "probe_live_appearance", return_value=None) as probe:
            p = self.policy()
            self.assertEqual(p.selected, "default")
            self.assertIsNone(p.metadata()["appearance"])
            probe.return_value = "dark"
            p.refresh()
            (self.home / "skins/modus-operandi.yaml").unlink()
            probe.return_value = "light"
            p.refresh()
            self.assertEqual(p.selected, "modus-vivendi")
            self.assertEqual(p.metadata()["appearance"], "dark")

    def test_capability_not_active_marker_controls_reentry(self):
        skin.manual_skin_selected()
        with patch.object(skin, "probe_live_appearance", return_value="dark"):
            p = self.policy("slate")
            p.select("auto")
            self.assertEqual(p.selected, "modus-vivendi")

    def test_scope_rechecked_and_disabled_does_not_probe(self):
        with patch.object(skin, "probe_live_appearance") as probe:
            self.assertIsNone(skin.live_policy("default", self.home / "profiles/math"))
            for env in ({"HERMES_MACOS_SKIN_SYNC": "0"}, {skin.CAPABILITY_HOME: ""}, {"SSH_TTY": "yes"}):
                with patch.dict(os.environ, env):
                    self.assertIsNone(self.policy())
            probe.assert_not_called()

    def test_prepare_clears_capability_on_noninteractive_reentry(self):
        skin.prepare_chat(SimpleNamespace(query="test"), self.home)
        self.assertNotIn(skin.CAPABILITY_HOME, os.environ)
        with patch.object(skin, "probe_live_appearance") as probe:
            self.assertIsNone(self.policy())
            probe.assert_not_called()

    def test_live_probe_is_narrow_bounded_and_uncached(self):
        with patch.object(skin.subprocess, "run", return_value=SimpleNamespace(stdout="dark\n")) as run:
            self.assertEqual(skin.probe_live_appearance(), "dark")
            self.assertEqual(skin.probe_live_appearance(), "dark")
            self.assertEqual(run.call_count, 2)
            self.assertLessEqual(run.call_args.kwargs["timeout"], 2)
            self.assertNotIn("export", run.call_args.args[0])
            self.assertIn("AppleInterfaceStyle", " ".join(run.call_args.args[0]))
        for result, expected in (("light\n", "light"), ("garbage", None)):
            with patch.object(skin.subprocess, "run", return_value=SimpleNamespace(stdout=result)):
                self.assertEqual(skin.probe_live_appearance(), expected)
        for error in (OSError(), subprocess.TimeoutExpired("probe", 1), subprocess.CalledProcessError(1, "probe")):
            with patch.object(skin.subprocess, "run", side_effect=error):
                self.assertIsNone(skin.probe_live_appearance())


class ServerLiveTests(LivePolicyTests):
    """Execute full real RPC functions with real skin engine and policy, no agent."""
    def setUp(self):
        super().setUp()
        try:
            import hermes_cli.skin_engine as engine
        except ModuleNotFoundError:
            self.skipTest("requires patched Hermes source on PYTHONPATH")
        self.engine = engine
        self.module_patch = patch.dict(sys.modules, {"hermes_cli.macos_skin": skin})
        self.module_patch.start()
        self.addCleanup(self.module_patch.stop)
        source = Path(engine.__file__).parents[1] / "tui_gateway/server.py"
        text = source.read_text()
        if '@method("skin.refresh")' not in text:
            target = self.home / "source/tui_gateway/server.py"
            target.parent.mkdir(parents=True)
            target.write_text(text)
            result = subprocess.run(["patch", "--batch", "-p1", "-i", str(ROOT / "patches/macos-live-skin-server.patch")], cwd=target.parents[1], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            text = target.read_text()
        tree = ast.parse(text)
        self.methods, self.events, self.writes = {}, [], []
        self.config = {"display": {"skin": "default", "streaming": True}}
        def register(name):
            def dec(fn):
                self.methods[name] = fn
                return fn
            return dec
        def write(key, value):
            self.writes.append((key, value))
            self.config["display"][key.split(".")[-1]] = value
        scope = {"method": register, "_load_cfg": lambda: self.config,
                 "_ok": lambda rid, result: {"id": rid, "result": result},
                 "_err": lambda rid, code, message: {"id": rid, "error": {"code": code, "message": message}},
                 "_emit": lambda *args: self.events.append(args), "_sessions": {},
                 "_write_config_key": write}
        names = {"resolve_skin"}
        for node in tree.body:
            if not isinstance(node, ast.FunctionDef):
                continue
            decorators = [ast.unparse(d) for d in node.decorator_list]
            if node.name in names or any(d in {"method('skin.refresh')", "method('config.set')", "method('config.get')"} for d in decorators):
                exec(compile(ast.Module(body=[node], type_ignores=[]), str(source), "exec"), scope)
        self.scope = scope
        self.assertIn("skin.refresh", self.methods)
        # Live and manual RPC stay on the serialized main-thread fast path.
        long_handlers = next(n for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "_LONG_HANDLERS" for t in n.targets))
        self.assertNotIn("skin.refresh", ast.unparse(long_handlers))
        self.assertNotIn("config.set", ast.unparse(long_handlers))

    def rpc(self, method, **params):
        return self.methods[method](1, params)

    def test_rpc_refresh_payload_and_change_only_event(self):
        with patch.object(skin, "probe_live_appearance", return_value="dark") as probe:
            first = self.scope["resolve_skin"]()
            self.assertEqual(first["mode"], "auto")
            self.assertEqual(self.rpc("skin.refresh")["result"], first)
            self.assertEqual(self.events, [])
            probe.return_value = "light"
            result = self.rpc("skin.refresh")["result"]
            self.assertEqual(result["name"], "modus-operandi")
            self.assertEqual(set(result), {"name", "colors", "branding", "banner_logo", "banner_hero", "tool_prefix", "help_header", "mode", "appearance", "source"})
            self.assertEqual(self.events, [("skin.changed", "", result)])
            self.rpc("skin.refresh")
            self.assertEqual(len(self.events), 1)
            probe.return_value = None
            self.assertEqual(self.rpc("skin.refresh")["result"], result)
            self.assertEqual(len(self.events), 1)

    def test_rpc_manual_auto_no_writes_and_read_metadata(self):
        with patch.object(skin, "probe_live_appearance", return_value="dark") as probe:
            self.scope["resolve_skin"]()
            result = self.rpc("config.set", key="skin", value="slate")["result"]
            self.assertEqual(result["value"], "slate")
            self.assertEqual(result["mode"], "manual")
            probe.reset_mock()
            self.rpc("skin.refresh")
            read = self.rpc("config.get", key="skin")["result"]
            self.assertEqual(read, {"value": "slate", "mode": "manual", "appearance": None, "source": "macos"})
            probe.assert_not_called()
            probe.return_value = "light"
            result = self.rpc("config.set", key="skin", value="auto")["result"]
            self.assertEqual(result["value"], "modus-operandi")
            self.assertEqual(result["mode"], "auto")
            self.assertEqual(self.writes, [])
            self.assertEqual(self.config["display"]["skin"], "default")
            count = len(self.events)
            self.rpc("config.set", key="skin", value="auto")
            self.assertEqual(len(self.events), count)

    def test_same_palette_manual_auto_emits_mode_change_for_polling(self):
        with patch.object(skin, "probe_live_appearance", return_value="dark"):
            self.scope["resolve_skin"]()
            self.rpc("config.set", key="skin", value="modus-vivendi")
            self.assertEqual(self.events[-1][2]["mode"], "manual")
            self.rpc("config.set", key="skin", value="auto")
            self.assertEqual(self.events[-1][2]["mode"], "auto")
            self.assertEqual(len(self.events), 2)
            self.assertEqual(self.writes, [])

    def test_out_of_scope_whitespace_auto_rejected(self):
        os.environ.pop(skin.CAPABILITY_HOME)
        os.environ.pop(skin.SESSION_HOME)
        self.assertIn("error", self.rpc("config.set", key="skin", value=" auto "))
        self.assertEqual(self.writes, [])

    def test_out_of_scope_auto_rejected_manual_persisted(self):
        os.environ.pop(skin.CAPABILITY_HOME)
        os.environ.pop(skin.SESSION_HOME)
        with patch.object(skin, "probe_live_appearance") as probe:
            result = self.rpc("config.set", key="skin", value="auto")
            self.assertEqual(result["error"]["code"], 4002)
            self.assertIn("default", result["error"]["message"])
            self.assertEqual(self.writes, [])
            self.rpc("config.set", key="skin", value="slate")
            self.assertEqual(self.writes, [("display.skin", "slate")])
            self.assertEqual(self.rpc("skin.refresh")["result"]["mode"], "disabled")
            probe.assert_not_called()


if __name__ == "__main__":
    unittest.main()
