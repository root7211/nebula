# Nebula 项目死代码审查报告 (Phase 3.9)

**审查日期**：2026年4月25日
**审查目标**：识别 `nebula` 仓库中未被引用的函数、废弃的代码路径、冗余的工具脚本以及遗漏的测试套件。

经过对核心源文件、Lua 代码生成器、示例代码和测试套件的全面静态分析，发现项目中存在一定数量的死代码和废弃工具。以下是详细的审查结果与清理建议。

## 核心源文件与代码生成器

在核心源文件中，`src/primitives.nelua` 包含了废弃的交互原语。该文件定义了 `HoverableState:update` 和 `ClickableState:update` 两个手动更新方法，这是 Phase 0 遗留的 API。自 Phase 2.4 引入 `interaction_factory.lua` 以来，交互状态机已改为编译期自动生成，`process_input` 方法内联了 AABB 检测和状态转换。虽然多个 demo 文件和 `nebula_core.nelua` 仍有 `require "primitives"` 和结构体字段声明，但其核心的 `:update()` 方法在全仓库中没有任何调用。建议在后续重构中，将 `HoverableState` 和 `ClickableState` 的结构体定义移入 `nebula_core.nelua`，并彻底删除 `primitives.nelua` 文件。

相反，`src/nebula_cursor.nelua` 提供的极简光标渲染辅助函数（`nebula_cursor_x_offset` 和 `nebula_cursor_visible`）仍处于活跃状态，被 `form_demo.nelua` 和 `login_demo.nelua` 引用，且有专门的测试套件覆盖。

在 Lua 代码生成器方面，`src/derive/app_factory.lua` 中保留了 `legacy_count_var` 和 `legacy_data_var` 的生成分支。这属于向后兼容代码，而非死代码，因为 `smoke_phase3_9.lua` 中有专门的测试用例覆盖此分支。此外，`pipeline_factory.lua` 和 `shader_compose.lua` 已在 Phase 3.7 的管线收敛工作中被彻底清理，废弃的路径已被完全删除。

## 工具脚本与测试套件

项目中的冗余主要集中在历史迁移工具和早期阶段的测试脚本上。以下表格总结了这些废弃文件的状态与清理建议：

| 文件/目录 | 状态 | 分析与建议 |
|---|---|---|
| `tools/patch_*.py` | 死代码（废弃工具） | 这些是 Phase 3.6.3 期间用于向源码中硬编码插入多行字符串的 Python 脚本。目前这些变更早已固化在源码中，脚本已失去作用。建议直接删除。 |
| `tools/smoke_phase3_2_*.lua`<br>`tools/verify_p2_4.lua` | 死代码（废弃测试） | 这些早期的 Lua 冒烟测试脚本中硬编码了旧版本的模块断言。目前运行这些脚本会直接报错。建议从 `run_all_tests.sh` 中移除对这些脚本的调用，并删除文件。 |
| `tools/run_all_tests.sh` | 配置遗漏 | `tests/smoke_phase3_6_3.lua`（文本选区支持冒烟测试）存在于仓库中，但未被加入到执行列表中。建议在脚本中补充该测试的调用。 |
| `tests/smoke_phase3_8.lua` | 部分死代码/需修复 | 该测试套件中包含了对 `app_factory.lua` 行数上限和版本号的硬编码断言。在 Phase 3.9 升级后，运行此测试会产生失败项。建议更新断言阈值，或将其标记为历史归档测试。 |

## 总结与行动建议

Nebula 项目整体代码质量较高，核心推导引擎中没有明显的死代码。为了进一步保持代码库的整洁，建议执行以下清理操作：

首先，删除 `tools/patch_*.py` 系列一次性脚本，以及 `tools/smoke_phase3_2_*.lua` 和 `tools/verify_p2_4.lua` 等早期测试脚本，并从 `run_all_tests.sh` 中移除对应条目。其次，将遗漏的 `tests/smoke_phase3_6_3.lua` 补充进 `run_all_tests.sh`，并修复 `tests/smoke_phase3_8.lua` 中的过时断言。最后，可以考虑重构 `primitives.nelua`，将结构体定义内聚到 `nebula_core.nelua` 并删除该文件。
