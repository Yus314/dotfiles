#!/usr/bin/env python3
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "gateway_preflight.py"
SPEC = importlib.util.spec_from_file_location("gateway_preflight", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load {SCRIPT}")
gateway_preflight = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = gateway_preflight
SPEC.loader.exec_module(gateway_preflight)


class GatewayPreflightTests(unittest.TestCase):
    def write_config(self, directory: str, text: str, *, dotenv: str = "") -> Path:
        path = Path(directory) / "config.yaml"
        path.write_text(text)
        (path.parent / ".env").write_text(dotenv)
        return path

    def test_accepts_exact_string_or_integer_channel(self):
        with tempfile.TemporaryDirectory() as tmp:
            string_path = self.write_config(tmp, 'discord:\n  allowed_channels: "123"\n')
            gateway_preflight.validate(string_path, "123")
            integer_path = self.write_config(tmp, "discord:\n  allowed_channels: 123\n")
            gateway_preflight.validate(integer_path, "123")

    def test_rejects_empty_extra_or_wrong_channels(self):
        with tempfile.TemporaryDirectory() as tmp:
            for value in ('""', '"123,456"', '"456"'):
                path = self.write_config(tmp, f"discord:\n  allowed_channels: {value}\n")
                with self.assertRaises(ValueError):
                    gateway_preflight.validate(path, "123")

    def test_rejects_missing_malformed_and_non_mapping_configs(self):
        with tempfile.TemporaryDirectory() as tmp:
            missing = Path(tmp) / "missing.yaml"
            with self.assertRaises(ValueError):
                gateway_preflight.validate(missing, "123")
            for text in ("discord: [", "[]\n", "discord: []\n"):
                path = self.write_config(tmp, text)
                with self.assertRaises(ValueError):
                    gateway_preflight.validate(path, "123")

    def test_rejects_missing_or_security_sensitive_profile_dotenv(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write_config(tmp, 'discord:\n  allowed_channels: "123"\n')
            (path.parent / ".env").unlink()
            with self.assertRaises(ValueError):
                gateway_preflight.validate(path, "123")

            for assignment in (
                "DISCORD_BOT_TOKEN=x",
                "export DISCORD_ALLOWED_CHANNELS=*",
                "DISCORD_ALLOWED_ROLES=admin",
                "DISCORD_ALLOW_BOTS=true",
                "GATEWAY_ALLOW_ALL_USERS=true",
                "DISCORD_HEALTH_BOT_TOKEN=x",
                "DISCORD_FOOD=x",
                "SAFE_KEY=valueDISCORD_ALLOWED_USERS=attacker",
                "SAFE_KEY=valueDISCORD_HEALTH_BOT_TOKEN=attacker",
            ):
                path = self.write_config(
                    tmp,
                    'discord:\n  allowed_channels: "123"\n',
                    dotenv=assignment + "\n",
                )
                with self.assertRaises(ValueError, msg=assignment):
                    gateway_preflight.validate(path, "123")

    def test_rejects_overriding_external_secret_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write_config(
                tmp,
                "discord:\n  allowed_channels: 123\n"
                "secrets:\n  bitwarden:\n    enabled: true\n    override_existing: true\n",
            )
            with self.assertRaises(ValueError):
                gateway_preflight.validate(path, "123")


if __name__ == "__main__":
    unittest.main()
