# 行业标杆研究与 Nebula 架构演进设想

> **摘要**：通过对高性能 UI 框架（Zed/GPUI）与现代 GPU 矢量渲染库（Vello/Piet）的深度调研，本报告旨在提炼核心设计模式，并将其引入 Nebula 的中长期路线图。

---

## 1. 行业标杆深度剖析

### 1.1 Zed (GPUI) — 极致的性能与内存管理
Zed 是目前全球响应速度最快的文本编辑器，其核心 UI 框架 **GPUI** 为 Nebula 提供了“交互级性能”的参考。

*   **核心模式：Arena Allocation (内存池分配)**
    *   **原理**：在每一帧开始时分配一块连续的大内存（Arena），帧内所有 UI 组件、文本布局数据均从此处分配。帧结束时直接整体释放，无需细粒度的 GC 或 `free`。
    *   **Nebula 借鉴**：与 Nelua 的内存分配器高度契合。Nebula 未来可引入 `FrameArena`，在 `TextVisual` 更新或动态布局计算时，彻底消除运行时内存碎片。
*   **核心模式：图层合成与离屏缓存 (Layer Caching)**
    *   **原理**：将静态的 UI 子树预渲染到离屏纹理中。只要子树状态未变，GPU 直接合成纹理，跳过所有 Visual 逻辑。
    *   **Nebula 借鉴**：在 Phase 4 中，可将 `@layout` 嵌套树标记为 `static_layer`，编译期自动生成离屏 Pass 逻辑。

### 1.2 Vello / Piet — 计算着色器驱动的矢量渲染
Google 与社区驱动的 Vello 项目代表了“后光栅化时代”的最高水平。

*   **核心模式：Compute Shader Tiling (分块计算)**
    *   **原理**：不使用传统的顶点/片段管线，而是利用 Compute Shader 将屏幕划分为 Tile，并行解算复杂的贝塞尔曲线和矢量路径。
    *   **Nebula 借鉴**：目前 Nebula 的 SDF 形状受限于简单几何体。未来若需支持 SVG 或复杂图标，可借鉴 Vello 的“分块解算”思想，在 `shader_compose.lua` 中引入基于 Compute Shader 的路径光栅化模板。
*   **核心模式：无状态渲染指令流**
    *   **原理**：将渲染指令序列化为紧凑的编码流，由 GPU 端的解释器执行。
    *   **Nebula 借鉴**：这为 Nebula 的 **Phase 3.3 (实例渲染)** 提供了灵感——不再是每个组件一个 Draw Call，而是将所有组件的属性（位置、颜色、圆角）编码进一个全局 Buffer，通过一个 Draw Call 完成万物渲染。

---

## 2. Nebula 架构演进路线图 (更新版)

### Phase 3.3 — 运行时动态列表与实例渲染 (当前重点)
*   **DOD (面向数据设计)**：借鉴 GPUI 的紧凑内存布局。
*   **统一实例缓冲区**：将所有形状的 Uniform 数据合并为 `Storage Buffer`，利用 `vertex_index` 和 `instance_index` 在着色器中索引数据。
*   **目标**：支持 10,000+ 组件的 60FPS 稳定渲染。

### Phase 3.4 — 文本编辑原语与键盘交互 (新增)
*   **排版引擎解耦**：借鉴 Piet 的分层思想，将“字形排版（Layout）”与“字形渲染（SDF Render）”彻底分离。
*   **可变文本缓冲区**：引入高效的 `Gap Buffer` 或 `Rope` 数据结构，支持大规模文本实时编辑。
*   **键盘焦点流转**：建立基于编译期推导的焦点链（Focus Chain）。

### Phase 4.0 — 离屏合成与矢量路径扩展 (长期愿景)
*   **离屏纹理缓存**：实现真正的“局部重绘”，静态图层零开销。
*   **GPU 矢量路径**：引入基于 Compute Shader 的路径光栅化模板，支持任意复杂的矢量图形。

---

## 3. 核心设计哲学对齐

| 维度 | 行业标杆 (Zed/Vello) | Nebula 演进方向 |
| :--- | :--- | :--- |
| **执行时机** | 运行时高度动态 | **编译期极致预处理 (Lua Macros)** |
| **内存策略** | 运行时 Arena | **编译期静态布局 + 运行时 Arena** |
| **渲染后端** | WebGPU / Vulkan | **WebGPU (WGPU-Native)** |
| **核心优势** | 响应式、动态性 | **零成本抽象、极小二进制、编译期安全** |

---

## 4. 参考文献
- [1] Zed GPUI Documentation: "The Architecture of a High-Performance UI Framework."
- [2] Raph Levien. "Vello: High-performance 2D graphics on GPU."
- [3] Nelua Language Reference: "Pre-processing and Meta-programming."
