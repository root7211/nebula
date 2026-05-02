# Phase 4.X 实施方案 v2：高密度文本渲染通道

**创建日期**：2026-04-29
**v2 修订日期**：2026-04-30
**v2 实施完成**：2026-05-02
**前置依赖**：Phase 4.4 S3（multiline_editable 已完成）
**状态**：✅ 全部实施完成（Step 1-5 + demo + 65 条冒烟测试 + 编译回归 | 49/49 回归全绿）

**v2 修订摘要**：
- 删除 S2（输入系统补全）— 剪贴板 API、Unicode 字符输入、Ctrl+C/V/X/A 已在缺口 #5/#6 清算中实现
- 删除 resize 通知 — Phase 3.12 已实现（`viewport_resized`）
- 重新设计顶点格式：RGBA8 压缩颜色替代 Vec4（64B→40B/vertex）
- 新增方案 B：Instanced 路径评估（复用 standard_instanced 基础设施）
- 明确 scope：仅等宽网格文本，变宽富文本留给后续 Phase
- D-4.1-C 风险声明

---

## 0. Scope 界定

本 Phase **仅解决一个问题**：Nebula 缺少高容量 + per-char 颜色的文本渲染通道。

**在 scope 内**：
- 等宽字符网格（终端、日志查看器、数据表格）
- max_chars 参数化至 8192
- Per-character 前景色 + 背景色
- L0/L1 GPU buffer（替代栈分配）
- UAX#14 换行算法（从 PLAN_PHASE4_2_3_CJK.md 移入，文本编辑器硬依赖）

**不在 scope 内**：
- 变宽富文本排版（Phase 4.2.3 HarfBuzz 的职责）
- Latin 连字（Tier 2，推迟到 Phase 5+，装饰性功能不影响核心流程）
- PTY / ANSI 解析（终端应用层代码）
- IME 预编辑（未来 Phase）
- 输入系统补全（已完成：缺口 #5/#6）

---

## 1. 现状分析

### 1.1 三条已有文本管线

| 路径 | spec 标志 | vertex 格式 | 字节/vertex | 适用场景 | 代码位置 |
|:-----|:----------|:------------|:-----------|:---------|:---------|
| SDF atlas | `textured=true` | NebulaPosUvVertex (pos+uv) | 16B | 按钮标签 | pipeline_factory.lua:50 |
| Slug 矢量 | `slug_text=true` | NebulaSlugVertex (5×Vec4) | 80B | 高质量文本 | pipeline_factory.lua:707 |
| **standard_instanced** | `standard_instanced=true` | 无 vertex buffer（程序化） | 0B | UI 组件 | pipeline_factory.lua:483 |

### 1.2 关键限制

1. **容量**：SDF 路径栈分配 `[max_chars×6]NebulaPosUvVertex`，默认 max_chars=256（24KB 栈），4000 字符需要 384KB 栈帧，不可行。
2. **颜色**：SDF 路径的颜色来自 uniform 全局色（`u.text_color`），无 per-char 颜色。Slug 路径 vertex attr4 带颜色但也是全局的。
3. **绘制模型**：SDF 用 per-vertex 三角形列表（6 vertices/char），instanced 路径用程序化顶点 + Storage Buffer。

### 1.3 Standard Instanced 路径的启示

standard_instanced 路径（pipeline_factory.lua:483-700）为高密度文本提供了一个成熟的参考模式：

- **零 vertex buffer**：vertex shader 用 `instance_index` + `vertex_index` 程序化生成 6 顶点
- **Storage Buffer**：per-instance 数据通过 `storage<read>` 传递（binding 1）
- **批量上传**：`upload(renderer, data, count)` 一次写入所有实例数据
- **已验证**：所有标准 UI 组件都走此路径，max_instances=128 在生产中稳定运行

---

## 2. 方案选择：Per-Vertex vs Instanced

### 方案 A：Per-Vertex 三角形列表（原方案）

每字符 6 个顶点，颜色在 vertex attribute 中。

