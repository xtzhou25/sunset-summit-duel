# 决战日不落之巅

Godot 4.6.3 制作的 2.5D 单人格斗小游戏。因、鱼、七、桃、哈在地下 livehouse 舞台切磋；当前基于 **功能 v18 / RC19**，包含五角色、随机/手动对手、专属技与音效、28 位观众和三层滚动舞台，并加入桌面键盘、全屏及隐藏触摸 HUD 的适配。

## 本地运行

**首次克隆必须先还原三个模型，再打开 Godot。** 安装 Python 3.8 或更新版本，在仓库根目录运行：

Windows：
```powershell
py -3 scripts/restore_assets.py
```

Linux / macOS：
```sh
python3 scripts/restore_assets.py
```

三个大模型以确定性 gzip **无损压缩**保存在 `assets/compressed/`；脚本恢复 `assets/ha.glb`、`assets/qi.glb`、`assets/tao.glb`，模型字节、画质和渲染不变。无需额外 Python 包或联网。压缩文件与还原文件均校验 SHA256/大小；正确还原的模型直接跳过，修改过的模型拒绝覆盖。请先备份或移开自己的修改，勿删除未备份内容。

安装采用临时文件加原子、不覆盖的硬链接，适用于 NTFS 和常规 Linux/macOS 文件系统；不支持硬链接的盘会安全报错，请将工程放在支持的本地磁盘。可通过脚本绝对路径从其他目录调用。

**桌面/Web 的所有导入、运行、测试及导出前均需完成还原。** 三个还原后的 GLB 被 Git 忽略；工程和导出引用路径不变。仅构建 Godot 引擎本身时不需要游戏资源。可运行 `python3 tests/restore_assets_test.py` 检查还原流程（Windows 使用 `py -3`）。

安装 **Godot 4.6.3 stable 标准版（非 .NET）**，导入根目录的 `project.godot`，等待资源导入后按 F5。也可在仓库根目录运行：

```sh
godot --headless --editor --path . --import
godot --path .
```

使用 Compatibility 渲染器。桌面默认 1280×800，最小 960×600。

## 操作

| 按键 | 动作 |
| --- | --- |
| A/D、左右方向键 | 移动；地面向后移动防御正面攻击 |
| W、上方向键、空格 | 跳跃 |
| S、下方向键 | 下蹲 |
| J / K / L / I | 刺拳与连拳 / 飞踢 / 重拳 / 回旋踢 |
| O | 专属技 |
| Esc | 暂停 / 继续 |
| F11、Alt+Enter | 桌面全屏 / 窗口切换 |

鼠标选择角色和设置；默认随机抽取其他四位之一。每局 60 秒、三局两胜。桌面版隐藏手机触摸区；Web 使用虚拟摇杆和攻击按钮。

## 导出及平台差异

安装与编辑器版本一致的官方导出模板后：

```sh
mkdir -p exports/windows
godot --headless --path . --export-release "Windows Desktop" exports/windows/SunsetSummitDuel.exe
```

EXE 与 PCK 须放在一起；分发时保留第三方许可。完整步骤见 [REPRODUCE-DESKTOP.md](REPRODUCE-DESKTOP.md)。

保留 Web 预设、页面旋转/全屏组件和历史打包脚本，但**不包含已导出的 Web 引擎、WASM 或站点产物**。Web 需要 WebGL 2，并通过 localhost 或 HTTPS 提供，不能以 file:// 直接启动。部分历史打包/回归脚本依赖上一版导出目录，不保证单条命令精确重建历史线上站点。本次仓库发布不改动或部署线上游戏网页。

### 可选精简 Windows 引擎

[runtime-optimization/RUNTIME-REPRODUCE.md](runtime-optimization/RUNTIME-REPRODUCE.md) 记录独立构建命令、工具链、校验值与许可。基于官方 Godot 4.6.3 源码提交 `35e80b3a8822a9df9be390814b62f44c0a9c69e8`，禁用 Vulkan、D3D12、XR，保留 OpenGL3；游戏模型、音频和玩法资源不删减。须另行取得源码、LLVM-MinGW 和 SCons；仓库不附引擎或编译器二进制。

