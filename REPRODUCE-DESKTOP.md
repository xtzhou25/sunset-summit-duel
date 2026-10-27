# Reproduce the Windows x86_64 build

**Fresh-clone prerequisite:** restore the three losslessly compressed models before any Godot import, run, test, or desktop/Web export. From the repository root, run `py -3 scripts/restore_assets.py` on Windows or `python3 scripts/restore_assets.py` on Linux/macOS. Requires Python 3.8+, no packages or network. Verified existing models are skipped; modified models are never overwritten. See README.md for checksum and filesystem requirements.

Baseline: functional18 / RC19 / expected Sites20, candidate source commit `b959271430231e7b2b33d87324e42e67605bdd78`.
Original RC19 ZIP SHA256: `2fec7b7160f5504e76ab3d8f1bd5bc4ac7fb8f785d5715b88d3a9c353dcc91ed`.

1. Install official Godot **4.6.3 stable standard** and its matching standard export templates from https://godotengine.org/download/archive/4.6.3-stable/ . Do not upgrade the engine for exact reproduction.
2. Open `project.godot` once to import assets, or run:
   `godot --headless --editor --path . --import`
3. Create `exports/windows`, then run:
   `godot --headless --path . --export-release "Windows Desktop" exports/windows/SunsetSummitDuel.exe`
4. Keep the generated EXE and PCK side by side. Copy the supplied README, licenses, and engine notices when redistributing.
5. To regenerate engine notices:
   `godot --headless --path . --script tests/desktop_engine_licenses.gd`
6. Test desktop input/layout:
   `godot --headless --path . --script tests/desktop_ui_test.gd`
7. Packed resources/20 ordered pairs/audio smoke (use absolute paths):
   `godot --headless --main-pack /absolute/path/exports/windows/SunsetSummitDuel.pck --script /absolute/path/tests/random_audio_pack_smoke.gd`

For sandboxed Linux, use writable XDG_CACHE_HOME, XDG_CONFIG_HOME, and XDG_DATA_HOME; install templates beneath `$XDG_DATA_HOME/godot/export_templates/4.6.3.stable/`. Windows normally installs templates through the Godot editor.

Official template archive SHA512:
`da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68`
Verified against https://github.com/godotengine/godot-builds/releases/download/4.6.3-stable/SHA512-SUMS.txt .

Changes limited to desktop-only main/hud adaptation, initial window size and a separate Windows export preset; combat, AI, audio, models, motion, and stage source unchanged. The retained Web preset is historical source compatibility, not a web deployment. No online publication was performed. Generated caches, official template binaries, and old web runtime are deliberately excluded from source archive. See BUILD-REPORT.md for test scope and limitations.