```
NebulaDenseCharVertex = @record{
  position: Vec2,      -- 8B
  uv:       Vec2,      -- 8B
  fg_color: [4]uint8,  -- 4B (RGBA8 unorm)
  bg_color: [4]uint8,  -- 4B (RGBA8 unorm)
}
-- 24 bytes/vertex × 6 vertices/char = 144 bytes/char
-- 8192 chars = 1.125 MB vertex buffer
```

**优点**：
- 实现简单，CPU 端逐字符填入 vertex array
- 不依赖 Storage Buffer（规避 D-4.1-C 风险——注：D-4.1-C 已通过，此风险不再成立）

**缺点**：
- 每字符 6 顶点存在大量冗余（同一字符的 6 个顶点共享 fg/bg color）
- 8192 字符 = 49152 顶点 × 24B = 1.125 MB CPU→GPU 传输/帧（若文本变化）
- vertex buffer 大对象需要 L0 或 L1 管理

### 方案 B：Instanced 路径（推荐）

复用 standard_instanced 基础设施的设计模式。每字符一个 instance，per-instance 数据通过 Storage Buffer 传递。Vertex shader 程序化生成单位 quad。

```
DenseCharInstance = @record{
  pos_x:     float32,   -- 4B  字符左上角 X（像素）
  pos_y:     float32,   -- 4B  字符左上角 Y（像素）
  uv_x:      float32,   -- 4B  atlas 纹理 U 起点
  uv_y:      float32,   -- 4B  atlas 纹理 V 起点
  uv_w:      float32,   -- 4B  atlas 纹理 U 宽度
  uv_h:      float32,   -- 4B  atlas 纹理 V 高度
  fg_color:  uint32,    -- 4B  RGBA8 packed
  bg_color:  uint32,    -- 4B  RGBA8 packed
}
-- 32 bytes/instance
-- 8192 chars = 256 KB Storage Buffer
```

**优点**：
- 零 vertex buffer（与 standard_instanced 一致）
- 每字符仅 32B（vs per-vertex 方案的 144B）
- 8192 字符 = 256 KB Storage Buffer（vs 1.125 MB vertex buffer）
- GPU 端 warp 效率更高（vertex shader 只有 6 次简单计算/instance）
- 与 Nebula 现有架构一致（公理 C：管线签名在 S1 确定）

**缺点**：
- 依赖 Storage Buffer 性能（D-4.1-C 未验证）
- 如果 D-4.1-C 在 10000 字符规模下退化 ≥ 20%，需要回退到方案 A

### 决策

**选择方案 B（Instanced）**，理由：
1. 与 Nebula 的核心架构（standard_instanced）一致
2. 内存效率高 4.4 倍
3. 代码复用度高（pipeline_factory 的 instanced 生成逻辑可直接参考）
4. 如果 D-4.1-C 结果不利，回退到方案 A 的改动范围可控（仅 vertex shader + upload 函数）

---

## 3. 实施路径

### 3.1 着色器：`nebula_compose_dense_text_shader(opts)`

位置：`shader_compose.lua`（新增函数）

