from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "generate-package-config.py"
SPEC = importlib.util.spec_from_file_location("generate_package_config", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
generate_package_config = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(generate_package_config)


class GeneratePackageConfigTest(unittest.TestCase):
    def test_profiles_name_full_minimal_and_all_explicitly(self):
        self.assertEqual(("emacs",), generate_package_config.PROFILES["full"])
        self.assertEqual(
            ("emacs-minimal",), generate_package_config.PROFILES["minimal"]
        )
        self.assertEqual(
            generate_package_config.APPLICATIONS,
            generate_package_config.PROFILES["all"],
        )

    def arrange_application(self, root: Path, name: str, source: str) -> Path:
        app_dir = root / name
        (app_dir / "elisp" / "modules").mkdir(parents=True)
        (app_dir / "emacspkg").mkdir()
        (app_dir / "elisp" / "init.org").write_text(source, encoding="utf-8")
        (app_dir / "elisp" / "modules" / "module.org").write_text(
            f"{source}-module", encoding="utf-8"
        )
        target = app_dir / "emacspkg" / "emacs-config.org"
        target.write_text("old", encoding="utf-8")
        return target

    def test_application_filter_updates_only_selected_application(self):
        with tempfile.TemporaryDirectory() as directory:
            applications_dir = Path(directory)
            emacs_target = self.arrange_application(applications_dir, "emacs", "full")
            minimal_target = self.arrange_application(
                applications_dir, "emacs-minimal", "minimal"
            )

            stale = generate_package_config.generate_configs(
                applications_dir, selected=("emacs",), check=False
            )

            self.assertEqual([emacs_target], stale)
            self.assertEqual("full\nfull-module", emacs_target.read_text(encoding="utf-8"))
            self.assertEqual("old", minimal_target.read_text(encoding="utf-8"))

    def test_invalid_application_fails_without_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            applications_dir = Path(directory)
            emacs_target = self.arrange_application(applications_dir, "emacs", "full")
            minimal_target = self.arrange_application(
                applications_dir, "emacs-minimal", "minimal"
            )

            with self.assertRaisesRegex(ValueError, "unknown application"):
                generate_package_config.generate_configs(
                    applications_dir,
                    selected=("emacs", "not-an-application"),
                    check=False,
                )

            self.assertEqual("old", emacs_target.read_text(encoding="utf-8"))
            self.assertEqual("old", minimal_target.read_text(encoding="utf-8"))

    def test_default_selection_checks_all_applications_without_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            applications_dir = Path(directory)
            emacs_target = self.arrange_application(applications_dir, "emacs", "full")
            minimal_target = self.arrange_application(
                applications_dir, "emacs-minimal", "minimal"
            )

            stale = generate_package_config.generate_configs(
                applications_dir, selected=None, check=True
            )

            self.assertEqual([emacs_target, minimal_target], stale)
            self.assertEqual("old", emacs_target.read_text(encoding="utf-8"))
            self.assertEqual("old", minimal_target.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
