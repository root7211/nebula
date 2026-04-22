# Nebula Phase 3.3：运行时动态列表与实例渲染规划详解

基于 Nebula 项目当前的代码库状态与规划文档（如 `PLAN_PHASE3.md` 和 `ROADMAP_INDUSTRY_RESEARCH.md`），即将启动的 **Phase 3.3** 标志着 Nebula 从“静态界面”向“动态高性能应用”的重大架构跨越。

以下是对 Phase 3.3 具体规划、技术挑战及实现路径的详细梳理。

---

## 1. 核心目标与定位

在 Phase 2 完成了“形即渲染”（组件状态机、自动布局、着色器组合）以及 Phase 3.1/3.2 完成了静态布局和 SDF 文本子系统之后，Nebula 已经具备了渲染高质量静态界面的能力。

**Phase 3.3 的核心目标**是：重构底层渲染基础设施，引入**实例渲染（Instancing）**与**基于对象池的动态列表**，使得 Nebula 能够以 60FPS 的稳定帧率，零开销地渲染成百上千个同类组件（如长列表、数据表格）。

## 2. 行业标杆借鉴与架构演进

根据最新的行业调研，Phase 3.3 深度借鉴了目前全球响应速度最快的文本编辑器 **Zed (GPUI)** 以及现代 GPU 矢量渲染库的设计哲学。

### 2.1 内存管理：Arena Allocation (内存池分配)
为了解决动态列表带来的频繁内存分配与碎片化问题，Nebula 将引入面向数据设计（DOD）。
*   **当前状态**：组件状态（如 `ButtonContext`）在栈上或通过常规堆分配。
*   **演进方案**：在每一帧开始时分配一块连续的大内存（Frame Arena）。帧内所有新创建的列表项、动态布局数据均从该 Arena 分配，帧结束时整体释放，实现真正的“零 GC 暂停”。

### 2.2 渲染指令流：无状态与统一实例缓冲区
*   **当前状态**：每个组件拥有自己独立的 Uniform Buffer 和 BindGroup，通过单独的 Draw Call 提交（如 `headless_test.c` 中所示的单次 Draw Call）。如果列表有 1000 项，就会产生 1000 个 Draw Call 和状态切换，迅速耗尽 WebGPU 的绑定限制。
*   **演进方案**：将所有同类组件（例如所有的 Button）的视觉属性（位置、颜色、圆角等）编码并打包到一个全局的 **Storage Buffer** 中。在着色器（`shader_compose.lua`）中，利用 `@builtin(instance_index)` 和 `@builtin(vertex_index)` 来索引对应组件的数据，从而实现**一个 Draw Call 渲染万物**。

## 3. 具体技术挑战与解决路径

### 3.1 GPU 状态爆炸与实例化渲染
如 `PLAN_PHASE3.md` 所述，如果继续沿用 Phase 2 的架构，大规模组件将导致 GPU 状态爆炸。
*   **解决路径**：重构 `pipeline_factory.lua` 和 `renderer.nelua`。
    *   当前 `wgpu_bindings.nelua` 已经暴露了 `WGPUVertexStepMode_Instance`。
    *   需要在管线工厂中新增支持实例属性输入的配置。
    *   将 `NebulaUniforms` 升级为支持数组或 Storage Buffer 形式的 `InstanceData`。

### 3.2 动态尺寸与编译期布局的矛盾
Nebula 的核心哲学是“编译期解算”，但动态列表的内容和数量在运行时才可知。
*   **解决路径**：混合模式布局。编译期（`layout_engine.lua`）解算列表容器的静态约束（如 Flexbox 的对齐方式、间距），并生成高效的运行时布局更新函数。运行时，当列表项增删时，调用这些预生成的函数快速计算绝对坐标，并写入实例缓冲区。

### 3.3 生命周期与焦点管理
条件渲染和长列表滚动意味着组件会被频繁销毁和重建，这使得输入状态（如 `NebulaInputState` 中的 `focused_id`）的管理变得复杂。
*   **解决路径**：建立基于组件 ID（`component_id`）的虚拟化机制。即使列表项在屏幕外被回收，其逻辑焦点状态仍由一个全局的焦点链（Focus Chain）维护。

## 4. 预期交付物与验收标准

Phase 3.3 预计开发周期为 2-3 周，其主要交付物和验收标准包括：

1.  **底层架构升级**：
    *   `renderer.nelua` 新增 Storage Buffer / Instance Buffer 的创建与更新接口。
    *   `pipeline_factory.lua` 能够自动派生支持 Instancing 的渲染管线。
    *   `shader_compose.lua` 支持基于 `instance_index` 的数据解包。
2.  **运行时对象池**：
    *   实现基于 Nelua 的高效 Frame Arena 分配器。
3.  **演示与测试**：
    *   新增 `dynamic_list_demo.nelua`，展示包含 10,000+ 个可交互组件的平滑滚动列表。
    *   集成到 `run_all_tests.sh` 中，确保无性能回退。

---

**总结**：Phase 3.3 是 Nebula 从“证明概念”走向“生产可用”的关键一步。通过引入 DOD 内存布局和 GPU 实例渲染，Nebula 将彻底解决大规模 UI 渲染的性能瓶颈，为其宣称的“极致性能”提供坚实的底层支撑。
