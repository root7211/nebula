# Nebula v3：计算统一架构白皮书

**版本**：v0.1-alpha (Visionary Draft)
**日期**：2026-04-26
**设计者**：Manus AI
**愿景**：消除 CPU 与 GPU 的鸿沟，实现“布局即计算，渲染即结果”。

---

## 1. 核心哲学：公理 Ω（计算统一性）

在 Nebula v3 中，前代的公理体系被升华为一个更高维度的统一场论：

> **公理 Ω**：CPU 仅负责“意图的编排”（Orchestration），GPU 负责“事实的生成”（Generation）。

这意味着 CPU 不再参与任何关于“像素位置”或“组件状态”的具体计算，它只负责将开发者的声明意图转化为 GPU 可理解的约束流。

---

## 2. 三大技术支柱

### 2.1 Compute Shader Layout (CSL)
**现状**：v2 在 S1 阶段（编译期）或 S2 阶段（CPU 运行期）解算布局。
**v3 变革**：将布局算法（如 Flexbox）完全迁移至 GPU Compute Shader。
- **机制**：CPU 将 UI 树序列化为存储在 `Storage Buffer` 中的约束节点。
- **解算**：每帧渲染前，GPU 运行 CSL 内核，并行解算数万个节点的几何属性。
- **哲学意义**：彻底解决“内容自适应布局”的二元论冲突。

### 2.2 拓扑流渲染 (Topology Stream Rendering)
**现状**：CPU 显式发出每个组件的 Draw Call。
**v3 变革**：引入 GPU 驱动的间接绘制（Indirect Drawing）。
- **机制**：GPU 根据布局解算和逻辑状态，自行生成绘制指令并写入 `Indirect Buffer`。
- **结果**：实现真正的动态拓扑变化，CPU 负载降至近乎为零。

### 2.3 统一状态仓库 (Unified State Storage)
**现状**：状态在 CPU 侧维护，通过 Uniforms 传递给 GPU。
**v3 变革**：所有 UI 状态（L1 层）原生驻留在 GPU 显存中。
- **机制**：交互逻辑（如点击、聚焦、动画转移）由 Compute Shader 直接在显存中完成状态更新。
- **同步**：CPU 仅作为事件的“搬运工”，将原始输入（鼠标/键盘）投递到 GPU 缓冲区。

---

## 3. 路线图展望

1. **Phase 6.0 (Research)**：实现基于 WGSL 的并行 Flexbox 解算器原型。
2. **Phase 6.1 (Integration)**：重构 `app_factory` 以支持约束流序列化。
3. **Phase 7.0 (Unified)**：全面转向 Indirect Rendering，废弃 CPU 侧的绘制编排。

---

## 4. 结语

Nebula v3 代表了 GUI 技术的终极形态：一个运行在 GPU 上的并行操作系统内核。它将使 UI 的复杂性与 CPU 性能彻底脱钩，释放出前所未有的交互潜能。
