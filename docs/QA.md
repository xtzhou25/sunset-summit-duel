# 决战日不落之巅 — release-candidate QA

## Verified
- Godot 4.6.3 Compatibility renderer, clean independent project, actual imported purple-white and yellow-white GLBs.
- Pure 60 Hz combat tests, 80 seeded full rounds, responsive HUD at six sizes, full game integration and two complete AI matches through best-of-three results/rematch. Logs are retained in qa/.
- Explicit startup/active/recovery windows, once-per-attack damage, guard drain/break, ground-only frontal defense, post-hit recovery protection, two-attack chain cap, walls and controlled aerial passing.
- Fixed arena X [-2.1, 2.1] in every orientation. Camera changes only for window layout, never tracks fighters or zooms during combat. Model scale is uniformly 1.2 in all orientations.
- Actual native captures at 1280×800, 844×390, 390×844 and 375×667 include attacks, guard, KO, edge jumps and menu. These are real Godot renders driven by repeatable QA inputs, not generated mockups.
- Twenty-one animations per character in v2. Original clips retained; BackstepGuard uses reversed original Walk lower-body channels and held Guard upper body. Retreat 0.66 m/s matches playback rather than sliding a static pose.
- Attack front reach calibrated to actual source-model mesh extents; separate horizontal hurtbox. Flying kick is a restrained low forward kick plus engine-driven airborne motion, not a high kick.
- Character colors use a simple soft-light shader to avoid burned-out white clothing. Stage uses simple geometry and bounded lights; no strobe or violent camera shake.
- Web export is single-threaded and statically packaged. Gzip WASM is decoded in the loader, checked for exact byte count and SHA256 before instantiation. All hosted files under 25 MB.

## LIMITED-QA, not verified
The ordinary cloud Chrome browser could open the local exported page but reports missing WebGL 2. No graphics-security flags or browser-security bypasses were used. Therefore browser combat performance, Safari/mobile GPU compatibility and real touchscreen ergonomics remain unverified. Native portrait viewports and injected touch tests are not physical iPhone/Android testing. Native audio hardware was unavailable, so synthesized effects and mute logic were checked in code but not audibly auditioned. A modern browser with WebGL 2, WebAssembly, DecompressionStream and HTTPS is required.

The release is a playable candidate, not a claim of universal device certification. Publication requires approval of the exact candidate. Existing Vesper site is unchanged.

## v2 regression
153 strict real-main-loop feedback assertions pass: both characters/facings, FightIdle versus menu Idle, HitReactStrong without movement override, punch/kick/block timing, silent misses, trade metadata, pause/background, rematch and KO. Original combat/edge/HUD/camera/integration and full-match tests retained. Native before/after GIF and reverse matchup captures demonstrate actual scene reactions. Animation worker checked new21-clip GLBs at120Hz with floor and tested garment/body checks. No graphics-security bypass or new browser/device certification is claimed.

## v3 bounded action revision
51 clips per character: original21 retained, plus15 paired _R/_L gameplay bases. Three-quarter upper-body presentation keeps actor roots, feet/strike plane and physical reach unchanged. Actual paired wrist active-path forward drift is at most .000075m versus the preserved original, and final landing/recovery endpoint comparisons pass.

309 real-main-loop presentation/state/geometry checks and153 feedback checks pass on the final Candidate3 asset hashes. Dedicated knockdown tests211, basiccombat8, edge42, touch/HUD110, integration11, 80 seeded rounds and full best-of-three AI match tests pass. Unblocked flying kicks trigger .80s down, .25s settled hold,1.00s rise and .35s wake protection; punch remains ordinary recoil unless lethal. Air loss holds at .20s until actual ground, KO holds down without rising. Pause/background, timeout during fall/rise, input rearm, rematch and first-ready-frame input are checked. Damage/range/attack cooldowns are unchanged.

Weighted actual-skin bounds pass desktop1280×800, landscape844×390, portrait390×844 and375×667, both walls/directions and airborne/down/hold/KO/recovery phases. Minimum margin is+21.6168px. Short brace support uses actual hand skin at.4667/.50s: purple minimum−.000936m (within2mm tolerance), yellow+.024m. Low-percentile heights and contact patch counts are reported descriptively, not claimed as full palm contact. Hands need not remain grounded in the settled kneel.

