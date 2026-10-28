#!/usr/bin/env python3
"""把网页版发布到 https://mirugumi.space/minigame/。

构建和上传都在构建机上完成（那里有 Godot 4.6.3、导出模板和配置好的 coscmd）。
本脚本只负责把有改动的源文件同步过去，再调用 scripts/release_web.sh。

    py -3 scripts/release_web.py --dry-run   # 只看会同步哪些文件
    py -3 scripts/release_web.py             # 同步 + 构建 + 发布 + 校验

SSH 密码只从环境变量 SSH_PASSWORD 读取（或用 --key 指定私钥），仓库里不保存任何密钥。
"""
from __future__ import annotations

import argparse
import os
import posixpath
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REMOTE_ROOT = "/home/admin/build/sunset-summit-duel"
SKIP_DIRS = ("deploy/", "dist/", "exports/", ".godot/", "node_modules/")
SITE_URL = "https://mirugumi.space/minigame/"


def changed_files() -> list[str]:
    """列出和构建机不一致的文件：未提交的改动 + 新增文件。

    用 git 判断而不是时间戳，构建机与本地的提交一致时同步量最小。
    """
    def git(*args: str) -> str:
        r = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True,
                           text=True, encoding="utf-8")
        if r.returncode != 0:
            raise SystemExit("git %s 执行失败: %s" % (" ".join(args), r.stderr.strip()))
        return r.stdout

    names = set(git("diff", "--name-only", "HEAD").splitlines())
    names |= set(git("ls-files", "--others", "--exclude-standard").splitlines())
    names = {n.strip() for n in names if n.strip()}
    return sorted(n for n in names if not n.startswith(SKIP_DIRS))


def needs_upload(sftp, rel: str, local: Path) -> bool:
    remote = posixpath.join(REMOTE_ROOT, rel)
    try:
        st = sftp.stat(remote)
    except IOError:
        return True
    return st.st_size != local.stat().st_size


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default=os.environ.get("RELEASE_HOST", ""), help="构建机地址，也可用环境变量 RELEASE_HOST")
    ap.add_argument("--user", default="admin")
    ap.add_argument("--key", default=None, help="用私钥代替 SSH_PASSWORD")
    ap.add_argument("--skip-build", action="store_true", help="复用构建机上已有的 dist/")
    ap.add_argument("--dry-run", action="store_true", help="只列出会同步的文件，不做任何改动")
    args = ap.parse_args()

    try:
        import paramiko
    except ImportError:
        raise SystemExit("pip install paramiko")

    if not args.host and not args.dry_run:
        raise SystemExit("请用 --host <ip> 或环境变量 RELEASE_HOST 指定构建机")
    password = os.environ.get("SSH_PASSWORD")
    if not args.dry_run and not password and not args.key:
        raise SystemExit("请设置 SSH_PASSWORD，或用 --key 指定私钥")

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(args.host, username=args.user, password=password, key_filename=args.key,
                   timeout=30, banner_timeout=60)

    changed = []
    with client.open_sftp() as sftp:
        for rel in changed_files():
            local = ROOT / rel
            if local.is_file() and needs_upload(sftp, rel, local):
                changed.append(rel)
        print("[同步] %d/%d 个文件与构建机不同" % (len(changed), len(changed_files())))
        for rel in changed:
            print("   ", rel)
        if args.dry_run:
            client.close()
            return
        for rel in changed:
            local = ROOT / rel
            remote = posixpath.join(REMOTE_ROOT, rel)
            parent = posixpath.dirname(remote)
            try:
                sftp.stat(parent)
            except IOError:
                sftp.mkdir(parent)
            sftp.put(str(local), remote)

    print("[构建] 在构建机上执行 scripts/release_web.sh")
    env = "SKIP_BUILD=1 " if args.skip_build else ""
    cmd = "cd %s && %sbash scripts/release_web.sh" % (REMOTE_ROOT, env)
    stdin, stdout, stderr = client.exec_command(cmd, timeout=3600)
    revision = ""
    for line in stdout:
        sys.stdout.write(line)
        if line.startswith("REVISION="):
            revision = line.strip().split("=", 1)[1]
    err = stderr.read().decode("utf-8", "replace")
    code = stdout.channel.recv_exit_status()
    client.close()
    if code != 0:
        sys.stderr.write(err[-2000:])
        raise SystemExit("构建机发布失败 (%d)" % code)

    if revision:
        print("[校验] 等待线上切到 %s" % revision)
        for _ in range(6):
            req = urllib.request.Request(SITE_URL, headers={"Cache-Control": "no-cache"})
            body = urllib.request.urlopen(req, timeout=30).read().decode("utf-8", "replace")
            if revision in body:
                print("    已生效:", SITE_URL, "revision", revision)
                return
            time.sleep(5)
        print("    警告：线上页面还没有引用 %s（CDN 缓存？）" % revision)


if __name__ == "__main__":
    main()
