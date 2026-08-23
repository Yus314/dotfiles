#!/usr/bin/env python3
"""Read-only MCP broker for one immutable synthetic AT-SPI target.

The broker never starts computer-use-linux's MCP server and never exposes its
capture, input, setup, or window tools. It permits only the CLI's `apps` and
`state` commands, verifies the target process identity before and after state
collection, and projects the result onto a small non-sensitive schema.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

APP_NAME = "hermes-computer-use-synthetic-target"
MAX_REQUEST_BYTES = 64 * 1024
MAX_OUTPUT_BYTES = 64 * 1024
MAX_NODES = 64
MAX_DEPTH = 8
MAX_STRING = 160
KNOWN_NAMES = {
    APP_NAME,
    "Hermes Synthetic Accessibility Target",
    "Synthetic accessibility fixture v1",
    "Synthetic text field",
    "Pilot checkbox enabled",
    "Alpha option",
    "Beta option",
    "Synthetic action button",
    "Disabled synthetic button",
    "Fixture status: ready",
}
SAFE_ENV_KEYS = (
    "HOME",
    "USER",
    "LANG",
    "LC_ALL",
    "LC_CTYPE",
    "XDG_RUNTIME_DIR",
)
SUPPORTED_PROTOCOL_VERSIONS = (
    "2025-11-25",
    "2025-06-18",
    "2025-03-26",
    "2024-11-05",
)

TOOLS = [
    {
        "name": "doctor",
        "description": "Report readiness of the synthetic read-only accessibility fixture.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "annotations": {
            "readOnlyHint": True,
            "destructiveHint": False,
            "idempotentHint": True,
            "openWorldHint": False,
        },
    },
    {
        "name": "list_apps",
        "description": "List only the allowlisted synthetic accessibility fixture.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "annotations": {
            "readOnlyHint": True,
            "destructiveHint": False,
            "idempotentHint": True,
            "openWorldHint": False,
        },
    },
    {
        "name": "get_app_state",
        "description": "Read a bounded, projected AT-SPI tree from the synthetic fixture only.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "annotations": {
            "readOnlyHint": True,
            "destructiveHint": False,
            "idempotentHint": True,
            "openWorldHint": False,
        },
    },
]


class BrokerError(RuntimeError):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


class Broker:
    def __init__(self, computer_use: Path, target_executable: Path, timeout: float = 10.0):
        self.computer_use = computer_use.resolve(strict=True)
        self.target_executable = target_executable.resolve(strict=True)
        self.timeout = timeout

    def _run(self, *args: str) -> Any:
        environment = {key: os.environ[key] for key in SAFE_ENV_KEYS if key in os.environ}
        try:
            completed = subprocess.run(
                [str(self.computer_use), *args],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=self.timeout,
                check=False,
                env=environment,
            )
        except subprocess.TimeoutExpired as error:
            raise BrokerError("UPSTREAM_TIMEOUT") from error
        if completed.returncode != 0 or len(completed.stdout) > MAX_OUTPUT_BYTES:
            raise BrokerError("UPSTREAM_FAILED")
        try:
            return json.loads(completed.stdout)
        except (json.JSONDecodeError, UnicodeDecodeError) as error:
            raise BrokerError("UPSTREAM_INVALID_OUTPUT") from error

    @staticmethod
    def _start_time(pid: int) -> str:
        try:
            # The comm field may contain spaces and parentheses; fields after the
            # final ')' begin at proc field 3. Start time is proc field 22.
            suffix = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
            return suffix[19]
        except (OSError, IndexError) as error:
            raise BrokerError("TARGET_NOT_READY") from error

    def _identity(self) -> dict[str, Any]:
        apps = self._run("apps")
        if not isinstance(apps, list):
            raise BrokerError("UPSTREAM_INVALID_OUTPUT")
        matches = [
            app
            for app in apps
            if isinstance(app, dict)
            and app.get("name") == APP_NAME
            and app.get("role") == "application"
            and isinstance(app.get("pid"), int)
            and isinstance(app.get("object_ref"), str)
        ]
        if len(matches) != 1:
            raise BrokerError("TARGET_NOT_READY")
        match = matches[0]
        pid = match["pid"]
        try:
            executable = Path(f"/proc/{pid}/exe").resolve(strict=True)
        except OSError as error:
            raise BrokerError("TARGET_NOT_READY") from error
        if executable != self.target_executable:
            raise BrokerError("IDENTITY_MISMATCH")
        return {
            "pid": pid,
            "start_time": self._start_time(pid),
            "object_ref": match["object_ref"],
        }

    @staticmethod
    def _bus_name(object_ref: str) -> str:
        if not object_ref.startswith(":") or "/" not in object_ref:
            raise BrokerError("STATE_POLICY_VIOLATION")
        return object_ref.split("/", 1)[0]

    @staticmethod
    def _safe_name(value: Any) -> str | None:
        if value is None:
            return None
        if not isinstance(value, str) or len(value.encode("utf-8")) > MAX_STRING:
            raise BrokerError("STATE_POLICY_VIOLATION")
        return value if value in KNOWN_NAMES else None

    def target_status(self) -> bool:
        try:
            self._identity()
            return True
        except BrokerError:
            return False

    def doctor(self) -> dict[str, Any]:
        ready = self.target_status()
        return {
            "ok": ready,
            "broker_version": 1,
            "target": {"id": "synthetic-gtk", "status": "ready" if ready else "unavailable"},
            "policy": {
                "read_only": True,
                "screenshots": False,
                "input": False,
                "host_apps": False,
                "sampling": False,
            },
        }

    def list_apps(self) -> dict[str, Any]:
        if not self.target_status():
            return {"apps": []}
        return {
            "apps": [
                {
                    "id": "synthetic-gtk",
                    "display_name": "Synthetic GTK Target",
                    "kind": "synthetic",
                    "status": "ready",
                }
            ]
        }

    def get_app_state(self) -> dict[str, Any]:
        before = self._identity()
        started = time.monotonic()
        raw = self._run("state", APP_NAME)
        after = self._identity()
        if before != after:
            raise BrokerError("TARGET_CHANGED")
        if not isinstance(raw, list) or not raw or len(raw) > MAX_NODES:
            raise BrokerError("STATE_POLICY_VIOLATION")
        expected_bus = self._bus_name(before["object_ref"])
        nodes: list[dict[str, Any]] = []
        for item in raw:
            if not isinstance(item, dict):
                raise BrokerError("STATE_POLICY_VIOLATION")
            object_ref = item.get("object_ref")
            if not isinstance(object_ref, str) or self._bus_name(object_ref) != expected_bus:
                raise BrokerError("STATE_POLICY_VIOLATION")
            index = item.get("index")
            parent = item.get("parent_index")
            depth = item.get("depth")
            role = item.get("role")
            states = item.get("states", [])
            child_count = item.get("child_count")
            if (
                not isinstance(index, int)
                or (parent is not None and not isinstance(parent, int))
                or not isinstance(depth, int)
                or depth > MAX_DEPTH
                or not isinstance(role, str)
                or len(role) > 64
                or not isinstance(states, list)
                or not all(isinstance(state, str) and len(state) <= 64 for state in states)
                or not isinstance(child_count, int)
            ):
                raise BrokerError("STATE_POLICY_VIOLATION")
            nodes.append(
                {
                    "id": index,
                    "parent_id": parent,
                    "depth": depth,
                    "role": role,
                    "name": self._safe_name(item.get("name")),
                    "states": states,
                    "child_count": child_count,
                }
            )
        root = nodes[0]
        if root["role"] != "application" or root["name"] != APP_NAME:
            raise BrokerError("STATE_POLICY_VIOLATION")
        return {
            "app_id": "synthetic-gtk",
            "complete": True,
            "node_count": len(nodes),
            "duration_ms": round((time.monotonic() - started) * 1000, 1),
            "nodes": nodes,
        }


def tool_result(payload: dict[str, Any], *, is_error: bool = False) -> dict[str, Any]:
    return {
        "content": [{"type": "text", "text": json.dumps(payload, separators=(",", ":"))}],
        "isError": is_error,
    }


def handle_request(broker: Broker, request: dict[str, Any]) -> dict[str, Any] | None:
    method = request.get("method")
    if "id" not in request:
        return None
    request_id = request["id"]
    if request.get("jsonrpc") != "2.0" or request_id is None:
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "error": {"code": -32600, "message": "Invalid Request"},
        }
    if method == "initialize":
        params = request.get("params")
        if not isinstance(params, dict) or not isinstance(params.get("protocolVersion"), str):
            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {"code": -32602, "message": "Invalid params"},
            }
        requested_version = params["protocolVersion"]
        version = (
            requested_version
            if requested_version in SUPPORTED_PROTOCOL_VERSIONS
            else SUPPORTED_PROTOCOL_VERSIONS[0]
        )
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {
                "protocolVersion": version,
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "computer-use-readonly-pilot", "version": "1"},
            },
        }
    if method == "ping":
        return {"jsonrpc": "2.0", "id": request_id, "result": {}}
    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": request_id, "result": {"tools": TOOLS}}
    if method == "tools/call":
        params = request.get("params")
        if not isinstance(params, dict) or params.get("arguments", {}) != {}:
            result = tool_result({"error": "INVALID_ARGUMENTS"}, is_error=True)
        else:
            name = params.get("name")
            try:
                if name == "doctor":
                    payload = broker.doctor()
                elif name == "list_apps":
                    payload = broker.list_apps()
                elif name == "get_app_state":
                    payload = broker.get_app_state()
                else:
                    raise BrokerError("UNKNOWN_TOOL")
                result = tool_result(payload)
            except BrokerError as error:
                result = tool_result({"error": error.code}, is_error=True)
        return {"jsonrpc": "2.0", "id": request_id, "result": result}
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "error": {"code": -32601, "message": "Method not found"},
    }


def write_response(response: dict[str, Any]) -> None:
    encoded = json.dumps(response, separators=(",", ":")).encode() + b"\n"
    if len(encoded) > MAX_OUTPUT_BYTES:
        encoded = (
            b'{"jsonrpc":"2.0","id":null,'
            b'"error":{"code":-32603,"message":"Internal error"}}\n'
        )
    sys.stdout.buffer.write(encoded)
    sys.stdout.buffer.flush()


def serve(broker: Broker) -> None:
    while True:
        raw_line = sys.stdin.buffer.readline(MAX_REQUEST_BYTES + 1)
        if not raw_line:
            break
        if len(raw_line) > MAX_REQUEST_BYTES:
            while raw_line and not raw_line.endswith(b"\n"):
                raw_line = sys.stdin.buffer.readline(MAX_REQUEST_BYTES + 1)
            write_response(
                {
                    "jsonrpc": "2.0",
                    "id": None,
                    "error": {"code": -32600, "message": "Invalid Request"},
                }
            )
            continue
        try:
            request = json.loads(raw_line)
        except (json.JSONDecodeError, UnicodeDecodeError):
            write_response(
                {
                    "jsonrpc": "2.0",
                    "id": None,
                    "error": {"code": -32700, "message": "Parse error"},
                }
            )
            continue
        if not isinstance(request, dict):
            write_response(
                {
                    "jsonrpc": "2.0",
                    "id": None,
                    "error": {"code": -32600, "message": "Invalid Request"},
                }
            )
            continue
        response = handle_request(broker, request)
        if response is not None:
            write_response(response)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--computer-use", required=True, type=Path)
    parser.add_argument("--target-executable", required=True, type=Path)
    args = parser.parse_args()
    serve(Broker(args.computer_use, args.target_executable))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
