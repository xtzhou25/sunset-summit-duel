#!/usr/bin/env python3
"""Losslessly restore bundled models. Python 3.8+, standard library only."""
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "assets/compressed/manifest.json"
EXPECTED = {"assets/ha.glb", "assets/qi.glb", "assets/tao.glb"}
CHUNK = 1024 * 1024

def safe_path(relative):
    if not isinstance(relative, str) or "\\" in relative:
        raise ValueError("Invalid asset path")
    parts = PurePosixPath(relative)
    if parts.is_absolute() or any(x in ("", ".", "..") for x in relative.split("/")):
        raise ValueError("Unsafe asset path: " + relative)
    target = ROOT.joinpath(*parts.parts)
    current = ROOT
    for part in parts.parts:
        current = current / part
        if current.is_symlink():
            raise ValueError("Symlinks are not accepted: " + relative)
    target.resolve().relative_to(ROOT)
    return target

def digest(path):
    h = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        while True:
            block = stream.read(CHUNK)
            if not block:
                break
            h.update(block)
            size += len(block)
    return size, h.hexdigest()

def matches(path, size, sha):
    return path.is_file() and digest(path) == (size, sha)

def validate_manifest(data):
    if data.get("version") != 1 or not isinstance(data.get("assets"), list):
        raise ValueError("Unsupported manifest")
    entries = data["assets"]
    if len(entries) != 3 or {e["destination"] for e in entries} != EXPECTED:
        raise ValueError("Unexpected model destinations")
    for entry in entries:
        safe_path(entry["destination"])
        size, sha = entry["raw_bytes"], entry["raw_sha256"]
        if not isinstance(size, int) or not 0 < size < 100_000_000:
            raise ValueError("Invalid raw size")
        if not isinstance(sha, str) or len(sha) != 64 or any(c not in "0123456789abcdef" for c in sha):
            raise ValueError("Invalid raw checksum")
        # Current format deliberately supports one deterministic gzip per model.
        parts = entry["parts"]
        expected = "assets/compressed/" + Path(entry["destination"]).name + ".gz"
        if len(parts) != 1 or parts[0]["path"] != expected:
            raise ValueError("Unexpected compressed path")
        part = parts[0]
        safe_path(part["path"])
        if not isinstance(part["bytes"], int) or not 0 < part["bytes"] < 12_000_000:
            raise ValueError("Invalid compressed size")
        if not isinstance(part["sha256"], str) or len(part["sha256"]) != 64 or any(c not in "0123456789abcdef" for c in part["sha256"]):
            raise ValueError("Invalid compressed checksum")
    return entries

def restore(entry):
    target = safe_path(entry["destination"])
    size, sha = entry["raw_bytes"], entry["raw_sha256"]
    if target.exists():
        if matches(target, size, sha):
            print("OK (already restored): " + entry["destination"])
            return
        raise ValueError("Refusing to overwrite modified asset: " + entry["destination"])
    part = entry["parts"][0]
    source = safe_path(part["path"])
    if not matches(source, part["bytes"], part["sha256"]):
        raise ValueError("Compressed size/checksum mismatch: " + part["path"])
    fd, temporary_name = tempfile.mkstemp(prefix="." + target.name + ".", suffix=".tmp", dir=target.parent)
    temporary = Path(temporary_name)
    try:
        h = hashlib.sha256()
        written = 0
        with os.fdopen(fd, "wb") as output:
            with gzip.open(source, "rb") as stream:
                while True:
                    block = stream.read(CHUNK)
                    if not block:
                        break
                    written += len(block)
                    if written > size:
                        raise ValueError("Decompressed asset exceeds expected size")
                    h.update(block)
                    output.write(block)
            output.flush()
            os.fsync(output.fileno())
        if (written, h.hexdigest()) != (size, sha):
            raise ValueError("Restored size/checksum mismatch: " + entry["destination"])
        # Atomic no-clobber install: hard-link only a complete verified file.
        # Supported on NTFS and standard Linux/macOS filesystems. Fail closed
        # if the filesystem cannot create hard links; never overwrite a file.
        try:
            os.link(temporary, target)
        except FileExistsError:
            if not matches(target, size, sha):
                raise ValueError("Asset changed during restore; refusing overwrite")
        print("Restored: " + entry["destination"])
    finally:
        temporary.unlink(missing_ok=True)

def main():
    entries = validate_manifest(json.loads(MANIFEST.read_text(encoding="utf-8")))
    # Preflight all existing assets and compressed inputs before writing.
    for entry in entries:
        target = safe_path(entry["destination"])
        if target.exists():
            if not matches(target, entry["raw_bytes"], entry["raw_sha256"]):
                raise ValueError("Refusing to overwrite modified asset: " + entry["destination"])
        else:
            part = entry["parts"][0]
            if not matches(safe_path(part["path"]), part["bytes"], part["sha256"]):
                raise ValueError("Compressed size/checksum mismatch: " + part["path"])
    for entry in entries:
        restore(entry)

if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, EOFError) as error:
        print("Asset restore failed: " + str(error), file=sys.stderr)
        sys.exit(1)
