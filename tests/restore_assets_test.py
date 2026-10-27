"""Dependency-free restore integrity tests; never edits the working models."""
from pathlib import Path
import json
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary) / "project"
        (root / "scripts").mkdir(parents=True)
        shutil.copy2(ROOT / "scripts/restore_assets.py", root / "scripts/restore_assets.py")
        shutil.copytree(ROOT / "assets/compressed", root / "assets/compressed")
        command = [sys.executable, str(root / "scripts/restore_assets.py")]
        def run():
            return subprocess.run(command, cwd=temporary, capture_output=True, text=True)
        result = run()
        assert result.returncode == 0, result.stderr
        for name in ("ha", "qi", "tao"):
            assert (root / "assets" / (name + ".glb")).is_file()
        result = run()
        assert result.returncode == 0 and result.stdout.count("already restored") == 3
        target = root / "assets/ha.glb"
        target.write_bytes(b"modified-user-asset")
        assert run().returncode != 0
        assert target.read_bytes() == b"modified-user-asset"
        target.unlink()
        (root / "assets/compressed/ha.glb.gz").write_bytes(b"corrupt")
        assert run().returncode != 0 and not target.exists()
        manifest = root / "assets/compressed/manifest.json"
        data = json.loads(manifest.read_text())
        data["assets"][0]["destination"] = "../escape.glb"
        manifest.write_text(json.dumps(data))
        assert run().returncode != 0
        assert not (root.parent / "escape.glb").exists()
        assert not list((root / "assets").glob(".*.tmp"))
    print("PASS: pristine restore, unrelated cwd, idempotence, modified target refusal, corrupted gzip refusal, traversal refusal, temporary cleanup")

if __name__ == "__main__":
    main()
