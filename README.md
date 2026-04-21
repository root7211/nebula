# Nebula GUI Compiler — Phase 3.2.4 已合入
> 当前仓库的**主线能力**已完成到 **Phase 2.5**。与此同时，**Phase 3.1（静态布局）、Phase 3.2.1（字体预处理）、Phase 3.2.2（纹理与顶点缓冲区基础设施）、Phase 3.2.3（文本着色器组合器）与 Phase 3.2.4（TextVisual 派生与运行时文本更新）已合入仓库**。开发者现在可以利用内置工具链生成自定义字体的 GPU SDF 资产，并使用 `TextVisual` 进行运行时文本渲染。

---

## 各阶段演进（主线到 Phase 2.5，布局与文本子系统进入 Phase 3）

| 项目 | Phase 0-2.5 | Phase 3.1 | Phase 3.2.1 | Phase 3.2.2 | Phase 3.2.3 | Phase 3.2.4 |
|---|---|---|---|---|---|---|
| 核心推导 | 形状 → 状态机/管线 | **静态 Flexbox 布局** | **SDF 文本预处理工具链** | **纹理与顶点缓冲区基础设施** | **文本着色器组合器** | **TextVisual 派生与运行时文本更新** |
| 渲染技术 | SDF 形状 + 多 Pass 阴影 | 布局对齐 | **GPU SDF 文本准备 (stb_truetype)** | **WGPUTexture & WGPUBuffer** | **SDF 采样渲染** | **动态文本网格生成与上传** |
| 资产管理 | 纯代码声明 | 同左 | **`.ttf` → `.pgm` (SDF Atlas) + `.nelua` (Metrics)** | 同左 | 同左 | **运行时文本字符串 → 顶点数据** |

---

## 项目结构

```text
nebula/
├── src/
│   ├── nebula_core.nelua      # 编译期推导引擎
│   ├── stb_truetype_bindings.nelua # ★ Phase 3.2.1: stb_truetype 的 Nelua FFI 绑定
│   ├── text_runtime.nelua     # ★ Phase 3.2.4: 文本运行时模块，字形顶点装配与网格上传
│   ├── derive/
│   │   ├── layout_engine.lua      # Phase 3.1: 编译期静态 Flexbox 布局引擎
│   │   ├── shader_compose.lua     # ★ Phase 3.2.3: 文本着色器组合器
│   │   └── ... (其他派生模块)
│   └── ...
├── assets/
│   └── generated/             # ★ Phase 3.2.1: 自动生成的字体 SDF 图集与度量文件
├── tools/
│   ├── font_preprocessor.nelua # ★ Phase 3.2.1: 字体预处理工具（TTF -> SDF Atlas）
│   ├── gen_stb_truetype_bindings.nelua # 绑定生成脚本
│   ├── test_generated_metrics.nelua    # 字体资产验证工具
│   ├── smoke_phase3_2_3.lua    # ★ Phase 3.2.3: 文本着色器组合器冒烟测试
│   └── ...
├── examples/
│   ├── layout_demo.nelua      # Phase 3.1: 布局演示
│   ├── text_demo.nelua        # ★ Phase 3.2.4: 文本渲染演示
│   └── ...
├── build.sh                   # 一键构建脚本
└── README.md
```

---

## ★ Phase 3.2.1 核心：SDF 字体预处理管道

Phase 3.2.1 引入了高性能文本渲染的基础设施。通过 `stb_truetype` 引擎，我们将标准矢量字体（TTF）转换为 GPU 友好的有向距离场（SDF）纹理。

### 关键特性
- **自动化工具链**：提供 `tools/font_preprocessor.nelua`，一键生成字体资产。
- **SDF 渲染准备**：生成 48px 基准的 SDF 图集，支持高质量的文本缩放与抗锯齿。
- **强类型度量**：生成的 `.nelua` 度量文件包含字符的 Advance、Offset 和 UV 坐标，可直接参与编译期布局计算。

### 使用字体预处理工具

如果你需要使用自定义字体，可以运行：

```bash
# 生成 SDF 图集和度量文件
# 默认输入路径: assets/fonts/LiberationSans-Regular.ttf
# 默认输出路径: assets/generated/
nelua tools/font_preprocessor.nelua
```

