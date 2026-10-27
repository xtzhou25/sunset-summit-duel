# 页面内横屏修订 v5.1

目标：不依赖 iPhone 的系统全屏或方向锁定，提供用户主动进入、随时退出的页面内横向排版。保留已发布功能 v5 的 PCK、59 动作、规则和五个动作按钮。

## 实施与验收

1. 从已验证 RC5 恢复源文件与十个网站文件，逐项 SHA256 和 ZIP CRC 验证。
2. 分离“页面内横屏”和“系统全屏”。竖屏时整套游戏画布和 HUD 顺时针旋转 90°，逻辑布局交换宽高；设备本身横屏时不二次旋转。
3. 使用可见 viewport 的尺寸及偏移，处理地址栏、safe-area 和窗口变化。始终保留可点击退出按钮。页面旋转不是系统方向锁定，也不能隐藏 Safari 地址栏。
4. 针对实际 Godot 4.6.3 Web 输入函数作精确、可重复补丁：client 坐标只逆变换一次，鼠标相对移动也旋转；取消活动触点不误触菜单，不遗留方向和连按。
5. 普通云浏览器中的真实指针探针验证 CSS 旋转坐标；自动化用例独立标注模拟多触点。真实 Godot HUD 验证五动作、方向、暂停、重开和选择界面。
6. 保留 WebGL 2 与真机限制：无法运行的浏览器项目不冒称通过，真实 iPhone Safari 需用户试玩确认。
7. 冻结完整源文件、原 PCK、Web 与 QA 到新候选，持久保存及实际下载校验，等待批准后才发布。

## 官方依据

- Godot 4.6 Web input source: https://github.com/godotengine/godot/blob/4.6/platform/web/js/libs/library_godot_input.js
- Canvas client rect is viewport-relative: https://developer.mozilla.org/en-US/docs/Web/API/Element/getBoundingClientRect
- Visible viewport and resize/scroll: https://developer.mozilla.org/en-US/docs/Web/API/VisualViewport
- WebKit safe areas and viewport-fit: https://webkit.org/blog/7929/designing-websites-for-iphone-x/

此轮不更改角色动作、攻击判定、音频策略、网站权限或其他网站。
