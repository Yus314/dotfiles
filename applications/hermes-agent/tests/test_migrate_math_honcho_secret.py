from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts/migrate_math_honcho_secret.py"


class MathHonchoMigrationTests(unittest.TestCase):
    def test_runtime_source_is_migrated_over_stdin_with_presence_only_output(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            tmp = Path(name)
            secret_file = tmp / "secrets.yaml"
            secret_file.write_text("encrypted-fixture\n")
            source_env = tmp / "lawliet.env"
            marker = "opaque-fixture-credential"
            source_env.write_text(f"OTHER=value\nHONCHO_API_KEY={marker}\n")
            capture = tmp / "capture.json"
            fake_sops = tmp / "sops"
            fake_sops.write_text(
                "#!/bin/sh\n"
                "if [ \"$1\" = decrypt ]; then printf 'OTHER=value\\n'; exit 0; fi\n"
                "if [ \"$1\" = set ]; then cat > \"$CAPTURE\"; exit 0; fi\n"
                "exit 2\n"
            )
            fake_sops.chmod(0o700)
            env = dict(os.environ, CAPTURE=str(capture))
            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--secret-file",
                    str(secret_file),
                    "--lawliet-env",
                    str(source_env),
                    "--sops",
                    str(fake_sops),
                ],
                text=True,
                capture_output=True,
                env=env,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(result.stdout, "source=present target=present\n")
            self.assertNotIn(marker, result.stdout + result.stderr)
            self.assertEqual(json.loads(capture.read_text()), f"HONCHO_API_KEY={marker}\n")

    def test_missing_source_blocks_without_secret_output(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            tmp = Path(name)
            secret_file = tmp / "secrets.yaml"
            secret_file.write_text("encrypted-fixture\n")
            fake_sops = tmp / "sops"
            fake_sops.write_text("#!/bin/sh\nprintf 'OTHER=value\\n'\n")
            fake_sops.chmod(0o700)
            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--secret-file",
                    str(secret_file),
                    "--lawliet-env",
                    str(tmp / "missing.env"),
                    "--sops",
                    str(fake_sops),
                ],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("migration blocked", result.stderr)
            self.assertNotIn("HONCHO_API_KEY=", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
