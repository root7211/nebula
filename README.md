# Nebula GUI Compiler — Phase 3.2.5 已合入
> 当前仓库的**主线能力**已完成到 **Phase 2.5**。与此同时，**Phase 3.1（静态布局）、Phase 3.2.1（字体预处理）、Phase 3.2.2（纹理与顶点缓冲区基础设施）、Phase 3.2.3（文本着色器组合器）、Phase 3.2.4（TextVisual 派生与运行时文本更新）与 Phase 3.2.5（演示完善与全面回归测试）已合入仓库**。文本渲染子系统现已通过多字号、多颜色、动态更新和 ASCII 全范围覆盖的验证。

---

## 各阶段演进（主线到 Phase 2.5，布局与文本子系统进入 Phase 3）

| 项目 | Phase 0-2.5 | Phase 3.1 | Phase 3.2.1 | Phase 3.2.2 | Phase 3.2.3 | Phase 3.2.4 | Phase 3.2.5 |
|---|---|---|---|---|---|---|---|
| 核心推导 | 形状 → 状态机/管线 | **静态 Flexbox 布局** | **SDF 文本预处理工具链** | **纹理与顶点缓冲区基础设施** | **文本着色器组合器** | **TextVisual 派生与运行时文本更新** | **演示完善与全面回归测试** |
| 渲染技术 | SDF 形状 + 多 Pass 阴影 | 布局对齐 | **GPU SDF 文本准备 (stb_truetype)** | **WGPUTexture & WGPUBuffer** | **SDF 采样渲染** | **动态文本网格生成与上传** | **多字号/多颜色/动态帧计数器** |
| 质量保障 | 手动验证 | 同左 | 度量验证工具 | 同左 | 冒烟测试 | text_demo | **31 项 Lua 断言 + 11 项编译回归** |

---

## 项目结构

```text
nebula/
├── src/
│   ├── nebula_core.nelua      # 编译期推导引擎
│   ├── stb_truetype_bindings.nelua # Phase 3.2.1: stb_truetype 的 Nelua FFI 绑定
│   ├── text_runtime.nelua     # Phase 3.2.4: 文本运行时模块，字形顶点装配与网格上传
│   ├── derive/
│   │   ├── layout_engine.lua      # Phase 3.1: 编译期静态 Flexbox 布局引擎
│   │   ├── shader_compose.lua     # Phase 3.2.3: 文本着色器组合器
│   │   ├── pipeline_factory.lua   # Phase 3.2.4: 管线工厂（含纹理+顶点路径）
│   │   └── ... (其他派生模块)
│   └── ...
├── assets/
│   └── generated/             # Phase 3.2.1: 自动生成的字体 SDF 图集与度量文件
├── tools/
│   ├── font_preprocessor.nelua # Phase 3.2.1: 字体预处理工具（TTF -> SDF Atlas）
│   ├── test_generated_metrics.nelua    # 字体资产验证工具
│   ├── smoke_phase3_2_2.lua    # Phase 3.2.2: 管线工厂纹理路径冒烟测试
│   ├── smoke_phase3_2_3.lua    # Phase 3.2.3: 文本着色器组合器冒烟测试
│   ├── smoke_phase3_2_4.lua    # ★ Phase 3.2.5: TextVisual 派生引擎冒烟测试（31 项断言）
│   ├── verify_p2_4.lua         # Phase 2.4: 交互原语工厂验证
│   ├── run_all_tests.sh        # ★ Phase 3.2.5: 全量回归测试运行器（11 项测试）
│   └── ...
├── examples/
│   ├── layout_demo.nelua      # Phase 3.1: 布局演示
│   ├── text_demo.nelua        # ★ Phase 3.2.5: 文本渲染完整展示（7 个文本组件）
│   └── ...
├── build.sh                   # 一键构建脚本
└── README.md
```

---

## ★ Phase 3.2.5 核心：演示完善与全面回归测试

Phase 3.2.5 是文本渲染子系统的质量收尾阶段。在 Phase 3.2.4 建立了 `TextVisual` 派生机制的基础上，本阶段通过丰富的演示场景和自动化测试套件，确保整个文本管线在各种边缘情况下的稳定性。

### text_demo 展示内容

`text_demo` 已从 Phase 3.2.4 的简单双行展示升级为包含 **7 个文本组件** 的综合展示：

| 组件 | 字号 | 颜色 | 用途 |
|---|---|---|---|
| 标题 | 48px | 白色 | 大字号 SDF 清晰度验证 |
| 副标题 | 28px | 蓝色 | 中等字号与颜色区分 |
| 正文（4 行） | 20px | 绿色 | 多行换行（`\n`）与行高计算验证 |
| ASCII 符号 | 16px | 橙色 | 全 ASCII 范围覆盖（`!@#$%^&*` 等） |
| 小字号 | 14px | 灰色 | SDF 在极小字号下的清晰度极限 |
| 帧计数器 | 24px | 白色 | **动态文本更新**（每秒刷新） |
| 大字号 | 64px | 淡紫色 | 大字号 SDF 质量验证 |