官方预编译模板与源码标签存在已记录的提交元数据差异，见该目录的 BUILD-PROVENANCE.json。**Windows 真机运行未验收**；Linux/headless 检查不等于 Windows 显卡、全屏、性能或音质保证。

## 测试

先导入资源，再运行当前五角色/桌面用例：

```sh
mkdir -p exports/qa-random-audio
godot --headless --path . --script tests/combat_test.gd
godot --headless --path . --script tests/desktop_ui_test.gd
godot --headless --path . --script tests/random_opponent_test.gd
godot --headless --path . --script tests/desktop_qi_combat_test.gd
godot --headless --path . --script tests/desktop_tao_combat_test.gd
node tests/fullscreen_ui_test.cjs
node tests/browser_directional_fixture_test.cjs
```

历史测试部分针对旧角色数、旧手机布局或外部导出文件，不代表全部适用于当前版本。历史验证见 [BUILD-REPORT.md](BUILD-REPORT.md)，本次重建检查见 [docs/REPOSITORY-VALIDATION.md](docs/REPOSITORY-VALIDATION.md)。Web mock 测试不替代真实浏览器实战。

## 目录与来源

- `scripts/`、`main.tscn`：玩法、AI、输入、HUD、摄像机。
- `assets/`、`stage-art/`：运行时模型、字体、音效、舞台与动画。
- `tests/`、`web-ui/`：测试、采样工具及 Web 页面组件。
- `docs/`：来源、许可、玩法契约与历史验证。
- `runtime-optimization/`：精简引擎构建配置、溯源与许可。

输入归档：`Sunset-Summit-Duel-Desktop-Source.zip`。
SHA256：`64c567c702c7b62b742f4823ba8cf8b0e4d18c1c3f76d31b0e3fa0e591138988`。

游戏运行时代码和资源保留原字节。仓库整理只改文档、忽略规则及少量旧测试/录制工具的机器路径，并移除日志、私人归档标识和内部回读记录；原始交付归档未修改。历史功能见 [docs/HISTORY.md](docs/HISTORY.md)。角色原始建模/绑定源工程不在本运行时仓库内，保留的是可运行 GLB 和来源说明。

## 单机 / 局域网模式

启动后先在入口选择「单机模式」或「局域网模式」。单机模式进入原有选角与 AI 对战；局域网模式先填写自己的昵称，再进入大厅。

房主创建房间后，同网段其他机器会自动发现房间列表，列表以房主昵称和房间名区分；选择房间即可加入。双方在选角界面各选一名不同角色后自动开赛。IP 只作为底层连接地址，大厅日常使用昵称识别。

- 局域网为**直连**：客机直接连接房主的 ENet 端口，房主本机负责权威战斗模拟，不经过任何外部服务器或转发。
- 默认端口：战斗 `UDP 7777`，房间自动发现广播 `UDP 7778`。若系统防火墙询问，请允许该程序通过专用网络。
- 自动发现依赖 UDP 广播；跨网段、访客 Wi-Fi 或防火墙隔离时，可使用大厅下方的「直接加入」并填写房主局域网 IP。
- 公网联机可在此协议上继续扩展为专用服务器或中继，不在当前版本范围内。

## 许可与公开范围

本仓库按项目所有者要求**公开展示源码**；公开可见不等于另行授予原创代码、美术或其他原创内容的开源许可。本次没有新增整项目 LICENSE。第三方许可仅覆盖各自组件，不自动适用于整个游戏。

- Godot：`docs/GODOT-LICENSE.txt`、`GODOT-THIRD-PARTY-NOTICES.json`。
- 字体：`docs/FONT-LICENSE.txt`。
- 猫叫录音（CC0）：`docs/MEOW-AUDIO-LICENSE.txt`。
- Open Motion Project / ACCAD / The Ohio State University 动作（CC BY 3.0）：`docs/ANIMATION-ATTRIBUTION.txt`、`docs/OPEN-MOTION-LICENSE.txt`。
- 可选自编译引擎及工具链：`runtime-optimization/licenses/`。