Animations are stylized and not collision-free. Brief localized under-cape/opening contacts and elbow-volume limitations remain; exact known locations are preserved in ANIMATION-V3-LIMITATIONS.txt. The externally visible yellow shoulder gap found in Candidate2 was fixed in Candidate3 by restoring the original cape drape and stabilizing auxiliary roll, without mesh changes. No independent finger articulation or realistic ragdoll is claimed.

Native long gameplay is recorded with normal input commands and the original AI, without teleporting fighters, replacing AI, changing HP or injecting combat states. Separate layout-fixture PNGs deliberately pose edge cases and are named accordingly. Captures use a fixed simulation timeline and are not browser or mobile performance benchmarks. Browser/mobile/audio LIMITED-QA above remains unchanged.

## Gameplay v4 candidate delta, 2026-10-25

- 57 imported clips per character, preserving all 51 accepted previous clips. Six new paired clips implement distinct lead Jab, rear Straight and authored-startup HeavyPunch. Exact runtime/source versions and SHA256 in ASSETS.json; all five animation Library records were actually downloaded and checked.
- Immediate J press starts Jab. A fresh second press in the final120ms recovery queues one Straight. Holding cannot auto-repeat. L is a separate ground-only heavy, with no new knockdown or combo extension. Pause/background/hurt/KO/rematch clears pending input without delaying the first new press.
- Actual imported hand meshes provide 10ms conservative min(R,L) active reach curves. Effective front is min(configured cap, measured extension+.04m), then the existing .26m hurtbox is added. Timing, reach and physics do not read animation playback, keeping deterministic combat.
- Checks: 474 punch variation; 8 basic; 42 edge; 211 knockdown; 429 strict real-main feedback; 16 actual AI; 153 old feedback; 311 presentation; 475 HUD/reduced-skin; 21 web-controller. 80 seeded full rounds now include heavy input; both characters complete actual-main best-of-three matches with fresh jab/straight/heavy input and clean rematch.
- Actual native20s gameplay recordings use normal input commands and original AI, with no HP/position/pose fixtures. Separate four-scenario animation demonstration is explicitly labelled a scripted wall-guard fixture, not a live match. Native visual review is not browser/mobile/audio certification.
- Fullscreen shell retains the published gesture-only API, rejection/unsupported/exit handling and honest manual-rotation fallback. v4 uses one render pixel per CSS pixel even on Retina to keep tested controls at actual CSS size. This trades supersampled sharpness for predictable touch targets and bounded GPU cost. The v3.1 minimum300px backing workaround is removed only in this new gameplay version.
- At actual568x267 gameplay canvas, six touch targets are48px tall, overlay cards fit and every tested jump/down/KO/recover skinned silhouette clears HUD/touch bounds by≥6.643px. At844x337 clearance≥14.337px. Extreme short displays necessarily show smaller characters. Portrait2x2 and desktop/landscape four-action rows remain separate from the arena.
- LIMITED-QA remains: no physical phone, browser gameplay, successful hardware orientation-lock or audible output certification. Local garment intersections remain disclosed; do not infer universally collision-free anatomy from selected checks.

## Gameplay v5 grounded roundhouse candidate

