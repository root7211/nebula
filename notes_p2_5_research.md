# Phase 2.5 技术调研笔记

## 1. WebGPU 多 Pass 渲染核心模式

### 离屏纹理 (Offscreen Texture)
- 第一个 Pass 渲染到离屏纹理（RenderAttachment + TextureBinding usage）
- 后续 Pass 将离屏纹理作为 sampled texture 绑定到 bind group
- 最终 Pass 渲染到 surface 的 swap chain texture

### 关键 WGPU 资源
- 离屏 Texture: `WGPUTextureDescriptor` with `RenderAttachment | TextureBinding`
- TextureView: 从离屏 texture 创建
- Sampler: 线性或最近邻采样
- BindGroupLayout: 需要额外的 texture + sampler entries（当前只有 uniform buffer）

## 2. UI 阴影实现方案对比

### 方案 A: SDF 解析阴影（单 Pass，推荐用于 Phase 2.5 起步）
- **原理**: 利用已有的 SDF 距离函数，在 fragment shader 中直接计算阴影
- **实现**: 在主 fragment shader 中，先用偏移后的坐标计算一个"模糊化"的 SDF 值作为阴影 alpha
- **模糊近似**: `shadow_alpha = 1.0 - smoothstep(-blur, blur, sdf(p - offset, half_size))`
- **优点**: 零额外 Pass，零额外纹理，完全在现有单 Pass 架构内完成
- **缺点**: 模糊效果是近似的（非真正高斯模糊），大 blur radius 时边缘不够柔和
- **适用场景**: CSS box-shadow 风格的 UI 阴影（blur ≤ 20px）

### 方案 B: 两 Pass 可分离高斯模糊（真正的高斯模糊）
- **原理**: 2D 高斯核可分解为两个 1D 核（水平 + 垂直）
- **Pass 1**: 渲染组件到离屏纹理 → 水平模糊
- **Pass 2**: 水平模糊结果 → 垂直模糊 → 输出到 surface
- **优点**: 真正的高斯模糊，视觉质量最高
- **缺点**: 需要 2 个额外 Pass + 2 个离屏纹理（ping-pong）+ sampler + 新的 BindGroupLayout
- **复杂度**: 架构改动大，pipeline_factory 需要支持多 sub-pipeline

### 方案 C: 单 Pass 近似高斯模糊（Kawase blur）
- **原理**: 使用多次降采样/升采样近似高斯模糊
- **适用**: 大面积背景模糊（如 iOS 毛玻璃效果）
- **Phase 2.5 暂不考虑**

## 3. 推荐的 Phase 2.5 分阶段策略

### Phase 2.5.1: SDF 解析阴影（单 Pass）
- 在 shader_compose.lua 中新增 shadow 片段
- 新增 Visual 字段: shadow_color, shadow_offset, shadow_blur
- 在 fs_main 中先绘制阴影层，再绘制主体
- 不改变管线架构，只扩展着色器组合器

### Phase 2.5.2: 离屏渲染基础设施
- 在 renderer.nelua 中新增 nebula_offscreen_pass_init()
- 支持创建离屏纹理 + TextureView + Sampler
- 扩展 BindGroupLayout 支持 texture + sampler binding

### Phase 2.5.3: 可分离高斯模糊 Pass
- 在 shader_compose.lua 中新增 blur_h / blur_v 着色器
- 在 pipeline_factory.lua 中支持多 sub-pipeline
- <T>Pipeline 扩展为支持 shadow_pass + main_pass

### Phase 2.5.4: 集成与验收
- 新增 shadow_demo.nelua
- 迁移 button_demo 添加阴影
- headless_test 回归

## 4. 当前架构约束

### shader_compose.lua
- 只支持单 Pass，`required_passes = {"main"}`
- 需要扩展为 `{"shadow_blur", "main"}` 或 `{"main"}` + shadow 内联

### pipeline_factory.lua
- 每个 <T>Pipeline 只有一个 WGPURenderPipeline + 一个 uniform buffer + 一个 bind group
- 多 Pass 需要: 多个 pipeline、离屏 texture、sampler、额外 bind group

### nebula_pipeline_base_init
- 当前只支持单个 uniform binding
- 多 Pass 需要额外的 texture + sampler binding entries

### nebula_gen_uniform_layout
- 需要支持新字段类型（shadow_color: Color, shadow_offset: Vec2, shadow_blur: float32）
- 这些字段已在 PLAN_PHASE2.md 中预定义
