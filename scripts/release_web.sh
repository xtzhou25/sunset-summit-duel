#!/usr/bin/env bash
# 在装有 Godot 4.6.3 的构建机上导出网页版，并发布到 nginx 反代 /minigame/ 的 COS 桶。
#
#   bash scripts/release_web.sh              # 构建 + 组装 + 上传
#   SKIP_BUILD=1 bash scripts/release_web.sh # 复用已有 dist/
#
# 依赖：Godot 4.6.3 + 导出模板（XDG_DATA_HOME）、python3，
#       以及配好 minigame 桶的 coscmd（COS_CONF，默认 ~/.cos-minigame.conf）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-/home/admin/build/tools/Godot_v4.6.3-stable_linux.x86_64}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-/home/admin/build/xdg/data}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/home/admin/build/xdg/config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/home/admin/build/xdg/cache}"
export PYTHONUTF8=1
COSCONF="${COS_CONF:-$HOME/.cos-minigame.conf}"
BASE_URL="https://mirugumi-space-1382800327.cos.ap-guangzhou.myqcloud.com/minigame/"

cd "$ROOT"

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "[1/4] 还原模型并导入资源"
  python3 scripts/restore_assets.py >/dev/null
  "$GODOT" --headless --path . --import >/dev/null 2>&1
  echo "[2/4] 导出网页版"
  mkdir -p exports/web
  "$GODOT" --headless --path . --export-release "Web" exports/web/index.html >/dev/null
  echo "[3/4] 打包成静态站点"
  python3 scripts/pack_web.py
else
  echo "[1-3/4] 跳过构建，复用 dist/"
fi

echo "[4/4] 组装 deploy/ 并上传"
REV=$(python3 - "$BASE_URL" <<'PY'
import hashlib, pathlib, re, shutil, sys

base = sys.argv[1]
root = pathlib.Path(".")
dist = root / "dist"
deploy = root / "deploy" / "minigame"

# 用 dist/ 的内容哈希做版本目录名，内容不变则目录名不变
digest = hashlib.sha256()
files = sorted(p for p in dist.rglob("*") if p.is_file() and p.name != "rev.txt")
for p in files:
    digest.update(p.relative_to(dist).as_posix().encode())
    digest.update(hashlib.sha256(p.read_bytes()).hexdigest().encode())
rev = digest.hexdigest()[:12]

out = deploy / rev
if out.exists():
    shutil.rmtree(out)
out.mkdir(parents=True)
for p in files:
    shutil.copy2(p, out / p.name)

# 入口页加 <base>，让相对路径都指向版本目录
html = (dist / "index.html").read_text(encoding="utf-8")
if "<base " in html:
    raise SystemExit("index.html 里已经有 <base> 标签")
html = re.sub(r"(<head[^>]*>)", lambda m: m.group(1) + '\n<base href="%s%s/">' % (base, rev), html, count=1)
(deploy / "index.html").write_text(html, encoding="utf-8", newline="\n")
(root / "deploy" / "VERSION").write_text(rev + "\n", encoding="utf-8", newline="\n")
print(rev)
PY
)

echo "    版本 $REV"
# 先传版本目录，最后传入口页，避免用户切到一半白屏
for f in deploy/minigame/"$REV"/*; do
  coscmd -c "$COSCONF" upload -f "$f" "/minigame/$REV/$(basename "$f")" >/dev/null
done
coscmd -c "$COSCONF" upload -f deploy/minigame/index.html /minigame/index.html >/dev/null
echo "    资源已上传，入口页已更新"
echo "REVISION=$REV"
