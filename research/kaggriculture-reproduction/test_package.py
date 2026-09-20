"""Load only the shipping archive in an isolated Python subprocess."""

import copy, gzip, json, subprocess, sys, tarfile, tempfile, unittest
import policy
from fetch_data import DEFAULT_DATA


class TestPackage(unittest.TestCase):
    def test_isolated_archive_predictions_match_source(self):
        archive = policy.ROOT / "submission.tar.gz"
        if not archive.exists():
            self.skipTest("Run package_agent.py first")
        replay = json.loads(
            gzip.decompress((DEFAULT_DATA / "episode-111105944.json.gz").read_bytes())
        )
        observations = [
            copy.deepcopy(replay["steps"][t][1]["observation"])
            for t in [0, 1, 100, 300, 500, 718]
        ]
        policy._MODELS = None
        expected = [policy.agent(o) for o in observations]
        with tempfile.TemporaryDirectory(prefix="kaggriculture-package-") as directory:
            with tarfile.open(archive, "r:gz") as bundle:
                self.assertEqual(
                    set(bundle.getnames()),
                    {
                        "main.py",
                        "policy.py",
                        "engine.py",
                        "kaggriculture.json",
                        "models.json.gz",
                        "NOTICE.md",
                        "LICENSE.engine",
                        "requirements.txt",
                    },
                )
                bundle.extractall(directory, filter="data")
            code = "import sys,json;sys.path.insert(0,sys.argv[1]);from main import agent;print(json.dumps([agent(o) for o in json.load(sys.stdin)]))"
            result = subprocess.run(
                [sys.executable, "-I", "-c", code, directory],
                input=json.dumps(observations),
                text=True,
                capture_output=True,
                check=True,
                cwd=directory,
            )
            self.assertEqual(json.loads(result.stdout), expected)


if __name__ == "__main__":
    unittest.main()
