# 决战日不落之巅

因、鱼、七、桃、哈在地下 livehouse 舞台友好切磋的独立 2.5D 单人格斗小游戏。横屏优先，竖屏兼容。页面顶部“页面内横屏”会将整个游戏和输入区域横向排版，竖屏持机时顺时针旋转90度；物理横屏时不重复旋转，可随时退出。“系统全屏”是独立浏览器能力，不锁定系统方向，也不保证隐藏 Safari 地址栏。

## 游玩
选择角色后，A/D 或左右方向键移动，方向上/W/空格跳跃，方向下/S下蹲，J 前手刺拳，收招最后120毫秒内松开再按可接一记后手直拳，最多两段；K 飞踢，L 重拳，I 地面回旋踢，O 专属技，Esc 暂停。重拳有更长前摇和收招，按住拳击不会自动连打。手机底部为固定虚拟摇杆与五个攻击按钮（竖屏3+2、横屏一排），可同时按住方向和动作。站在地面向后移动会防住正面攻击，但防御槽会消耗，不能一直龟缩；空中不能防御。每局60秒，三局两胜，平局重赛。可暂停、静音、重开或切换角色。飞踢命中可击倒对手，倒地期间不能追打；起身后短暂保护，KO则保持倒地。

## 工程
使用 Godot 4.6.3 打开 project.godot。Web 导出预设已包含；导出后运行 python3 scripts/pack_web.py，dist/ 为静态部署目录。Web 需要支持 WebGL 2 的现代浏览器；详情见 docs/QA.md。dist/ 不能通过 file:// 直接启动，应使用 HTTPS 静态托管或 localhost 测试。

原角色建模/绑定源文件在独立动画源包中保留，本工程只含轻量运行时 GLB，不含旧城市玩法。来源和许可见 docs/ANIMATION-ATTRIBUTION.txt、docs/FONT-LICENSE.txt 和网页 CREDITS.txt。

## 专属远程技能（保留）
因按 O / 喵波，半蹲张臂，从真实嘴部发出可读的“喵”字与猫叫；鱼按 O / 爱心波，小跳头顶比心，从双手中心向前发出粉色实体爱心。两者冷却4秒，接受起手时开始，受击打断不退还。每弹伤害12，可以地面正面防御；空中不能格挡。爱心以发射瞬间的对手上身为方向快照，不追踪，太近可能越过。两弹互相穿过，不反射。

所有旧招式和59个基线动作保留；因67动作、鱼71动作（原动作全部保留，新增配对蹲起）。网页旋转与多指取消修复保持。完整 source/web/QA/许可冻结并回读后，须批准才发布。

## 已知限制
真实 Godot 原生录像和自动化输入/规则检查已完成；普通云浏览器仅完成页面旋转与真实指针/模拟触点测试，缺少 WebGL2，未验证浏览器实战性能或真实 iPhone/Safari 多指。猫叫来自明确 CC0 的真实猫录音，保留原始音高与速度，但本环境没有可用音频硬件，未作听觉验收。GIF 无声；P2 附原生引擎混音有声 MP4，未作真人听感保证。详见 docs/QA.md 和 docs/MEOW-AUDIO-LICENSE.txt。

## P1 · 功能 v7 空间与方向控制
手机方向盘上跳、下蹲、斜上斜跳，空中左右可平滑调整落点；松开下键起身，跳/攻击可立即取消蹲伏。按住上不自动连跳。正常跳跃更高、后退更快，重拳命中显著拉开而防住仅较小推移；原招式伤害、远程冷却不变。蹲伏不改变受击盒，不增加高低段体系或无敌。

P1 本身不改打击音效；后续 P2 已在此版本独立完成。参数前后、真实测试范围见 docs/P1-SPACING-CONTROLS.md。

## P2 · 功能 v8 打击反馈与角色身份
轻拳、直拳、重拳、踢击、格挡、破防、挥空、跳落和击倒各用真实事件触发分层原创音效。重拳命中停顿95毫秒、可关闭的100毫秒轻微横向镜头偏移，HUD不震；挥空不冒充命中。设置中可独立调整音效与角色声，主静音保留，首次开始/操作后才播放。音频固定10槽，暂停/后台不积压。因始终对应紫色，鱼始终对应黄色，选角与换边不改变身份。见 docs/P2-IMPACT-FEEDBACK.md。

## P3 · 功能 v9 攻防与 AI 节奏
AI 在中距离会短退、停步或接近；观察到换边后短暂重新判断。对已经发出的弹体使用延迟且不保证成功的防守/跳跃选择，不读取玩家按键。招式伤害、动作、CD和速度全部保持。固定种子脚本对比表明缠斗占比降低，但并非玩家平衡或真机性能认证。详见 docs/P3-RHYTHM-AUDIT.md。

## 七 · 功能 v10
三角色选择与独立对手切换；七的单发步枪技 O，正面可防御、冷却4秒。采用最终 v03 模型；已通过原生自动化接口/输入/边界验收，浏览器、iPhone、可听音质及游戏镜头目检仍有限制。准确接口、备份与验收边界见 docs/QI-INTEGRATION.md。

