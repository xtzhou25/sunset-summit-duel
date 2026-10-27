# 决战日不落之巅 / Sunset Summit Duel

Independent Godot 4.6 project. Original purple-white and yellow-white characters, a single fixed-view 2.5D underground livehouse, friendly non-gory sparring. No original Vesper project code or deployment is modified.

## Milestones and acceptance
- M0: deterministic arena simulation, fixed side view, actual imported characters; headless mechanics tests and real native screenshot.
- M1: player selection, finite-delay AI, 60-second rounds, best of three, draws replay, keyboard/touch, pause/background/cancel and fresh rematch state.
- M2: polished bounded-cost livehouse, reaction/guard/knockdown/victory clips; readable clothing, no foreground foot occlusion, no flashing lights.
- M3: regression, real native/web checks where supported, portrait/landscape coverage, source and export checkpoints with exact archive hashes/CRC. Explicitly report unavailable browser/iOS checks. Candidate only; publication requires release approval.

## Combat design
Arena tightened for fullbody legibility. World X only with vertical jump Y, Z=0. 4.2m center-movement arena; floor and edge clamped. Ground bodies cannot cross; aerial pass intentionally allowed. Facing tracks opponent outside committed attacks. Retreat blocks frontal ground hits while guard remains. Guard wears down and only regenerates outside blocking after delay. No midair block. One damage event per attack. Short two-hit chain only, defender recovery protection against indefinite combos. Punch quick short-range, flying kick longer commitment. Fighters begin from equal foundations, then small recovery/reach differences.

## Controls
A/D or arrows move, Space jumps, J punches, K flying kicks, Escape pauses. Touch controls occupy a distinct bottom panel. World arena remains identical in portrait and landscape; no orientation lock. Sound starts only following a user input and can be muted.

## Persistence
Keep input Library identities and animation attribution in asset manifest. Save milestone source archives plus web candidate separately; retain local and downloaded SHA256 and ZIP CRC validation. Never claim a save is verified solely from an upload acknowledgement.

## Completed progression — 2026-10-25
M0: real original models imported into a new clean project; deterministic greybox and actual native renderer checked.
M1: complete selectable-character AI matches, keyboard and touch, rounds, pause/focus/rematch lifecycle. First source checkpoint persisted and actual readback SHA/ZIP CRC matched.
M2: underground livehouse, soft readable character lighting, nineteen clips including guarded backstep, native portrait character height approximately 128 px at 390×844. User renamed the game 决战日不落之巅; all active titles and stage branding updated.
M3 candidate: 8 basic combat checks, 42 edge checks, 110 responsive touch/HUD checks, lifecycle tests, 80 seeded rounds and two full end-to-end AI matches passed. Four aspect-ratio camera bounds checks passed; actual native screenshots retained. Browser WebGL2 unavailable in ordinary cloud Chrome, explicitly LIMITED-QA. Exact RC1 was approved and published as owner-private Site v1 on 2026-10-25. Online files are frozen pending device feedback.

## Final measured tuning
Global uniform model scale 1.2. Arena centers [-2.1, 2.1]. Push half-width .35, hurtbox half-width .26. Punch front .60/.55 m, kick front .73/.78 m; startup .14/.36 s and active .10/.13 s. Forward run 2.4 m/s uses measured source gait speed; retreat .66 m/s uses BackstepGuard at 1.0/1.0643. Jump5m/s and gravity17.5m/s², deliberate apex air pass threshold .55m. Stage boundaries never drop actors.

## First release delivered — 2026-10-25
All planned core milestones M0–M3 are implemented. The exact RC1 was published at https://sunset-summit-duel.coral-pear-2376.chatgpt.site, active v1 / commit f00ffd3036f74cd8899100c9c72b0ace70dd73d2. All ten deployed game files matched the approved manifest byte-for-byte. Site access is owner-only. Vesper remains active v16 at its original commit.

No unimplemented core feature remains in this first-release scope. Next-stage validation depends on user device feedback: signed-in browser launch, WebGL2/mobile performance, physical multitouch ergonomics and audible effects. Native aspect-ratio tests do not replace physical-phone testing. Do not modify the live first release for unsolicited polish while the user is trying it. Fix a reported reproducible defect or proceed with a newly approved change as a separately versioned candidate.