### 回归测试套件

Phase 3.2.5 引入了 `tools/run_all_tests.sh` 自动化回归测试运行器，覆盖两大类测试：

**Part 1: Lua 冒烟测试（编译期逻辑验证）**
- `smoke_phase3_2_2.lua` — 管线工厂纹理+顶点路径
- `smoke_phase3_2_3.lua` — 文本着色器 SDF 管线
- `smoke_phase3_2_4.lua` — TextVisual 派生引擎完整链路（**31 项断言**）
- `verify_p2_4.lua` — 交互原语工厂

**Part 2: 编译回归测试（Nelua → C → 二进制）**
- `text_demo` (Phase 3.2.5)、`button_demo` (Phase 2.4)、`login_demo` (Phase 2.4)
- `simple_rect_demo` (Phase 2.4)、`shadow_demo` (Phase 2.5)、`layout_demo` (Phase 3.1)
- `uniform_layout_test` (Phase 2.1)

运行方式：
```bash
bash tools/run_all_tests.sh
```

---

## Phase 3.2.1 核心：SDF 字体预处理管道

Phase 3.2.1 引入了高性能文本渲染的基础设施。通过 `stb_truetype` 引擎，我们将标准矢量字体（TTF）转换为 GPU 友好的有向距离场（SDF）纹理。

### 关键特性
- **自动化工具链**：提供 `tools/font_preprocessor.nelua`，一键生成字体资产。
- **SDF 渲染准备**：生成 48px 基准的 SDF 图集，支持高质量的文本缩放与抗锯齿。
- **强类型度量**：生成的 `.nelua` 度量文件包含字符的 Advance、Offset 和 UV 坐标，可直接参与编译期布局计算。

### 使用字体预处理工具

如果你需要使用自定义字体，可以运行：

```bash
# 生成 SDF 图集和度量文件
nelua tools/font_preprocessor.nelua
```

验证生成的资产：
```bash
nelua tools/test_generated_metrics.nelua
```

---

## Phase 3.2.2 核心：纹理与顶点缓冲区基础设施

Phase 3.2.2 建立了 GPU 纹理上传和顶点缓冲区管理的基础。这使得 Nebula 能够从纯几何 SDF 渲染扩展到支持基于顶点数据的渲染，为文本和未来更复杂的 UI 元素打下基础。

### 关键特性
- **通用纹理上传**：`renderer.nelua` 中新增 `nebula_upload_texture`，支持 CPU 像素数据到 WGPUTexture 的高效传输。
- **管线工厂扩展**：`pipeline_factory.lua` 现已支持生成带有 TextureView 和 Sampler 的 BindGroup 布局，以及支持 Position 和 UV 顶点属性输入的 RenderPipeline。
- **缓冲区管理**：引入了缓冲区释放机制，以支持动态顶点数据的更新和回收。

---

## Phase 3.2.3 核心：文本着色器组合器

Phase 3.2.3 实现了专门用于 SDF 文本渲染的着色器组合器。它利用 Phase 3.2.2 提供的纹理与顶点缓冲区基础设施，将字体图集和文本几何数据转化为屏幕上的清晰字符。

### 关键特性
- **SDF 文本模板**：`shader_compose.lua` 中新增文本专属模板，用于生成高效的顶点和片段着色器。
- **顶点着色器**：处理输入的 Position 和 UV 坐标，计算字形在屏幕上的最终位置。
- **片段着色器**：执行 SDF 阈值测试和基于 `fwidth` 的抗锯齿处理，确保文本在不同缩放级别下保持平滑。

---

## Phase 3.2.4 核心：TextVisual 派生与运行时文本更新

Phase 3.2.4 引入了 `TextVisual` 派生机制，使得开发者能够以声明式的方式定义文本组件，并在运行时动态更新其内容。这是实现交互式文本显示和编辑的关键一步。

### 关键特性
- **`TextVisual` 派生**：通过 `nebula_derive` 宏，自动为 `TextVisual` 结构体生成文本渲染所需的初始化、更新和数据转换逻辑。
- **运行时文本更新**：`TextContext:set_text(renderer, text_string)` 接口允许在应用程序运行时动态改变文本内容，并自动更新底层顶点缓冲区。
- **字形顶点装配**：`text_runtime.nelua` 模块负责根据字体度量数据和输入字符串，将每个字符转换为渲染所需的 Position 和 UV 顶点数据。

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
./build.sh text_demo         # ★ Phase 3.2.5 文本渲染完整展示
```

### 运行回归测试

```bash
bash tools/run_all_tests.sh  # 运行全部 11 项测试
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
- [x] **Phase 3.2.5** — 演示完善与全面回归测试。
- [ ] **Phase 3.3** — 运行时动态列表与实例渲染。