- Both characters now have59 imported clips: the accepted57 remain unchanged, with only paired RoundhouseKick_R/L appended. Definitive source/runtime Library version5 hashes are pinned in ASSETS.json and actual-readback proof is included.
- Dedicated I key and 回旋踢 touch action. Ground-only, single frontal sweep, no random flying-kick replacement, no full-circle AOE, no extra combo extension, no downed-target hits. Purple .90s/yellow .96s; .28 startup, .14 nominal active, .48/.54 recovery. Damage13, guard30, ordinary nonlethal recoil; lethal contact uses existing KO/down lifecycle.
- Actual imported right-foot skin bounds are sampled at120Hz and interpolated into10ms curves. Both facing curves are identical. Forward contact uses min(1.40m, measured forward_max+.04m), separate existing .26m horizontal hurtbox; depth must overlap ±.25m; vertical span is measured min/max±.06m. The actual plane crossing is purple .327346–.406856s / yellow .327315–.407948s, preventing premature off-plane damage. impact_y is captured in world coordinates before trades and drives the roundhouse spark.
- 804 dedicated roundhouse checks (including40 mixed-input full rounds), unchanged474 punch/211 knockdown/42 edge/8 basic and80 seeded rounds pass. Real-main strict roundhouse300 checks include1182 exact paired pose samples, ordinary recoil ownership, hit/block/break/miss, autoplay/mute, air rejection, once-per-action, pause/background/reset/first fresh input and simultaneous trades. Inherited strict punch429, feedback153, presentation311, integration11, AI18 pass. Both complete best-of-three matches include player roundhouse inputs and clean rematches.
- Five-action HUD: portrait2+3 and landscape row, with no additional reserved stage height. All837 UI/input tests,20 old-body checks and55 new roundhouse checks pass (912 total). The new sweep covers880 full-body poses at both arena walls/facings, every.05s plus active endpoints and final frame. Fixed camera minimum width changed6.4→7.2 only to keep the longer foot inside the frame; same arena/rules, no combat-time tracking/zoom. Minimum roundhouse side clearance9.32px at375×614 and9.69px at390×791; prior poses retain6.64px minimum. Smallest action target58.42×48CSSpx at568×267.
- Two20-second actual native AI-match recordings use normal input commands, without HP/pose/position fixtures. Separate four-facing scripted-wall-guard pose fixtures validate continuous support/sweep/recovery, not live AI; their early contact-particle height was subsequently corrected and final AI recordings use the corrected world height. Final reduced-layout PNGs are explicitly posed fixtures, not live matches.
- Exact59 animation sources/runtime/QA were each downloaded and hash/manifest checked. Assets preserve wardrobe/geometry and prior clips; localized garment contacts, stylized static hands and near-opponent leg occlusion remain disclosed, not hidden behind a universal no-intersection claim.
- Fullscreen API behavior, CSS-pixel renderbuffer, pause/rounds/audio gating and owner-private deployment scope remain unchanged. Browser gameplay, physical phones, successful hardware orientation lock and audible output remain LIMITED-QA. Native/logic tests do not certify these devices.

## 功能 v6 最终验收
- 247 弹体规则检查：双角色双向、伤害/正面格挡/空中不可挡、扫掠/大步长、一次扣血、CD提交/打断、起身保护/倒地不可追打、暂停/后台/重开/回合清理及AI公开状态延迟。
- 375 严格真实场景检查，753配对动作样本、12精确骨骼发射事件；576个独立参考骨骼世界位姿误差0，杜绝手动时钟blend延迟。10弹体视觉结构检查。
- 六动作HUD专项556项与完整旧HUD934项通过。86真实蒙皮施法姿态×双墙×六尺寸，身体及VFX共12边界门槛通过；最矮568×267保守VFX上边距约0.55px，其他尺寸留白更多。
- 旧近战/回合/倒起规则回归和严格回旋踢300项保持通过。中文字体确有喵字；CC0原始猫录音解码/波形/导入时长与静音门槛可测，未宣称耳听通过。
- 修复后四向28秒控制夹具显示命中、冷却、第二发格挡；另有紫/黄各25秒正常AI对战，使用正常输入而非修改位置/HP。GIF无声，都是Godot原生，不是浏览器/iPhone录像。
- 网页显示控制器30项、精确引擎输入15项保留；普通云Chrome真指针点击旋转后的第六动作目标、模拟多触点滑动/取消通过。模拟TouchEvent不等于物理iPhone测试。
- 保留全部59基线动作与外形，追加紫2/黄6。局部披肩/头发/手臂内部接触仍记录，不宣称零穿插。心形静态手势并无独立手指骨。
- 普通云浏览器缺WebGL2，浏览器GPU性能/真实iPhone/Safari地址栏/硬件多指/听觉输出仍未测。不得把页面内旋转称为系统方向锁或必然真正全屏。

## P1 功能 v7：方向与空间
224项纯规则（含两角色每方向20次正常起跳越人）、190项真实main输入/状态/蒙皮间距、2686项方向盘与五攻击按钮验证通过。既有375专属技、300回旋踢反馈、429连拳反馈及基本规则/击倒/80轮压力/完整比赛通过。旧连拳落地用例随跳跃变长将输入等待7/4帧改17/14帧，仍检查同一落地锁；重拳push期望.36改.52，其余不弱化。专属触控场景指定真实960×600而非headless默认64×64，按钮契约改为方向盘+五攻击。

