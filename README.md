# Nebula GUI Compiler — Phase 3.2.1 已合入
> 当前仓库的**主线能力**已完成到 **Phase 2.5**。与此同时，**Phase 3.1（静态布局）与 Phase 3.2.1（字体预处理）已合入仓库**。开发者现在可以利用内置工具链生成自定义字体的 GPU SDF 资产。

---

## 各阶段演进（主线到 Phase 2.5，布局与文本子系统进入 Phase 3）

| 项目 | Phase 0-2.5 | Phase 3.1 | Phase 3.2.1 |
|---|---|---|---|
| 核心推导 | 形状 → 状态机/管线 | **静态 Flexbox 布局** | **SDF 文本预处理工具链** |
| 渲染技术 | SDF 形状 + 多 Pass 阴影 | 布局对齐 | **GPU SDF 文本准备 (stb_truetype)** |
| 资产管理 | 纯代码声明 | 同左 | **`.ttf` → `.pgm` (SDF Atlas) + `.nelua` (Metrics)** |

---

## 项目结构

```text
nebula/
├── src/
│   ├── nebula_core.nelua      # 编译期推导引擎
│   ├── stb_truetype_bindings.nelua # ★ Phase 3.2.1: stb_truetype 的 Nelua FFI 绑定
│   ├── derive/
│   │   ├── layout_engine.lua      # Phase 3.1: 编译期静态 Flexbox 布局引擎
│   │   └── ... (其他派生模块)
│   └── ...
├── assets/
│   └── generated/             # ★ Phase 3.2.1: 自动生成的字体 SDF 图集与度量文件
├── tools/
│   ├── font_preprocessor.nelua # ★ Phase 3.2.1: 字体预处理工具（TTF -> SDF Atlas）
│   ├── gen_stb_truetype_bindings.nelua # 绑定生成脚本
│   ├── test_generated_metrics.nelua    # 字体资产验证工具
│   └── ...
├── examples/
│   ├── layout_demo.nelua      # Phase 3.1: 布局演示
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
```

---

## 阶段状态汇总

### Phase 2 主线进度 (Completed)
- [x] **Phase 2.1 - 2.5** — 自动对齐、着色器组合、管线工厂、交互原语、多 Pass 阴影。

### Phase 3 子阶段进度 (In Progress)
- [x] **Phase 3.1** — 编译期静态 Flexbox 布局系统。
- [x] **Phase 3.2.1** — 字体预处理工具链与 SDF 生成。
- [ ] **Phase 3.2.2** — GPU 纹理上传与文本顶点缓冲区基础设施。
- [ ] **Phase 3.2.3** — 文本着色器合成器（SDF 采样渲染）。
- [ ] **Phase 3.2.4** — `TextVisual` 派生与 `text_demo` 演示。
- [ ] **Phase 3.3** — 运行时动态列表与实例渲染。
