# 音效选择细化（功能 18 候选）

## 审核结论和边界
原有轻拳、直拳、重拳、踢击、挥空拳/踢、格挡、破防已分别有音色、包络、增益和限频，保留它们，不为了“调整”全部替换。问题是桃/哈生成时均复用爱心发射，桃命中借用直拳，哈缺少独立预警与落地声音。本次仅改音频呈现，不改攻击判定、伤害、冷却、目标锁定或 AI。

- 因：继续使用真实猫叫，不变调、不加速、不替换。`docs/MEOW-AUDIO-LICENSE.txt` 的 BigSoundBank / Joseph SARDIN CC0 原始出处继续有效，原始录音和游戏版 SHA 不变。
- 鱼：保留柔和爱心发射；新增短气泡/谐波接触，不借用直拳。
- 七：单次圆润街机“啪”，不连射；带限瞬态、较缓起音，避免尖利长尾。不是现实枪械采样。
- 桃：带空气感的弹性果实发射和软果实接触，不使用枪声或普通拳击。
- 哈：施法锁定时双轻提示、生成时短下行空气声、命中或真正落地时海绵双段闷响。格挡/破防仍仅用相应通用接触声，不叠普通命中。
- 无 BGM、旁白、角色人声、商业游戏音频。

## 来源和复现
新增 `assets/audio/refined/` 共14个单声道48kHz/16bit PCM WAV，均由本项目助手原创数值合成；输入是固定种子噪声、振荡器、带限/包络参数，没有任何外部采样。没有新增第三方音频许可依赖；此说明不为整个项目另行授予许可。旧源码/素材保留，运行时仅把指定 cues 路由至 refined 目录。

```
python3 scripts/generate_refined_audio.py --baseline .
python3 scripts/generate_refined_audio.py --baseline . --check
```

生成器需 Python3/NumPy。相同参考环境可逐字节复现；`--check` 比较全部14个已存 WAV。manifest 含 SHA256、时长、峰值、RMS、端点、削波数和试听顺序。Godot import 禁用归一化、trim、loop、有损压缩，保证混音预算。两变体仅1.8%音色频率差、4ms时长差；运行时不变调、每事件仅播一个变体。

## 音量和叠音
保留10个固定播放器：6战斗、2猫叫、2UI；分组滑块、静音、失焦暂停、事件去重、无延迟重播均不变。新声音峰值≤0.28（−11.06dBFS），新cue线性增益为 .12–.21，七 .17。普通命中优先级高于空气/预警，新增cue最多同时2个，冷却60–120ms；既有类别不放宽。

所有10个声部任意相位开始的保守采样峰值上界为0.677163（约−3.39dBFS），前提是维持固定声部、增益帽、没有外加音源或总线增益。它是数值上界，不是声压安全保证或认证true-peak测量。

## 接线契约
- attack kind special，施法者 kind=4：cake_warn。使用已有被接受攻击事件，拒绝输入不发声。
- projectile_spawn：meow→meow，heart→heart_emit，rifle→rifle_emit，peach→peach_emit，cake→cake_drop。
- hit：heart→heart_hit，peach→peach_hit，cake→cake_land；其他不变。
- block/break：优先 block/guard_break，禁止额外 hit 声。
- 视图层记 projectile id→kind；despawn reason boundary 且蛋糕 pos.y≈0 才 cake_land。contact despawn 不发声，避免与命中重复。清局同时清映射；不为 range/lifetime 播着地。

## 试听材料与限制
`preview/audio-selection-preview.wav`：17段/13.065秒，片段间隔0.55秒；`preview/试听顺序.txt`标注时间。预览整体单独+12.04dB便于试听，峰值−9.126dBFS、RMS−33.866dBFS，零削波；不是实际对局录音。游戏内仍使用低增益。没有可确认的音频输入/监听工具，因此尚未通过扬声器/耳机主观试听，也不声明实手机、浏览器听感已验收。波形、频谱或角色描述不是实听证据。

## 独立运行时验证
Godot 4.6.3 / Dummy 驱动：原音频池测试更新资产数量后74项全部通过；新增7类声音的派发、独立资源路径、限频、原速播放、静音停止、不重播共42项全部通过。旧测试经软件捕获验证真实猫叫解码峰值0.793619，仍在0.795预算内。这是AudioServer/软件解码验证，不是实际音箱监听。初次测试因默认XDG目录不可写未启动，改用 `/tmp` 可写测试配置后成功；测试极速退出产生的临时音频引用警告已通过等待AudioServer释放消除。最终日志在 `qa/refined-audio-test.log`、`qa/refined-specific-test.log`。