真正模拟跳跃96蒙皮姿态、双墙/双朝向/六尺寸全身边界通过，专属技86姿态/发射点边界继续通过。四向蹲起/松开/跳取消原生检查通过，脚底无明显漂浮，大衣裙外露无新明显问题；局部既有接触不作零相交保证。方向区128px竖屏、短横屏68px，是连续操作盘而非四个小按钮，攻击触控尺寸至少48px。

24秒左右并排前后录像同输入：旧版近距离跳未越过，新版成功越过；重拳原生轮廓空隙由约.39m增至.76m。最终7秒段为控制开局后正常AI，其他段明确是控制判定夹具。另有10秒四向蹲起。手机尺寸截图是姿态/布局夹具。浏览器/真机/听感限制不变。

普通云Chrome输入壳最终通过：真实鼠标覆盖八方向/中立/五攻击；四个viewport的合成触点19/19用例均通过；退出模式同时释放两触点与键盘、抑制旧流尾部、重新进入及不支持系统全屏降级正确。Node 15精确输入+30显示壳+8显式mock夹具检查通过。浏览器端使用实际Godot JS回调与明确mock HUD接收器，不是WASM游戏或真实多点触屏认证。

## P2 / functional v8 evidence
- `impact-feedback.json`: 657 checks, 72 actor/facing/move/outcome cases + 4 simultaneous trades; zero failures.
- `impact-native-telemetry.json`: actual native MovieWriter 1800 physics frames, 30 seconds, 15 controlled scenarios, no timing/scenario failures. MP4 preserves engine mixed sound, not an offline fabricated soundtrack. Actual max shake 2.546 px at1280 width (<.3%); HUD stationary.
- `native-audio-measurements.json`: decoded capture48k stereo, peak .0981445, zero clipped samples, explicit muted24–26s segment exactly zero. These measurements are not subjective listening approval; loudness/timbre/latency on phone speakers still needs user device feedback.
- Audio pool74 checks, settings486, directions2686, typed simulation events132. Original cat decoded peak .793619, 28 new lossless PCM assets peak≤.299; fixed10 voices worst-bound .67722.
- Regression logs keep prior failing assertion snapshots marked `-before`: old tests assumed sine tones and silent misses, deliberately superseded by named original impact/whiff cues. Geometry/damage/animation checks remain; heavy hitstop explicit .095 update. Historical shutdown ObjectDB/resource warnings remain in some headless scene suites after success; not concealed as clean logs.
- Native settings375×614 and568×267 inspected, controls fit and ≥44px; new name glyphs and selected鱼 left-yellow/right-purple inspected. Exact exported PCK loads29 audio streams,10players and selected鱼 identity.
- Existing browser shell/input Node53 checks retained. Current cloud browser lacks WebGL2, so actual WebGL gameplay, iPhone/Safari multi-touch, device latency and subjective hearing remain LIMITED-QA. No unsafe flags or false hardware certification.

## P3 · 功能 v9 攻防节奏
AI 只在 240ms 延迟的公开位置/已发生攻击/已发射弹体快照上决策；每个弹体一次概率选择，可能挡、跳或不采取专项反应。中距离可短退、停步或接近，换边被延迟观察到后短暂重新判断。所有既有招式参数、动画、音频与物理文件不变。完整方法、招式表和局限见 P3-RHYTHM-AUDIT.md 与 P3-MOVE-CONTRACT.json。

## P3 功能 v9
仅 AI 公开状态延迟决策修改。完整招式风险参数与同种子比较见 P3-RHYTHM-AUDIT.md / P3-MOVE-CONTRACT.json。80 个固定策略场景每版重复验证，近身时间总体 63.4%→58.9%，混合输入52.7%→43.5%；AI 在脚本中胜率提高，不宣称50%平衡或人工试玩。新增1075意图断言、785037含逐帧边界断言通过；它们不代表同数量独立场景。P4另测实际10分钟原生资源生命周期，不能代替WebGL或iPhone。
