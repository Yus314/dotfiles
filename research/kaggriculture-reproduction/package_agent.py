"""Build a flat Kaggle agent archive and a separate reproducible research bundle."""

import gzip, hashlib, json, tarfile, zipfile
from pathlib import Path

ROOT = Path(__file__).parent
RUNTIME = [
    "main.py",
    "policy.py",
    "engine.py",
    "kaggriculture.json",
    "models.json.gz",
    "NOTICE.md",
    "LICENSE.engine",
    "requirements.txt",
]


def main():
    frozen = json.loads((ROOT / "FREEZE.json").read_text())
    for name, expected in frozen["runtime_sha256"].items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == expected, (
            f"Frozen runtime changed: {name}"
        )
    with (ROOT / "submission.tar.gz").open("wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w") as archive:
                for name in RUNTIME:
                    path = ROOT / name
                    info = archive.gettarinfo(str(path), arcname=name)
                    info.uid = info.gid = 0
                    info.uname = info.gname = ""
                    info.mtime = 0
                    with path.open("rb") as f:
                        archive.addfile(info, f)
    paths = [
        p
        for p in ROOT.iterdir()
        if p.is_file()
        and p.suffix in {".py", ".md", ".json", ".txt"}
        and p.name != "DELIVERY_SHA256.json"
    ] + [ROOT / "models.json.gz", ROOT / "LICENSE.engine", ROOT / "submission.tar.gz"]
    for directory in ["reports", "evidence", "baselines"]:
        if (ROOT / directory).exists():
            paths.extend(
                p
                for p in (ROOT / directory).rglob("*")
                if p.is_file() and "__pycache__" not in p.parts and p.suffix != ".pyc"
            )
    with zipfile.ZipFile(
        ROOT / "reproduction-bundle.zip", "w", zipfile.ZIP_DEFLATED
    ) as archive:
        for path in sorted(set(paths)):
            archive.write(path, path.relative_to(ROOT))
    hashes = {
        name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
        for name in ["submission.tar.gz", "reproduction-bundle.zip"]
    }
    (ROOT / "DELIVERY_SHA256.json").write_text(json.dumps(hashes, indent=2))
    print(json.dumps(hashes, indent=2))


if __name__ == "__main__":
    main()
