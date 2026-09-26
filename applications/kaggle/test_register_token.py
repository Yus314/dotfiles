"""Check credential confidentiality and failure behavior without real credentials."""

import contextlib
import getpass
import io
import json
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import register_token as registration


class RegistrationTests(unittest.TestCase):
    def test_clipboard_is_captured_without_display(self):
        token = "KGAT_dummy-not-a-real-token"
        output = io.StringIO()
        with (
            patch.object(
                registration.subprocess,
                "run",
                return_value=subprocess.CompletedProcess([], 0, token + "\n", ""),
            ) as run,
            contextlib.redirect_stdout(output),
            contextlib.redirect_stderr(output),
        ):
            self.assertEqual(registration.read_clipboard_token(), token)
        self.assertEqual(output.getvalue(), "")
        self.assertTrue(run.call_args.kwargs["capture_output"])

    def test_clipboard_rejects_unrelated_content(self):
        with patch.object(
            registration.subprocess,
            "run",
            return_value=subprocess.CompletedProcess([], 0, "unrelated clipboard text", ""),
        ):
            with self.assertRaises(ValueError):
                registration.read_clipboard_token()

    def test_rejects_empty_json_and_shell_assignments(self):
        with patch.object(registration.subprocess, "run") as run:
            for value in ("", "\n", '{"key":"legacy"}', "KAGGLE_API_TOKEN=example", "two tokens"):
                with self.subTest(value=value), self.assertRaises(ValueError):
                    registration.encrypt_token(value, "sops")
            run.assert_not_called()

    def test_secret_uses_stdin_and_ciphertext_round_trips(self):
        token = "dummy-test-token"
        ciphertext = b"api_token: ENC[dummy-ciphertext]\n"
        results = [
            subprocess.CompletedProcess([], 0, ciphertext, b""),
            subprocess.CompletedProcess([], 0, json.dumps({"api_token": token}).encode(), b""),
        ]
        with patch.object(registration.subprocess, "run", side_effect=results) as run:
            self.assertEqual(registration.encrypt_token(token, "sops"), ciphertext)
            for call in run.call_args_list:
                self.assertNotIn(token, repr(call.args))
                self.assertTrue(call.kwargs["capture_output"])
            self.assertEqual(json.loads(run.call_args_list[0].kwargs["input"]), {"api_token": token})

    def test_failed_encryption_keeps_previous_file_and_hides_diagnostics(self):
        token = "dummy-test-secret-in-error"
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "secrets.yaml"
            source = Path(directory) / "token"
            destination.write_bytes(b"existing ciphertext")
            source.write_text(token)
            output = io.StringIO()
            with (
                patch.object(registration, "DESTINATION", destination),
                patch("sys.argv", ["register_token.py", "--sops", "sops", "--from-file", str(source)]),
                patch.object(
                    registration.subprocess,
                    "run",
                    return_value=subprocess.CompletedProcess([], 1, token.encode(), token.encode()),
                ),
                contextlib.redirect_stdout(output),
                contextlib.redirect_stderr(output),
            ):
                self.assertEqual(registration.main(), 1)
            self.assertNotIn(token, output.getvalue())
            self.assertEqual(destination.read_bytes(), b"existing ciphertext")

    def test_refuses_mismatched_round_trip(self):
        results = [
            subprocess.CompletedProcess([], 0, b"api_token: ENC[dummy]\n", b""),
            subprocess.CompletedProcess([], 0, b'{"api_token":"different"}', b""),
        ]
        with patch.object(registration.subprocess, "run", side_effect=results):
            with self.assertRaises(RuntimeError):
                registration.encrypt_token("dummy-token", "sops")

    def test_refuses_visible_input_fallback(self):
        with (
            patch("sys.argv", ["register_token.py", "--sops", "sops"]),
            patch.object(registration.getpass, "getpass", side_effect=getpass.GetPassWarning),
            patch.object(registration.subprocess, "run") as run,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            self.assertEqual(registration.main(), 1)
            run.assert_not_called()

    def test_atomic_replacement_is_private_and_cleans_temporary_file(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "secrets.yaml"
            destination.write_bytes(b"old ciphertext")
            with patch.object(registration, "DESTINATION", destination):
                registration.write_ciphertext(b"new ciphertext")
            self.assertEqual(destination.read_bytes(), b"new ciphertext")
            self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o600)
            self.assertEqual(list(Path(directory).iterdir()), [destination])


if __name__ == "__main__":
    unittest.main()
