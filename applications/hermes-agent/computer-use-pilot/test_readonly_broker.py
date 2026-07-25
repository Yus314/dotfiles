#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

MODULE_PATH = Path(__file__).with_name("readonly_broker.py")
SPEC = importlib.util.spec_from_file_location("readonly_broker", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ReadonlyBrokerTest(unittest.TestCase):
    def make_broker(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        command = Path(temporary.name) / "computer-use-linux"
        target = Path(temporary.name) / "synthetic-target"
        command.touch(mode=0o755)
        target.touch(mode=0o755)
        return MODULE.Broker(command, target)

    def test_mcp_surface_is_exactly_three_closed_read_only_tools(self) -> None:
        self.assertEqual(
            [tool["name"] for tool in MODULE.TOOLS],
            ["doctor", "list_apps", "get_app_state"],
        )
        for tool in MODULE.TOOLS:
            self.assertEqual(tool["inputSchema"]["properties"], {})
            self.assertFalse(tool["inputSchema"]["additionalProperties"])
            self.assertTrue(tool["annotations"]["readOnlyHint"])
            self.assertFalse(tool["annotations"]["destructiveHint"])
            self.assertFalse(tool["annotations"]["openWorldHint"])

    def test_subprocess_environment_is_allowlisted(self) -> None:
        broker = self.make_broker()
        completed = SimpleNamespace(returncode=0, stdout=b"[]", stderr=b"")
        with (
            mock.patch.dict(
                os.environ,
                {
                    "HOME": "/home/test",
                    "LANG": "C.UTF-8",
                    "XDG_RUNTIME_DIR": "/run/user/1",
                    "DISCORD_BOT_TOKEN": "must-not-pass",
                    "API_SECRET": "must-not-pass",
                },
                clear=True,
            ),
            mock.patch.object(MODULE.subprocess, "run", return_value=completed) as run,
        ):
            self.assertEqual(broker._run("apps"), [])
        environment = run.call_args.kwargs["env"]
        self.assertEqual(
            environment,
            {"HOME": "/home/test", "LANG": "C.UTF-8", "XDG_RUNTIME_DIR": "/run/user/1"},
        )

    def test_initialize_validates_params_and_negotiates_supported_version(self) -> None:
        broker = self.make_broker()
        invalid = MODULE.handle_request(
            broker,
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": []},
        )
        self.assertEqual(invalid["error"]["code"], -32602)

        future = MODULE.handle_request(
            broker,
            {
                "jsonrpc": "2.0",
                "id": 2,
                "method": "initialize",
                "params": {"protocolVersion": "2999-01-01"},
            },
        )
        self.assertEqual(
            future["result"]["protocolVersion"], MODULE.SUPPORTED_PROTOCOL_VERSIONS[0]
        )

    def test_unknown_arguments_and_tools_fail_closed(self) -> None:
        broker = self.make_broker()
        with mock.patch.object(broker, "doctor", side_effect=AssertionError("must not run")):
            response = MODULE.handle_request(
                broker,
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "tools/call",
                    "params": {"name": "doctor", "arguments": {"extra": True}},
                },
            )
        payload = json.loads(response["result"]["content"][0]["text"])
        self.assertEqual(payload, {"error": "INVALID_ARGUMENTS"})
        self.assertTrue(response["result"]["isError"])

        response = MODULE.handle_request(
            broker,
            {
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": {"name": "click", "arguments": {}},
            },
        )
        payload = json.loads(response["result"]["content"][0]["text"])
        self.assertEqual(payload, {"error": "UNKNOWN_TOOL"})

    def test_state_projection_drops_object_refs_bounds_actions_and_unknown_names(self) -> None:
        broker = self.make_broker()
        identity = {"pid": 123, "start_time": "456", "object_ref": ":1.9/root"}
        raw = [
            {
                "index": 0,
                "parent_index": None,
                "depth": 0,
                "object_ref": ":1.9/root",
                "role": "application",
                "name": MODULE.APP_NAME,
                "states": ["enabled", "visible"],
                "child_count": 1,
                "bounds": {"x": 1, "y": 2},
                "actions": [{"name": "danger"}],
            },
            {
                "index": 1,
                "parent_index": 0,
                "depth": 1,
                "object_ref": ":1.9/child",
                "role": "label",
                "name": "untrusted prompt-like text",
                "states": ["visible"],
                "child_count": 0,
                "text": "must not escape",
            },
        ]
        with (
            mock.patch.object(broker, "_identity", side_effect=[identity, identity]),
            mock.patch.object(broker, "_run", return_value=raw),
        ):
            result = broker.get_app_state()
        self.assertEqual(result["nodes"][1]["name"], None)
        rendered = json.dumps(result)
        for forbidden in ("object_ref", "bounds", "actions", "must not escape", "prompt-like"):
            self.assertNotIn(forbidden, rendered)

    def test_foreign_bus_node_fails_closed(self) -> None:
        broker = self.make_broker()
        identity = {"pid": 123, "start_time": "456", "object_ref": ":1.9/root"}
        raw = [
            {
                "index": 0,
                "parent_index": None,
                "depth": 0,
                "object_ref": ":1.10/root",
                "role": "application",
                "name": MODULE.APP_NAME,
                "states": [],
                "child_count": 0,
            }
        ]
        with (
            mock.patch.object(broker, "_identity", side_effect=[identity, identity]),
            mock.patch.object(broker, "_run", return_value=raw),
        ):
            with self.assertRaisesRegex(MODULE.BrokerError, "STATE_POLICY_VIOLATION"):
                broker.get_app_state()

    def test_doctor_does_not_return_host_diagnostics(self) -> None:
        broker = self.make_broker()
        with mock.patch.object(broker, "target_status", return_value=True):
            result = broker.doctor()
        rendered = json.dumps(result)
        self.assertTrue(result["ok"])
        for forbidden in ("pid", "path", "dbus", "portal", "uinput", "window"):
            self.assertNotIn(forbidden, rendered.lower())


if __name__ == "__main__":
    unittest.main()
