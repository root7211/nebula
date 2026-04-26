# Phase 4.1 实施方案：Slug 文本渲染引擎

**目标**：引入 Slug 算法，实现无纹理的纯数学矢量文本渲染，彻底解决 Unicode 全量支持问题，同时严格遵守公理 A（阶段封闭性）。

## 1. 架构背景与张力

当前 Nebula 使用基于 SDF（Signed Distance Field）的图集（Atlas）进行文本渲染。这种方案在 ASCII 字符集下表现良好，但面对包含数万个字形的 CJK（中日韩）字符集时，预计算的 SDF 图集会变得极其庞大（数百 MB），不仅占用大量显存，而且在极端缩放时仍可能出现伪影。

为了兑现“不违反公理 A 的 Unicode 全量支持”的承诺，我们需要一种不需要预计算光栅化图集的方案。2026 年 3 月进入公共领域的 **Slug 算法**（Eric Lengyel）完美契合了这一需求。Slug 直接在 GPU 上从贝塞尔曲线控制点计算像素覆盖率，其“字形渲染”被优雅地分解为“数据提取”（S0 阶段）和“像素计算”（S2 阶段），中间没有任何运行时的光栅化或图集管理。

## 2. 实施路径

### 2.1 S0 阶段：扩展 `font_preprocessor.nelua`

在预处理阶段，我们需要从 TTF 字体文件中提取贝塞尔曲线数据，而不是生成 SDF 位图。

- **新增命令行选项**：为 `font_preprocessor.nelua` 添加 `--mode=slug` 选项。
- **数据提取**：使用 `stb_truetype` 或直接解析 TTF 表，提取每个字形的二次贝塞尔曲线控制点。
- **数据打包**：按照 Slug 算法的要求，将曲线数据打包为 `curve_data` 和 `band_data`。
- **输出生成**：生成 `curve_data.nelua` 和 `band_data.nelua` 文件，这些文件将作为编译期常量在 S1 阶段被包含。

### 2.2 S1 阶段：着色器与管线生成

在编译阶段，我们需要生成支持 Slug 算法的 WebGPU 管线和着色器。

- **着色器组合**：在 `src/derive/shader_compose.lua` 中新增 `nebula_compose_slug_shader` 函数。该函数负责将 Slug 的参考 HLSL 实现翻译为 WGSL，并将 S0 阶段生成的 `curve_data` 和 `band_data` 绑定为 Storage Buffer 或只读纹理。
- **管线工厂**：在 `src/derive/pipeline_factory.lua` 中新增 `gen_pipeline_slug_text` 路径。该路径负责创建包含 Slug 所需 Bind Group Layout 的 WebGPU 管线。
- **配置开关**：在 `nebula_annotate` 中保留 `text_mode = "ascii_sdf"` 作为轻量级后备路径，新增 `text_mode = "slug"` 作为默认的高质量 Unicode 路径。

### 2.3 S2 阶段：运行时渲染

在运行阶段，GPU 将直接根据曲线数据计算像素覆盖率。

- **顶点装配**：`text_runtime.nelua` 需要更新，以支持向 GPU 传递 Slug 算法所需的每个字符的边界框（Bounding Box）和曲线数据索引。
- **渲染提交**：CPU 侧的渲染提交逻辑基本保持不变，依然是绑定 Pipeline 和 Bind Group，然后发出 Draw Call。核心的计算工作完全卸载到了 GPU 的 Fragment Shader 中。

## 3. 验收标准

1. **功能正确性**：能够正确渲染包含复杂曲线的 CJK 字符，且在任意缩放级别下无锯齿、无伪影。
2. **公理合规性**：整个流程严格遵守公理 A，S2 阶段没有任何字体解析或光栅化操作。
3. **性能指标**：渲染 10,000 个中文字符的帧率不低于 60 FPS，且显存占用显著低于等效的 SDF 图集方案。
4. **向后兼容**：原有的 `ascii_sdf` 模式依然可用，且相关测试用例全部通过。
