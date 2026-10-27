#!/usr/bin/env bash
# Rebuild helper for Linux host. Download and verify inputs using BUILD-PROVENANCE.json first.
# Usage: bash Build-Optimized-Runtime.sh /path/to/godot-4.6.3-stable /path/to/llvm-mingw [jobs]
set -euo pipefail
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "Usage: $0 GODOT_SOURCE LLVM_MINGW_TOOLCHAIN [JOBS]" >&2
  exit 2
fi
SOURCE=$(realpath "$1")
TOOLCHAIN=$(realpath "$2")
JOBS=${3:-4}
test -f "$SOURCE/SConstruct"
test -x "$TOOLCHAIN/bin/x86_64-w64-mingw32-clang++"
python3 - "$SOURCE/version.py" <<'PY'
import runpy, sys
v=runpy.run_path(sys.argv[1])
assert (v['major'],v['minor'],v['patch'],v['status']) == (4,6,3,'stable'), 'Expected official Godot4.6.3-stable source'
PY
export PATH="$TOOLCHAIN/bin:$PATH"
cd "$SOURCE"
python3 -m SCons -j"$JOBS" platform=windows target=template_release arch=x86_64 \
 use_mingw=yes use_llvm=yes optimize=size_extra lto=none debug_symbols=no \
 vulkan=no d3d12=no opengl3=yes disable_xr=yes
printf '\nBuilt runtime: %s/bin/godot.windows.template_release.x86_64.llvm.exe\n' "$SOURCE"
printf 'Copy to a NEW portable folder as SunsetSummitDuel.exe; keep the original game PCK unchanged.\n'
