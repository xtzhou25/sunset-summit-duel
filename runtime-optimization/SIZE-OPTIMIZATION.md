# 体积优化说明 / Size optimization

## 实际文件变化
- 原版 EXE：104,659,456 bytes。
- 优化 EXE：49,139,712 bytes，减少55,519,744 bytes（53.05%）。
- 游戏 PCK：13,932,428 bytes，完全不变。
- EXE + PCK：从118,591,884 bytes减到63,072,140 bytes，减少46.82%。不含少量说明及许可。

没有删角色、动作、音效、舞台、字体或游戏规则，也没有降低资源质量。对142个PCK文件逐项检查，没有发现测试/文档/原始模型等可安全删除的冗余，因此保留完整PCK。没有使用UPX或可执行文件加壳工具。

## 方法
从官方Godot4.6.3-stable源码编译原生Windows x86_64 release模板，使用体积优先优化。保留游戏实际使用的Compatibility/OpenGL3渲染，关闭未使用的Vulkan、Direct3D12和XR功能；其余3D、动画、物理、音频、字体、高级文本/CJK和资源格式支持保留。

完整来源、编译器及标志见BUILD-PROVENANCE.json。官方源码版权声明和第三方许可在licenses/LICENSE.txt及licenses/COPYRIGHT.txt；旧版引擎生成的声明也保留以便追溯。

## 校验与验收边界
- 优化EXE SHA256：d5a52b1b05a8ee34ff8c4cbb0b972b6294e8f6f3555aad4290ce43ed49def0e0。
- 原样PCK SHA256：74c848485257814f620a92918dcb890e1bca0a75ed952f0881cad39dedb03422。
- 编译成功、Windows PE结构及动态依赖已检查；ZIP通过CRC检查。
- 本环境没有Windows真机；本地Wine启动器在来宾程序初始化前以invalid pointer/退出码134中止，对独立最小测试EXE也一样，因此无法用于运行验收，不能据此判定游戏失败。新的Windows EXE尚未实际执行。不能将此前Linux原版引擎的图形、输入及全屏验证视为新EXE运行验证。
- 五角色/20组合/43音频流、36项桌面输入等检查针对未变化的PCK，完整记录见BASELINE-BUILD-REPORT.md。
- EXE没有代码签名；不要关闭安全软件。解压后保留EXE/PCK同目录，再双击EXE。

Source revision: the official4.6.3 release article and source tag identify35e80b3a8 (https://godotengine.org/article/maintenance-release-godot-4-6-3/). Both the original downloaded Windows template and preinstalled Linux baseline identify7d41c59c4 instead. That baseline revision could not be resolved in the public repository. We therefore do NOT claim commit-identical engines despite the shared4.6.3 label. This custom build follows the canonical official release source recorded in BUILD-PROVENANCE.json; only the game PCK is proven byte-identical. Windows launch remains an explicit unverified boundary.
PCK compiled GDScript tokenizer headers were independently checked: main/combat/hud all use version101, matching the custom source tokenizer. This static compatibility check is not a substitute for a Windows runtime test. Static compiler/runtime license notices are retained under licenses/LLVM-MINGW-LICENSE.txt and licenses/toolchain/.