```wgsl
// Uniforms — 极简：只有 viewport + cell_size
struct DenseTextUniforms {
  viewport: vec2<f32>,
  cell_w:   f32,        // 等宽字符宽度（像素）
  cell_h:   f32,        // 等宽字符高度（像素）
}
@group(0) @binding(0) var<uniform> u: DenseTextUniforms;

// Per-instance 数据通过 Storage Buffer
struct DenseCharInstance {
  pos_x:    f32,
  pos_y:    f32,
  uv_x:    f32,
  uv_y:    f32,
  uv_w:    f32,
  uv_h:    f32,
  fg_color: u32,    // RGBA8 packed
  bg_color: u32,    // RGBA8 packed
}
@group(0) @binding(1) var<storage, read> chars: array<DenseCharInstance>;
@group(0) @binding(2) var glyph_atlas:   texture_2d<f32>;
@group(0) @binding(3) var glyph_sampler: sampler;

struct VertexOutput {
  @builtin(position) clip_pos: vec4<f32>,
  @location(0) uv:       vec2<f32>,
  @location(1) fg_color: vec4<f32>,
  @location(2) bg_color: vec4<f32>,
}

@vertex
fn vs_main(
  @builtin(instance_index) inst: u32,
  @builtin(vertex_index)   vert: u32
) -> VertexOutput {
  let ch = chars[inst];

  // 6 vertices → unit quad (same pattern as standard_instanced)
  var corner_x: f32; var corner_y: f32;
  var uv_x: f32;     var uv_y: f32;
  switch (vert % 6u) {
    case 0u { corner_x = 0.0; corner_y = 0.0; uv_x = ch.uv_x;            uv_y = ch.uv_y; }
    case 1u { corner_x = 1.0; corner_y = 0.0; uv_x = ch.uv_x + ch.uv_w;  uv_y = ch.uv_y; }
    case 2u { corner_x = 0.0; corner_y = 1.0; uv_x = ch.uv_x;            uv_y = ch.uv_y + ch.uv_h; }
    case 3u { corner_x = 0.0; corner_y = 1.0; uv_x = ch.uv_x;            uv_y = ch.uv_y + ch.uv_h; }
    case 4u { corner_x = 1.0; corner_y = 0.0; uv_x = ch.uv_x + ch.uv_w;  uv_y = ch.uv_y; }
    case 5u { corner_x = 1.0; corner_y = 1.0; uv_x = ch.uv_x + ch.uv_w;  uv_y = ch.uv_y + ch.uv_h; }
    default { corner_x = 0.0; corner_y = 0.0; uv_x = 0.0; uv_y = 0.0; }
  }

  let pixel_x = ch.pos_x + corner_x * u.cell_w;
  let pixel_y = ch.pos_y + corner_y * u.cell_h;
  let ndc_x = (pixel_x / u.viewport.x) * 2.0 - 1.0;
  let ndc_y = 1.0 - (pixel_y / u.viewport.y) * 2.0;

  // Unpack RGBA8 → vec4<f32>
  let fg = unpack4x8unorm(ch.fg_color);
  let bg = unpack4x8unorm(ch.bg_color);

  var out: VertexOutput;
  out.clip_pos = vec4<f32>(ndc_x, ndc_y, 0.0, 1.0);
  out.uv       = vec2<f32>(uv_x, uv_y);
  out.fg_color = fg;
  out.bg_color = bg;
  return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let sdf = textureSample(glyph_atlas, glyph_sampler, in.uv).r;
  let width = fwidth(sdf);
  let alpha = smoothstep(0.5 - width, 0.5 + width, sdf);
  // 背景色 + 前景色按 SDF alpha 叠加
  return mix(in.bg_color, vec4<f32>(in.fg_color.rgb, 1.0), in.fg_color.a * alpha);
}
```

关键设计要点：
- **Uniforms 只有 16B**：viewport + cell_size。所有 per-char 数据在 Storage Buffer。
- **fg/bg 用 `u32` + `unpack4x8unorm`**：WGSL 内置函数，零额外开销，精度对 GUI 颜色足够。
- **vertex shader 程序化生成 quad**：与 standard_instanced 完全一致的模式。
- **fragment shader 做 bg+fg SDF 混合**：背景色填充 cell，前景色按字形 alpha 叠加。

### 3.2 管线代码生成：`gen_pipeline_dense_text()`

位置：`pipeline_factory.lua`（新增函数）

生成的 Nelua record 结构：

```
<Base>DenseTextPipeline = @record{
  pipeline:     WGPURenderPipeline,
  bind_layout:  WGPUBindGroupLayout,
  uniform_buf:  WGPUBuffer,      -- 16B: viewport + cell_size
  storage_buf:  WGPUBuffer,      -- max_chars × 32B
  storage_size: uint64,
  bind_group:   WGPUBindGroup,   -- binds uniform + storage + atlas + sampler
  char_count:   uint32,          -- 当前帧实际字符数
}
```

Bind Group Layout（4 entries）：

| binding | 类型 | visibility | 内容 |
|:--------|:-----|:-----------|:-----|
| 0 | uniform | vertex+fragment | DenseTextUniforms (16B) |
| 1 | storage<read> | vertex | array\<DenseCharInstance\> |
| 2 | texture_2d | fragment | glyph_atlas (SDF) |
| 3 | sampler | fragment | glyph_sampler |

