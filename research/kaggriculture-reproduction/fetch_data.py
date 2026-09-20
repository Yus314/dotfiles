"""Fetch public replay JSON listed in a frozen manifest; no Kaggle credentials."""

import argparse, concurrent.futures, gzip, hashlib, json, os, urllib.request
from pathlib import Path

ROOT = Path(__file__).parent
DEFAULT_DATA = Path(os.environ.get("KAGGRICULTURE_DATA", ROOT / "data")).expanduser()


def fetch(entry, data):
    eid = entry["id"]
    path = data / f"episode-{eid}.json.gz"
    if path.exists():
        raw = gzip.decompress(path.read_bytes())
    else:
        req = urllib.request.Request(
            f"https://www.kaggleusercontent.com/episodes/{eid}.json",
            headers={"User-Agent": "KaggricultureReplayResearch/1.0"},
        )
        with urllib.request.urlopen(req, timeout=90) as f:
            raw = f.read()
        parsed = json.loads(raw)
        if len(parsed.get("steps", [])) != 720:
            raise ValueError(f"Incomplete replay: {eid}")
        path.write_bytes(gzip.compress(raw, compresslevel=6, mtime=0))
    print("downloaded", eid, flush=True)
    return str(eid), hashlib.sha256(raw).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--data", type=Path, default=DEFAULT_DATA)
    args = parser.parse_args()
    args.data.mkdir(parents=True, exist_ok=True)
    entries = json.loads(args.manifest.read_text())["episodes"]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        hashes = dict(pool.map(lambda e: fetch(e, args.data), entries))
    args.manifest.with_name(args.manifest.stem + "-sha256.json").write_text(
        json.dumps(hashes, indent=2)
    )


if __name__ == "__main__":
    main()
