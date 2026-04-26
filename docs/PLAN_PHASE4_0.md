# Nebula Phase 4.0 开发计划：编译期公理校验器 (Axiom Validator)

## 1. 目标与愿景
Phase 4.0 的核心任务是将 Nebula 的架构哲学（三大公理与七大不变量）从“文档共识”升级为“编译器强制约束”。基于 **注册表质量门 (Registry Quality Gate)** 方案，我们将利用 Lua 宏在 S1 阶段的全局可见性，在代码生成之前对元数据进行深度语义校验。

## 2. 核心校验架构
我们将引入一个独立的校验模块 `src/derive/axiom_validator.lua`，并在 `nebula_core.nelua` 和 `app_factory.lua` 的关键生成入口处挂载校验钩子。

### 2.1 校验层级
- **Visual 级校验**：在 `nebula_derive` 入口触发，校验单个组件规格是否违反生命周期公理。
- **App 级校验**：在 `nebula_derive_app` 入口触发，校验组件间的组合关系、管线唯一性及静态展开约束。

## 3. 重点实施任务

### 3.1 任务 A：生命周期类型白名单 (公理 B 约束)
- **目标**：防止 L2（帧级）数据泄漏到 L1（持久层）。
- **实现**：
    - 在 `axiom_validator.lua` 中定义 `L1_TYPE_ALLOWLIST`（包含 `float32`, `Vec2`, `Vec4`, `Color`, `bool`）。
    - 校验 `nebula_registry[type_name]` 中的所有字段。
    - **禁止项**：严禁在 Visual Record 中直接使用 `NebulaTextMesh`、`GapBuffer` 或任何指针类型。
    - **报错**：若校验失败，抛出带有具体字段名和违规类型的编译错误。

### 3.2 任务 B：管线签名哈希与去重 (公理 C 约束)
- **目标**：确保“相同形态即相同渲染”，消除冗余管线，预防 wgpu 布局冲突。
- **实现**：
    - 遍历 `nebula_app_registry[app_name].type_groups`。
    - 为每个 Visual 类型计算 `PipelineSignature`（基于字段列表、着色器 Feature、Uniform 字节大小）。
    - **强制合并**：如果两个不同的 Visual 类型计算出相同的签名哈希，校验器将修改 `type_groups`，强制它们共享同一个底层 `Pipeline` 实例。
    - **布局预检**：比对 Nelua Uniform 布局与 WGSL 结构体，确保字节对齐 100% 匹配。

### 3.3 任务 C：静态展开验证 (不变量 I1 约束)
- **目标**：彻底杜绝运行时组件树遍历。
- **实现**：
    - 校验 `nebula_app_registry`。
    - **禁止动态注册**：确保所有组件名均为合法的静态标识符。
    - **Slot 约束**：校验 `reg.slots` 的 `max_instances` 必须为编译期常量。
    - **代码生成审查**：确保 `gen_app_update` 仅生成显式的具名成员调用，不含任何基于数组的循环。

## 4. 进度安排 (Milestones)

| 阶段 | 任务名称 | 关键产出 |
| :--- | :--- | :--- |
| **M1** | **校验器骨架搭建** | 创建 `axiom_validator.lua`，定义核心接口与报错机制 |
| **M2** | **Visual 语义校验** | 实现 L1 类型白名单，挂载到 `nebula_derive` |
| **M3** | **管线签名引擎** | 实现签名哈希计算与 App 级的管线去重逻辑 |
| **M4** | **全量回归测试** | 编写 `smoke_phase4_0.lua`，构造违规用例确保校验器能准确拦截 |

## 5. 验收标准
1. **拦截成功率**：所有故意违反公理的测试用例（如在 Visual 中使用指针）必须导致编译失败。
2. **零性能损耗**：校验过程仅发生在 S1 编译期，生成的 S2 运行时二进制文件不含任何校验逻辑。
3. **错误提示友好度**：编译错误必须指明具体的组件名、字段名及违反的公理编号。

---
**Next Phase**: Phase 4.1 (Slug 文本渲染引擎 — Unicode/CJK 支持)