生成的方法：

- `init(renderer, max_chars)` — 创建 pipeline + buffers + bind group
- `update_atlas_binding(renderer, tex_view, sampler)` — 绑定 SDF atlas 纹理
- `update_viewport(renderer, vw, vh, cell_w, cell_h)` — 更新 uniform buffer
- `upload(renderer, data: *[0]DenseCharInstance, count)` — 写入 Storage Buffer
- `draw(pass, count)` — `wgpuRenderPassEncoderDraw(pass, 6, count, 0, 0)`

在 `nebula_gen_pipeline_source(spec)` 分发链中新增：

```lua
elseif spec.atlas_dense then
  assert(spec.wgsl_source, "nebula_gen_pipeline_source: wgsl_source required for atlas_dense path")
  local max_chars = spec.max_chars or 4096
  return gen_pipeline_dense_text(spec.base, spec.wgsl_source, max_chars)
```

### 3.3 DenseTextContext 派生

位置：`nebula_core.nelua`（新增 `nebula_derive_dense_text_visual`）

与 `nebula_derive_text_visual` 并列，但关键差异：

| 维度 | 现有 TextContext | 新 DenseTextContext |
|:-----|:----------------|:-------------------|
| 调用方式 | `nebula_derive_text_visual("T")` | `nebula_derive_dense_text_visual("T")` |
| spec 标志 | `textured=true` | `atlas_dense=true` |
| 颜色模型 | uniform 全局色 | per-instance fg/bg |
| 容量 | max_chars=256（栈） | max_chars=4096+（L0 buffer） |
| set_text | `set_text(renderer, text)` | `set_cells(renderer, cells, count)` |
| 数据源 | cstring | `*[0]DenseCharInstance` |

`set_cells` 方法不做排版计算——调用方负责填充 `DenseCharInstance` 数组（pos, uv, fg, bg）。这保持了框架的通用性：终端应用用 cell grid 填充，代码编辑器用排版结果填充。

### 3.4 辅助运行时

位置：`text_runtime.nelua`（新增）

```nelua
-- 等宽网格辅助：根据 (row, col, codepoint) 填充 DenseCharInstance
global function nebula_dense_grid_fill_instance(
  inst:         *DenseCharInstance,
  row:          uint32,
  col:          uint32,
  codepoint:    uint32,
  origin_x:     float32,
  origin_y:     float32,
  cell_w:       float32,
  cell_h:       float32,
  fg_packed:    uint32,
  bg_packed:    uint32
): void
```

这是一个纯辅助函数，不强制使用。终端应用可以直接填充 `DenseCharInstance` 数组。

---

## 4. 公理合规性审查

### 公理 A（阶段封闭性）

| 操作 | 阶段 | 理由 |
|:-----|:-----|:-----|
| DenseCharInstance record 定义 | S1 | 类型在编译期确定 |
| DenseTextPipeline record 生成 | S1 | pipeline_factory 编译期展开 |
| WGSL 着色器组合 | S1 | shader_compose 编译期生成 |
| GPU buffer 创建 | S2 init | 大小由 S1 的 max_chars 确定 |
| Storage Buffer 写入 | S2 per-frame | 运行时数据 |
| SDF 采样 + 颜色混合 | S2 render | GPU 操作 |

**合规**：无 S1 操作泄漏到 S2，无 S2 操作拉回 S1。

### 公理 B（生命周期三层）

| 数据 | 层 | 创建 | 销毁 | 理由 |
|:-----|:---|:-----|:-----|:-----|
| SDF atlas 纹理 | L0 | init | deinit | 应用全生命周期 |
| pipeline + bind group | L0 | init | deinit | 编译期确定的管线签名 |
| Storage Buffer (256KB) | L0 | init | deinit | 大小编译期确定，内容每帧更新 |
| DenseCharInstance[] 数组 | L2 | 每帧 | arena.reset | CPU 端帧级临时数据 |
| Uniform buffer (16B) | L0 | init | deinit | viewport/cell_size |

