# 固定摇杆：页面旋转输入桥只读审计

结论：不需要给 Godot 摇杆额外做90度旋转。现有桥已把浏览器 client 坐标转换到 Godot 的逻辑画布坐标；HUD 继续用 InputEventScreenTouch/Drag.position 和 Control.get_global_rect()，再次旋转会造成方向错误。未发现本次摇杆需求必须修改的输入桥漏洞。

## 路径与所有权
1. 页面内横屏在竖屏设备上给 shell 顺时针旋转90°。canvas.width/height取未变换的frame.client尺寸，而不是旋转后的矩形宽高；DPR不会再乘一次。
2. fullscreen.js 的 LivehouseCanvasInput.position 使用实际 canvas矩形逆变换：逻辑x=(clientY−rect.top)×canvas.width/rect.height；逻辑y=(rect.right−clientX)×canvas.height/rect.width。正常/物理横屏返回null，使用原Godot变换。工具栏、安全区和visualViewport偏移已包含在矩形中，不重复加偏移。
3. patch_rotated_input.py 精确替换Godot导出函数。touch start/move/end均调用同一position函数，保留changedTouches里真实identifier，不按数组序号重编号。鼠标绝对与相对运动均对应同一逻辑坐标系。
4. 变换不裁剪越界坐标，因此固定摇杆已经捕获的手指拖出底座时，仍可由HUD按相同ID处理并限制摇杆杆头幅度；不应在JS层把它改为新手指或攻击按钮。
5. 旋转/尺寸/viewport偏移变化前，shell调用cancelInput。hook逐个释放持有的触点、鼠标键、键盘键，并用屏幕外坐标避免菜单点击。旧触点后续move/end被抑制，新的touchstart允许重新使用同一ID。
6. 浏览器touchcancel映射为对应ID的一次屏幕外release；Godot原生导出没有独立canceled标记，所以HUD仍应根据release清空摇杆所有权，不依赖canceled=true才复位。当前_end_touch的direction路径符合这一要求。

## 实际执行的测试
- web-ui/page_landscape.test.cjs：30个控制器/坐标用例通过。涵盖页面进入退出、90°角点/中心、相对运动、visualViewport偏移、工具栏变化、DPR2/3、窗口旋转、系统全屏降级、失焦/隐藏清输入等。
- tests/rotated_input_test.cjs：15个精确导出hook用例通过。包含非连续ID91/4、changedTouches重排、拖出画布、不裁剪、touchcancel、双指及鼠标取消、旧序列抑制、新ID不受影响、键盘释放、补丁幂等与未知引擎拒绝。
- 新 tests/joystick_rotated_bridge_test.cjs：124断言通过。组合实际生产adapter与导出hook代码，在390×844、375×667、844×390、568×320四尺寸、DPR3与非零viewport偏移下，跟踪摇杆中心→右→右上→左上→越界→回中；第二攻击手指保留独立ID；模式切换释放两触点一次且抑制尾部；ID重用和原生cancel正确。

联合测试用两个既有测试工厂表达同一画布，并只桥接canvas身份；生产坐标算法未复制替换。它不是浏览器DOM或真实触屏测试，更不证明iPhone/WebGL游玩通过。当前已恢复的导出JS通过精确补丁检查；最终重新导出后应再次执行rotated_input_test.cjs。

## 未修改内容与回归注意
本审计只新增联合测试、日志、哈希证据与本文，没有改产品JS、CSS、补丁、HUD或战斗AI。

旧 tests/browser_directional_fixture_test.cjs 曾固定断言九宫格的0.38/0.62阈值及旧注释，属于旧方向盘mock契约；摇杆实现负责人应按新死区/固定中心/单触点所有权语义更新它，而不是用旧mock验证新摇杆。此项已向集成负责人报告。

证据：exports/qa-joystick-input/，其中INPUT-BRIDGE-VERIFICATION.json记录当前测试与产品桥文件哈希。日志结论仅为Node合成事件/输入桥验证，无真机认证。
