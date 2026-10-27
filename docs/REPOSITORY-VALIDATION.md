# 公开仓库准备验证 · 2026-10-27

## 来源与整理

输入归档 Sunset-Summit-Duel-Desktop-Source.zip，37,365,729 字节。
SHA256：64c567c702c7b62b742f4823ba8cf8b0e4d18c1c3f76d31b0e3fa0e591138988。

逐文件比较确认保留的游戏资源、运行时 GDScript、场景与导出配置与输入归档一致。仅调整 README、文档私人归档标识、工具链本地路径，以及三个历史录制脚本和一个历史 soak 测试的机器路径。依赖未附历史 checkout 的旧成对录制脚本予以排除。

排除原始日志、私人回读证明、内部完整性清单和 Word 计划；不包含缓存、导出产物、引擎/编译器或源 ZIP。原交付归档未修改。保留来源和第三方许可，不新增原创内容的开源许可。

## 本次重新执行

Linux，Godot 4.6.3.stable.official.7d41c59c4，headless；Node.js 执行纯 JavaScript mock 测试。以下全部退出 0：

| 检查 | 结果 |
| --- | --- |
| 全量资源导入 | 成功 |
| combat_test.gd | 0 failures |
| desktop_ui_test.gd | 36 checks，0 failures |
| random_opponent_test.gd | 202,072 checks，0 failures |
| desktop_qi_combat_test.gd | 513 checks，0 failures |
| desktop_tao_combat_test.gd | 711,040 checks，0 failures；48 pair stress rounds，重复一致 |
| fullscreen_ui_test.cjs | 30 passed，0 failed |
| browser_directional_fixture_test.cjs | 9 mock tests passed |

BUILD-REPORT.md 是历史交付验证，不表示其中所有测试本次重跑。

## 公开前审计

对候选文件（含二进制字节）扫描常见 GitHub/OpenAI/AWS token、Bearer token、私钥头、私人归档标识和用户/工作区绝对路径；未发现匹配。没有符号链接，没有 100 MB 以上文件。该扫描不能证明所有形式的秘密绝不存在。

保留 Godot、字体、音频、动作和可选工具链许可。第三方来源页面、原始 BVH 与许可证保留原始字节及上游空白格式；不因 git whitespace 提示重写来源证据。公开展示不会自动改变原创内容许可。

## 边界

未重新导出 Windows/Web 包，未在 Windows 真机运行，未做可听音质或真实手机/浏览器实战验收。JavaScript mock 不代表浏览器认证。本文不表示远程创建或推送已成功。

## 经批准的无损模型传输适配

因上传通道单请求大小限制，ha/qi/tao 三个模型改以确定性 gzip 进入 Git；原始 GLB 在本地由 scripts/restore_assets.py 还原并忽略，不改场景/导出引用路径。不降低精度、不重新编码模型、不改变画质。assets/compressed/manifest.json 记录每个压缩文件及原始文件的大小和 SHA256，.gdignore 防止 Godot 导入压缩副本。

重新验证：临时干净工程还原、从其他 cwd 调用、重复调用跳过、修改目标拒绝覆盖、损坏 gzip 拒绝、路径穿越拒绝、临时文件清理均通过。完整还原结果匹配原始模型 SHA256；本地重新导入和桌面 UI 的 36 项检查退出 0。Windows Python/NTFS 未真机实测；不支持硬链接的文件系统会安全失败。