## 功能 v11 · 弹体反应可行性与原生画面验收
AI仍只读取延迟的公开状态：保留240毫秒反应延迟及原防御概率；对普通跳跃不可能跨过的高水平弹道，原躲弹跳跃分支改为短暂停顿，不改成必防。可行下降心形弹仍可能跳避。招式伤害、冷却、角色模型均不变。完整数值/原生渲染范围与真机/听感限制见 docs/AI-PROJECTILE-HEIGHT-GATE.md 和 docs/STABILIZATION-STAGE-ACCEPTANCE.md。

## 功能 v12 · 固定虚拟摇杆
左手按住圆形摇杆并拖动：左右移动，上推跳跃，下推下蹲，斜上斜跳；松手归中，持续上推不自动连跳。摇杆中心有死区、方向边界有迟滞；外观位移连续，但格斗移动速度不随推杆距离改变。右手五个攻击按钮及键盘保持原样，可与摇杆同时操作。页面内横屏沿用现有坐标桥，暂停、后台及切菜单清空触点。准确验收范围见 docs/JOYSTICK-RELEASE-ACCEPTANCE.md。

## 功能 v13 · 桃
新增第四位角色「桃」，桃色与白色，装饰云朵不属于人物且未制作翅膀。双手向前送出一颗带果缝、蒂和叶的三维桃子；1.10 秒动作，在 0.42 秒单次发射，4 秒冷却、12 点伤害，正面地面防御规则不变。四角色支持12种不同的有序对战组合。保留固定摇杆与旧三角色行为。

最终资产、实际骨骼发射点、独立规则/原生输入、有限镜头与180秒运行回归范围见 docs/TAO-INTEGRATION-QA.md。此版本不宣称真实手机/浏览器实战或音频听感验收；模型局部头发与上臂接触、旋转裙褶已记录，非全帧零穿模承诺。

## 哈：天降蛋糕
橙白角色，使用下半黑框、上缘无框眼镜。O/蛋糕召唤在起手时锁定对手当前地面位置，先显示橙色落点环，0.45秒后蛋糕从上方下落，不追踪。单次命中12伤害，冷却4秒；可以走开，地面向后防御同样有效，空中不能防御。前摇受击取消，已落下的蛋糕保持飞行；KO/重开/菜单全部清理。详见 docs/HA-INTEGRATION-QA.md。


## Functional v17 / RC18 — expanded livehouse
- World arena expands from ±2.1m to ±4.2m; original spawn ±1.3m and all move/attack stats preserved.
- A device-independent shared fight window gently tapers additional outward separation from5.2m to5.8m. Common translation, inward movement and jump height are untouched; camera never writes back to physics.
- Dual-target orthographic camera:0.20m deadzone,0.16s follow, maximum horizontal width8.2m; the existing short-landscape vertical jump/cake envelope remains a higher-priority minimum.
- Far/back/equipment+floor parallax compensation:0.25/0.12/0; stationary floor,28 batched below-stage fan silhouettes with muted character-color glowsticks.
- Existing saved shake preference now appears as「动态效果」: turning it off disables hit shake and decorative light/fan animation, not essential camera following. Pause/background/menu freeze decorative time.
- Fresh web PCK is built with`godot --headless --export-pack Web exports/web/index.pck`. `scripts/pack_stage_web.py VERIFIED_RC17_DIST` reuses the byte-verified unchanged Godot4.6.3 engine and production rotated-input bridge, updates only declared PCK size. Explicit export resources include fight_camera and both stage-art scripts.
- Native exact-size screenshots and camera tests cover portrait, ordinary/short landscape; real graphical600s/20pairs is the release gate. Native/synthetic checks do not certify browser/Safari/iPhone touch, hardware FPS, or audible output.

### P7 measured rendering optimization
The28fans now batch112 arm/glow line commands into4 colored multiline calls. Controlled1280×800 original/batched/original/batched native fixture showed ~27 fewer draw calls; the fixed-pose comparison was pixel-identical. FPS changes were mixed, so no consistent FPS uplift is claimed. Final600s stability evidence is separate from the earlier unoptimized600s and historical180s baseline.

### Release acceptance and post-round scope
Final optimized native graphical run:600.011s,12,697 rendered frames,35,962 physics frames,20ordered pairs/20native PNGs,20pause/20focus/20menu cycles,zero errors,identical starting/ending runtime hashes. This is software-rendered native stability evidence, not physical-device60FPS. Controlled A/B reduces draw calls; historical native performance comparisons remain contextual.
The5.8m shared window constrains active combat. Existing post-round KO settling retains its inertia: an explicit8-case far-distance cake-KO test reached5.99778m transiently.120actual-weighted-pose projection checks across desktop/portrait/short landscape passed with minimum12.998px margin; no clipping or additional post-round movement lock was introduced.

## 功能 v18 / RC19 · 随机对手和音效选择
默认从其他四位角色等概率抽取对手；新对局/随机模式再战重抽，同一场的局间不换。手动指定保留，玩家与指定对手冲突时回到随机。鱼/桃/哈有独立技能命中或过程声音，七单发声更短柔和；保留因喵声、现有静音和音量设置。来源与确切验收范围见 docs/RANDOM-OPPONENT-AUDIO-QA.md、docs/AUDIO-SELECTION-REFINEMENT.md。Dummy环境未作主观听感验收。