验证生成的资产：
```bash
nelua tools/test_generated_metrics.nelua
```

---

## ★ Phase 3.2.2 核心：纹理与顶点缓冲区基础设施

Phase 3.2.2 建立了 GPU 纹理上传和顶点缓冲区管理的基础。这使得 Nebula 能够从纯几何 SDF 渲染扩展到支持基于顶点数据的渲染，为文本和未来更复杂的 UI 元素打下基础。

### 关键特性
- **通用纹理上传**：`renderer.nelua` 中新增 `nebula_upload_texture`，支持 CPU 像素数据到 WGPUTexture 的高效传输。
- **管线工厂扩展**：`pipeline_factory.lua` 现已支持生成带有 TextureView 和 Sampler 的 BindGroup 布局，以及支持 Position 和 UV 顶点属性输入的 RenderPipeline。
- **缓冲区管理**：引入了缓冲区释放机制，以支持动态顶点数据的更新和回收。

---

## ★ Phase 3.2.3 核心：文本着色器组合器

Phase 3.2.3 实现了专门用于 SDF 文本渲染的着色器组合器。它利用 Phase 3.2.2 提供的纹理与顶点缓冲区基础设施，将字体图集和文本几何数据转化为屏幕上的清晰字符。

### 关键特性
- **SDF 文本模板**：`shader_compose.lua` 中新增文本专属模板，用于生成高效的顶点和片段着色器。
- **顶点着色器**：处理输入的 Position 和 UV 坐标，计算字形在屏幕上的最终位置。
- **片段着色器**：执行 SDF 阈值测试和基于 `fwidth` 的抗锯齿处理，确保文本在不同缩放级别下保持平滑。

---

## ★ Phase 3.2.4 核心：TextVisual 派生与运行时文本更新

Phase 3.2.4 引入了 `TextVisual` 派生机制，使得开发者能够以声明式的方式定义文本组件，并在运行时动态更新其内容。这是实现交互式文本显示和编辑的关键一步。

### 关键特性
- **`TextVisual` 派生**：通过 `nebula_derive` 宏，自动为 `TextVisual` 结构体生成文本渲染所需的初始化、更新和数据转换逻辑。
- **运行时文本更新**：`TextContext:set_text(renderer, text_string)` 接口允许在应用程序运行时动态改变文本内容，并自动更新底层顶点缓冲区。
- **字形顶点装配**：`text_runtime.nelua` 模块负责根据字体度量数据和输入字符串，将每个字符转换为渲染所需的 Position 和 UV 顶点数据。
- **`text_demo` 示例**：提供了一个完整的演示，展示了 `TextVisual` 的初始化、字体图集绑定、动态文本更新和渲染。

---

## 构建与运行

### 环境要求

- Linux x86_64 / WSL2
- Nelua 0.2.0-dev
- GCC 11+
- **stb_truetype**: (已包含在 `src/` 绑定中，无需额外安装)
- **wgpu-native v29.0.0.0**: 需放置在 `vendor/wgpu-native`

### 编译与运行

```bash
chmod +x build.sh
./build.sh shadow_demo       # Phase 2.5 阴影演示
./build.sh layout_demo       # Phase 3.1 布局演示
./build.sh text_demo        # ★ Phase 3.2.4 文本渲染演示
```

---

## 阶段状态汇总

### Phase 2 主线进度 (Completed)
- [x] **Phase 2.1 - 2.5** — 自动对齐、着色器组合、管线工厂、交互原语、多 Pass 阴影。

### Phase 3 子阶段进度 (In Progress)
- [x] **Phase 3.1** — 编译期静态 Flexbox 布局系统。
- [x] **Phase 3.2.1** — 字体预处理工具链与 SDF 生成。
- [x] **Phase 3.2.2** — GPU 纹理上传与文本顶点缓冲区基础设施。
- [x] **Phase 3.2.3** — 文本着色器合成器（SDF 采样渲染）。
- [x] **Phase 3.2.4** — `TextVisual` 派生与 `text_demo` 演示。
- [ ] **Phase 3.2.5** — 演示与回归测试（已部分包含在 3.2.4 的 `text_demo` 中，但仍需独立完善）。
- [ ] **Phase 3.3** — 运行时动态列表与实例渲染。