**合规**：L0 数据不跨层引用 L2，L2 数据帧末销毁。

### 公理 C（形即渲染）

```
Σ(DenseTextVisual) = (
  VertexLayout:   无（程序化）,
  UniformsLayout: DenseTextUniforms (16B),
  ShaderModule:   dense_text_shader,
  BlendState:     AlphaBlend
)
```

所有四项在 S1 完全确定。与现有管线签名正交，不冲突。

---

## 5. D-4.1-C 风险状态（已消除）

~~方案 B 依赖 Storage Buffer 在 8192 instance 规模下的性能。~~

**D-4.1-C 已通过**（commit `ebd7333`）：Storage Buffer 在 1K→5K→10K 实例规模下退化仅 +2.5%，远低于 20% 阈值。方案 B（Instanced）无性能风险，可直接实施。详见 `REPORT_PHASE4_2_2_BENCH.md`。

---

## 6. 验收标准

1. ~~**容量**：`dense_text_demo` 渲染 120×50 = 6000 字符网格，每字符独立 fg/bg color。~~ ✅ 已实现
2. ~~**公理合规**：axiom_validator 对 DenseTextVisual 的管线签名审查通过。~~ ✅ smoke_phase4_x_dense.lua 65/65 通过
3. ~~**回归**：47/47 回归测试全绿 + 新增专项测试。~~ ✅ 49/49 全绿（含 2 项新增）
4. **性能基线**：记录 6000 字符帧时间，作为 D-4.1-C 数据点。（待 GPU 环境运行时验证）
5. ~~**API 简洁性**：应用层调用不超过 3 步：① 填充 DenseCharInstance 数组 ② upload ③ draw。~~ ✅ dense_text_demo 验证

---

## 7. 文件清单

| 文件 | 操作 | 内容 | 状态 |
|:-----|:-----|:-----|:-----|
| `src/derive/shader_compose.lua` | 修改 | 新增 `nebula_compose_dense_text_shader()` | ✅ Step 1 |
| `src/derive/pipeline_factory.lua` | 修改 | 新增 `gen_pipeline_dense_text()`，扩展分发链 | ✅ Step 2 |
| `src/renderer.nelua` | 修改 | 新增 `DenseCharInstance` record + `DenseTextUniforms` record | ✅ Step 3 |
| `src/nebula_core.nelua` | 修改 | 新增 `nebula_derive_dense_text_visual()` 派生入口 | ✅ Step 4 |
| `src/text_runtime.nelua` | 修改 | 新增 `nebula_dense_grid_fill_instance()` 辅助函数 | ✅ Step 5 |
| `examples/dense_text_demo.nelua` | 新建 | 120×50 网格 + per-char color 演示 | ✅ Step 5 |
| `tests/smoke_phase4_x_dense.lua` | 新建 | 管线生成 + 着色器组合 + 公理合规专项测试（65 条） | ✅ Step 5 |
| `docs/PLAN_PHASE4_X_DENSE_TEXT.md` | 更新 | 本文档（标记实施完成） | ✅ |

---

## 8. 与原方案的 Diff 摘要

| 维度 | v1（原方案） | v2（本修订） |
|:-----|:------------|:------------|
| Scope | 高密度文本 + 输入补全 | 仅高密度文本（输入已完成） |
| 顶点格式 | Vec4 fg/bg (64B/vertex) | 方案 B: Instanced 32B/instance |
| 颜色精度 | float32×4 | RGBA8 packed (u32) |
| 绘制模型 | Per-vertex 三角形列表 | Instanced（与 standard_instanced 一致） |
| 内存占用 (8192 chars) | 1.5 MB vertex buffer | 256 KB Storage Buffer |
| resize 通知 | 需新增 | 已有（Phase 3.12） |
| 剪贴板 | 需新增 | 已完成（缺口 #5） |
| Unicode 输入 | 需新增 | 已完成（缺口 #6） |
| D-4.1-C | 回避 | ✅ 已通过（+2.5% 退化），风险消除 |
| Dense vs Rich | 未界定 | 明确仅等宽网格 |