The frozen RC1 archive and deployment are unchanged; this post-publication plan and delivery index are additional release records.

## v2 bounded revision candidate — 2026-10-25
User requested a fighting idle and visible impact feedback. Added FightIdle/HitReactStrong, preserving19 prior clips. Root cause: prior .4s hit reaction was blended in for .08s, initially frozen by hitstop, then truncated by .24/.32s stun. Recoil now enters immediately at .04s and follows explicit hit age over the unchanged stun window; manual AnimationPlayer advancement prevents blend clocks freezing while deterministic attack poses are sought. Menu Idle and round-end Victory/Knockdown remain distinct.

Punch/kick/block hitstop .055/.075/.025s. Small directional warm hit sparks versus weaker blue blocks and distinct tones; misses trigger none. Damage, ranges, guard costs, invulnerability and combo recovery remain unchanged. Effects stop with pause and reset cleanly; character switching reuses the two models rather than destroying shared renderer resources mid-frame. Strict153 feedback assertions and original42 edge assertions pass. Actual native three-second before/after GIF uses repeatable inputs, not an artist animation or mockup.

RC1 remains frozen for rollback. The exact RC2 was approved and published as active Site v2. Existing browser/mobile/audio LIMITED-QA remains.

## v2 publication completed — 2026-10-25
Active v2 commit 8a6bbda4fae390990be2bd6937d83c31ca0037ad. All10 deployed files were read back with supported service access and matched RC2 sizes/SHA256. Access remains owner-only revision1, and v1 stays available for rollback. Vesper remains active v16 unchanged. RC2 source archive passed actual Library download SHA/CRC/all84 manifest hashes, clean import and all153 strict feedback checks. Scope is complete; await user browser/device feedback without unsolicited live changes.

## v3 action revision — 2026-10-25
User requested camera-facing fighting presentation and responsive knockdowns, with patient motion refinement. Added15 paired animation bases per character while preserving original21. Actor roots and hitbox plane are unchanged. Engine now maps both facings without blending through the wrong-facing pose; all punch/kick/reaction/down clocks are explicit.

Nonlethal unblocked flying kicks now enter loss→ground catch→settled kneel→recovery→protected ready. Original v2 used Knockdown only after KO and never played Recover during a normal match. Airborne loss waits for actual floor contact, down/rise actors cannot be hit or act, fresh wake-up input works immediately, and held stale input does not auto-fire. KO settles and holds without recovery; timeout/airborne winners finish their existing motion without further combat. Pause/background/rematch resets remain clean.

Final bounded animation candidate: purple21732563754c7765f37801d87136cd2e2938f9686da955315d4271b744d4d52c; yellowd083c9c4125d3e57bf9b942896bb243e3a2954c978748bf3ad6a18206ad58eb9. A visible yellow shoulder gap found in native playback was traced to a temporary cape avoidance flap exposing an intentionally omitted under-cape mesh region; restoring original drape fixed it without changing geometry or hand targets. Local concealed cape contacts remain documented, not claimed collision-free.

Final309presentation and153feedback assertions pass, in addition to211knockdown and unchanged baseline regressions. Exact candidate publication still requires approval after source/web/native QA persistence and download verification. Live v2 and frozen RC1/RC2 remain unchanged during this work. New user-authorized jab→straight and heavy punch scope is queued separately in NEXT-ATTACK-PLAN.md, not included in this revision.

## Gameplay v4 closeout
Distinct jab→straight two-press chain and separate heavy are implemented, measured-reach calibrated, and core regressions pass. Fullscreen v3.1 remains present in this branch; short-height HUD and camera allocation are bounded fixes, not arena/physics changes. Final native fixture review, clean packaged-source import and Library whole-candidate readback gate release. Next requested ground roundhouse belongs to a separate functional v5 and is not included in this57-clip candidate.

