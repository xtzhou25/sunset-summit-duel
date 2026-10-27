# Reproduce the smaller Windows runtime

Before importing/exporting the game from a fresh clone, run `py -3 scripts/restore_assets.py` (Windows) or `python3 scripts/restore_assets.py` (Linux/macOS) from the repository root. This losslessly restores three models; engine compilation alone does not require game assets.

The game project/PCK is unchanged from the accompanying desktop source. Build the engine runtime separately; do not alter gameplay assets.

1. Download the canonical official Godot4.6.3-stable source tarball and verify the exact archive SHA256 in BUILD-PROVENANCE.json. The official release article identifies source commit35e80b3a8822a9df9be390814b62f44c0a9c69e8.
2. Use the recorded LLVM-MinGW20261020 UCRT toolchain (Clang23.1.4) and SCons4.11.1. Verify the toolchain publisher checksum recorded in provenance. Add its bin directory to PATH; do not replace system compilers.
3. From extracted Godot source, run:

```sh
python3 -m SCons -j4 platform=windows target=template_release arch=x86_64 \
  use_mingw=yes use_llvm=yes optimize=size_extra lto=none debug_symbols=no \
  vulkan=no d3d12=no opengl3=yes disable_xr=yes
```

4. Copy bin/godot.windows.template_release.x86_64.llvm.exe into a NEW portable folder as SunsetSummitDuel.exe. Copy the existing SunsetSummitDuel.pck without alteration. Do not overwrite the baseline release.
5. Include Godot LICENSE.txt/COPYRIGHT.txt and compiler/static runtime notices from the toolchain LICENSE.TXT and x86_64-w64-mingw32/share/mingw32/COPYING* files, plus all existing game/font/audio/motion attribution.
6. Validate PE architecture/imports, hashes, resource compatibility and actual Windows runtime before claiming Windows acceptance. Exact compiler paths/timestamps can make rebuilt EXE hashes differ; use the recorded artifact hash for this delivered binary.

No custom source patch, removed model/audio resource, UPX packing, LTO assumption, or dynamic CRT DLL shipment is required. The zip is standard Deflate, compatible with Windows extraction; it is not a7z archive despite the packager used.
