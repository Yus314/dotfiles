#!/usr/bin/env python3
"""Encrypt a Kaggle personal API token without printing it or writing plaintext.

Run from a local terminal for hidden input, use --from-clipboard on macOS, or
pass --from-file with a token file. Token values never enter command arguments.
"""

from __future__ import annotations

import argparse
import getpass
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import warnings

ROOT = Path(__file__).resolve().parents[2]
DESTINATION = ROOT / "applications/kaggle/secrets.yaml"


def read_clipboard_token() -> str:
    result = subprocess.run(
        ["/usr/bin/pbpaste"], capture_output=True, text=True, timeout=10
    )
    token = result.stdout.strip()
    if result.returncode != 0 or not token.startswith("KGAT_"):
        raise ValueError("The clipboard must contain a Kaggle API token beginning with KGAT_.")
    return token


def encrypt_token(token: str, sops: str) -> bytes:
    token = token.strip()
    if not token or any(character.isspace() for character in token):
        raise ValueError("Enter one non-empty token without internal whitespace.")
    if token.startswith(("{", "export ", "KAGGLE_API_TOKEN=")):
        raise ValueError("Supply only the API token, not JSON or an environment assignment.")
    result = subprocess.run(
        [
            sops,
            "--config",
            str(ROOT / ".sops.yaml"),
            "encrypt",
            "--filename-override",
            "applications/kaggle/secrets.yaml",
            "--input-type",
            "json",
            "--output-type",
            "yaml",
            "/dev/stdin",
        ],
        input=json.dumps({"api_token": token}).encode(),
        capture_output=True,
        cwd=ROOT,
    )
    if result.returncode != 0 or not result.stdout.startswith(b"api_token: ENC["):
        # Do not relay subprocess diagnostics, which may contain input data.
        raise RuntimeError("SOPS encryption failed; check the repository recipient keys.")
    verified = subprocess.run(
        [sops, "decrypt", "--input-type", "yaml", "--output-type", "json", "/dev/stdin"],
        input=result.stdout,
        capture_output=True,
        cwd=ROOT,
    )
    if verified.returncode != 0:
        raise RuntimeError("Cannot decrypt the new ciphertext; check your local SOPS key.")
    if json.loads(verified.stdout) != {"api_token": token}:
        raise RuntimeError("SOPS round-trip verification failed.")
    return result.stdout


def write_ciphertext(ciphertext: bytes) -> None:
    # Atomic replacement preserves the previous credential if encryption fails.
    # The temporary file contains ciphertext only and is private from creation.
    fd, temporary = tempfile.mkstemp(prefix=".secrets-", suffix=".yaml", dir=DESTINATION.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(ciphertext)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, DESTINATION)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--from-file", type=Path, help="Path to a file containing only the token")
    source.add_argument("--from-clipboard", action="store_true", help="Read the macOS clipboard without displaying it")
    parser.add_argument("--sops", default=shutil.which("sops"), help="SOPS executable path")
    args = parser.parse_args()
    if not args.sops:
        parser.error("sops is not on PATH; run this command through nix shell with SOPS.")
    try:
        if args.from_file:
            token = args.from_file.expanduser().read_text(encoding="utf-8")
        elif args.from_clipboard:
            token = read_clipboard_token()
        else:
            # Refuse getpass's visible-input fallback when no terminal is available.
            with warnings.catch_warnings():
                warnings.simplefilter("error", getpass.GetPassWarning)
                token = getpass.getpass("Kaggle API Token (hidden): ")
        write_ciphertext(encrypt_token(token, args.sops))
    except (OSError, ValueError, RuntimeError, EOFError, getpass.GetPassWarning, subprocess.SubprocessError):
        print("Registration failed; check the input, SOPS recipient keys and local decryption key.")
        return 1
    except KeyboardInterrupt:
        print("Registration cancelled.")
        return 1
    print("Saved and verified applications/kaggle/secrets.yaml (encrypted).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