## Gameplay v5 closeout
Grounded roundhouse implemented for both characters with dedicated I/five-action HUD, actual-foot XYZ contact gating, correct impact-height feedback, fixed support and return-to-stance animation, and unchanged previous combat/round rules. Native four-facing continuous pose gates and normal AI gameplay pass. Final candidate persistence, clean-extraction verification and exact approval gate publication. No further moves are included in this revision.

## v5.1 页面内横屏修订（待批准发布）

- RC5 冷恢复：ZIP SHA256、CRC、182 项清单均验证。旧线上功能 v5 / Sites v6 保持回滚。
- 页面横屏独立于系统全屏，不调用 orientation.lock。竖屏时整容器顺时针90度且交换逻辑宽高；物理横向时不额外旋转；viewport resize/scroll、safe-area 边映射、返回按钮均保留。
- 精确 Godot 4.6 Web 输入补丁：clientXY 逆变换一次、relative movement 同步旋转、原 touch ID 多指路径保留。模式变化前释放鼠标/触点/键盘，取消触点在按钮外释放，抑制旧流尾部与旧按键 repeat。
- 保留原五个生产 GDScript 文件、全部模型和 PCK / WASM。网站十文件只有 index.html 与 index.js 变化。
- 回归：回旋踢804项、原HUD912项、附加横屏与身体边界530项、真实HUD取消/选择/暂停/重开467项、集成11项通过。新的JS输入15项与显示控制器30项通过。
- 普通云Chrome真实指针验证与模拟TouchEvent测试分别记录。真实游戏仍报告缺WebGL2，未改安全标志；iPhone真机与Safari地址栏/硬件多指未测，交付为诚实标注的可操作试验版。
- 不增加新招式或改变格斗规则。完整候选保存并回读后等待批准，用户试玩反馈为下一阶段依据。

## 功能 v6 专属技能收口 — 2026-10-25
在已发布 RC6 功能 v5.1 / Sites v7 基线上追加两角色专属弹体，不修改旧近战伤害、连段、倒起、回合规则。固定相机身体高度预算从3.10m改3.16m，仅用于矮横屏爱心上缘，不跟随战斗缩放。接受施法时提交4秒CD；真实骨骼发射点、扫掠碰撞、单次命中、正面地面格挡、打断/暂停/后台/清理均验证。

连续验收发现旧 .10s 动画 blend 与手动 seek/零advance冲突，导致黄白左向抬臂延迟。专属动作改为零blend并使用唯一模拟phase时钟，精确首尾相接；独立干净导入的576骨骼世界位姿逐点比较误差0，375场景检查通过。最终四向原生录像在修复后重新录制，不沿用失败画面。

六动作自适应HUD、冷却遮罩/秒数与页面内旋转输入保留。音源为CC0真猫录音，字体包含喵字，字面永不镜像；音频仅用户手势后播放，mute/暂停立即停止。原生音频硬件与iPhone未验证，如实保留LIMITED-QA。最终候选须完整保存并实际回读后提交批准；旧线上版本保持不动。

## P1 方向与空间优化 — 2026-10-25
用户实测后授权更容易跳过、快速后退、重击推开，并追加上跳下蹲/斜跳/空中控制。独立RC8实现，未混入P2声音重构。完整参数与状态优先级见 P1-SPACING-CONTROLS.md；执行计划 Library [private-archive-reference-omitted]。P1完成发布后顺序推进P2反馈音效、P3攻防/AI审计、P4性能与输入回归，各阶段独立持久验证与版本回退，未测真机/听感不得宣称通过。

## 2026-10-25 P2 / functional v8 / RC9
P1 published and frozen before this branch. P2 adds typed actual-event audiovisual feedback, original PCM impact variants, fixed audio pool, settings, bounded camera-only micro-shake. No gameplay damage/attack window changes; heavy presentation hitstop 85→95ms. Character naming update: 因=purple, 鱼=yellow; HUD identity colors follow kind, not slot/world X. Native MovieWriter 30s audio/video and settings pictures inspected; 657 real-main tests, 486 settings/identity, 2686 directional checks and prior rules regressions pass. Sources/QA/license and Library roundtrip are required before deployment. P3/P4 remain next, no expanded systems.
