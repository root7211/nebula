# Phase 4.X 实施方案：高密度文本渲染通道 + 输入系统补全

**创建日期**：2026-04-29
**前置依赖**：Phase 4.4 S3（multiline_editable 已完成）

---

## 0. 动机与定位

本 Phase 解决两个正交但协同的问题：

1. **文本渲染通道缺乏高密度模式**：当前 Nebula 有两条文本路径——
   SDF atlas（textured，max_chars=256）和 Slug 矢量（max_chars=256）。
   两者都为"按钮标签"量级设计，无法承载终端/代码编辑器/日志查看器
   等场景的 4000+ 字符需求，也缺乏 per-character 颜色属性。

2. **输入系统不完整**：缺少 Unicode 字符输入（glfwSetCharCallback）、
   剪贴板集成、和窗口 resize 通知暴露给应用层。

两者结合可以解锁：终端模拟器、代码编辑器、日志查看器、数据表格等
所有"文本密集 + 颜色属性"场景。

### 公理合规性声明

本 Phase 的所有新增能力均通过三大公理审查：

| 能力 | 公理 A（阶段封闭） | 公理 B（三层生命周期） | 公理 C（形即渲染） |
|:-----|:-----|:-----|:-----|
| atlas_dense 渲染通道 | ✅ 管线签名在 S1 确定 | ✅ atlas=L0, vbuf=L0, quad_data=L2 | ✅ Σ(V) 确定性映射 |
| max_chars 参数化 | ✅ spec 参数，S1 已知 | ✅ buffer 大小编译期确定 | ✅ 管线签名不变 |
| per-char color | ✅ VertexLayout 在 S1 确定 | ✅ color data=L2（帧级填入） | ✅ 属于 VertexLayout |
| glfwSetCharCallback | ✅ S2 用户输入事件 | ✅ codepoint=L2（帧级事件） | ✅ 与管线无关 |
| 剪贴板 | ✅ S2 OS API 调用 | ✅ 内容=L2 或 L1 | ✅ 与管线无关 |
| on_resize | ✅ S2 窗口事件 | ✅ viewport uniform 已有 | ✅ uniform 值变化 |

---

## 1. 现状分析

### 1.1 已有的文本渲染路径

Nebula 当前有两条文本管线路径，均由 `pipeline_factory.lua` 的
`nebula_gen_pipeline_source(spec)` 分发：

| 路径 | spec 标志 | vertex 格式 | 着色器 | 适用场景 |
|:-----|:----------|:------------|:-------|:---------|
| textured (SDF atlas) | `textured=true` | NebulaPosUvVertex (2×Vec2=16B) | nebula_compose_text_shader | 按钮标签（max_chars=256） |
| slug_text (矢量) | `slug_text=true` | NebulaSlugVertex (5×Vec4=80B) | nebula_compose_slug_shader | 高质量文本（max_chars=256） |

关键代码位置：
- `shader_compose.lua:26` — `nebula_compose_text_shader()` 生成 SDF atlas WGSL
- `shader_compose.lua:405` — `nebula_compose_slug_shader()` 生成 Slug WGSL
- `pipeline_factory.lua:50` — `gen_pipeline_textured_vertex()` 生成 textured 管线源码
- `pipeline_factory.lua:662` — `gen_pipeline_slug_text()` 生成 Slug 管线源码
- `pipeline_factory.lua:780` — `nebula_gen_pipeline_source(spec)` 分发入口
- `text_runtime.nelua:494` — `NebulaPosUvVertex` record 定义
- `text_runtime.nelua:189` — `nebula_ascii_text_build_vertices()` 顶点构建
- `nebula_core.nelua:982` — `gen_text_context_for()` SDF text context 生成
- `nebula_core.nelua:1046` — `nebula_derive_text_visual()` SDF text 派生入口

### 1.2 已有的输入基础设施

- `glfw_bindings.nelua` — 键盘 key code（GLFW_KEY_*）、鼠标按钮、光标位置
- `nebula_core.nelua:210` — `spec.max_chars` 参数已有（默认 256）
- `renderer.nelua:494` — `NebulaPosUvVertex` 只有 position + uv，无 color

### 1.3 缺失的能力

1. **max_chars 硬限制**：textured 路径的 `nebula_ascii_text_build_vertices`
   栈分配 `[%d]NebulaPosUvVertex`（max_vertices = max_chars × 6）。
   当 max_chars=4000 时，栈需要 4000×6×16 = 384 KB，对栈帧来说过大。

2. **无 per-char color**：`NebulaPosUvVertex` 只有 pos+uv；
   `nebula_compose_text_shader` 里颜色来自 `u.text_color`（uniform 全局色）。
   Slug 路径在 vertex attr4 里带 color，但每个 draw call 只有一个颜色。

3. **无 Unicode 字符输入**：GLFW key callback 只给 key code，
   没有 `glfwSetCharCallback` 来获取 Unicode codepoint。

4. **无剪贴板**：`glfw_bindings.nelua` 未绑定
   `glfwGetClipboardString` / `glfwSetClipboardString`。

5. **无 resize 通知**：`NebulaRenderer` 内部处理了 surface 重建，
   但 App 层无法感知窗口尺寸变化。

---

## 2. 实施路径

### 2.1 S1：Dense Text Rendering 通道

**目标**：新增第三条文本管线路径 `atlas_dense`，支持 4000+ 字符、
per-character fg/bg color、等宽优化。

#### 2.1.1 新顶点格式

```
NebulaDenseCharVertex = @record{
  position: Vec2,     -- 16B (x, y)  像素坐标
  uv:       Vec2,     -- 16B (u, v)  atlas 纹理坐标
  fg_color: Vec4,     -- 16B (r, g, b, a) 前景色
  bg_color: Vec4,     -- 16B (r, g, b, a) 背景色
}
-- 64 bytes/vertex
-- 每字符 6 顶点 = 384 bytes/char
-- 4000 字符 = 1.5 MB（可接受，CPU 端 arena 或 malloc）
```

#### 2.1.2 新 WGSL 着色器

由 `nebula_compose_dense_text_shader(opts)` 生成，位于
`shader_compose.lua`：

```
@group(0) @binding(0) var<uniform> u: DenseTextUniforms;
@group(0) @binding(1) var glyph_atlas:   texture_2d<f32>;
@group(0) @binding(2) var glyph_sampler: sampler;

struct DenseTextUniforms {
  viewport: vec2<f32>,
}

struct DenseCharVertexInput {
  @location(0) position: vec2<f32>,
  @location(1) uv:       vec2<f32>,
  @location(2) fg_color: vec4<f32>,
  @location(3) bg_color: vec4<f32>,
}

@vertex
fn vs_main(in: DenseCharVertexInput) -> VertexOutput {
  let ndc = vec2<f32>(
    (in.position.x / u.viewport.x) * 2.0 - 1.0,
    (in.position.y / u.viewport.y) * 2.0 - 1.0
  );
  out.clip_pos = vec4<f32>(ndc.x, -ndc.y, 0.0, 1.0);
  out.uv = in.uv;
  out.fg_color = in.fg_color;
  out.bg_color = in.bg_color;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let sdf = textureSample(glyph_atlas, glyph_sampler, in.uv).r;
  let width = fwidth(sdf);
  let alpha = smoothstep(0.5 - width, 0.5 + width, sdf);
  // 混合：背景色 + 前景色按 alpha 叠加
  return mix(in.bg_color, vec4<f32>(in.fg_color.rgb, 1.0), in.fg_color.a * alpha);
}
```

关键差异（对比现有 `nebula_compose_text_shader`）：
- Uniforms 极简（只有 viewport），颜色全部在 vertex attribute
- Fragment shader 做 bg+fg 混合
- 仍使用同一个 atlas 纹理（SDF 路径，glyph_atlas binding）

#### 2.1.3 管线代码生成

在 `pipeline_factory.lua` 中新增 `gen_pipeline_dense_text()`，
并在 `nebula_gen_pipeline_source(spec)` 的分发链中增加：

```lua
elseif spec.atlas_dense then
  return gen_pipeline_dense_text(spec.base, spec.uniforms_record, spec.wgsl_source)
```

生成的管线 record 结构与 `gen_pipeline_textured_vertex` 类似，
但 `init` 方法使用 `nebula_init_dense_char_vertex_layout`（4 attributes）。

#### 2.1.4 顶点构建运行时

在 `text_runtime.nelua` 中新增：

```nelua
global function nebula_dense_text_build_vertices(
  text:         cstring,
  origin_x:     float32,
  origin_y:     float32,
  pixel_height: float32,
  fg_colors:    *[0]Color,   -- per-char 前景色数组
  bg_colors:    *[0]Color,   -- per-char 背景色数组
  default_fg:   Color,
  default_bg:   Color,
  out_vertices: *[0]NebulaDenseCharVertex,
  max_vertices: uint32,
  out_width:    *float32,
  out_height:   *float32
): uint32
```

调用方负责分配 out_vertices 内存（L2 arena 或 L1 buffer）。

#### 2.1.5 TextContext 派生扩展

在 `nebula_core.nelua` 中新增 `nebula_derive_dense_text_visual(type_name)`，
与现有 `nebula_derive_text_visual` 并列。

关键差异：
- TextContext 用 `text_mode="atlas_dense"` 注入
- set_text 方法接受 fg_colors/bg_colors 参数
- vertex buffer 改用 L1 持久分配（不走 arena，因为 4000×6×64B = 1.5MB）

#### 2.1.6 公理合规性细节

| 数据 | 生命周期层 | 理由 |
|:-----|:----------|:-----|
| atlas 纹理 | L0 | init 创建，应用全生命周期 |
| pipeline + bind group | L0 | 编译期确定的管线签名 |
| dense vertex buffer | L0/L1 | init 创建（大小编译期确定），内容每帧更新 |
| per-frame quad data | L2 | 每帧 CPU 构建，写入 L0 buffer |
| DenseTextUniforms | L0 | 只含 viewport，resize 时更新 |

公理 C 审查：
- Σ(TerminalVisual) = (DenseCharVertexLayout, DenseTextUniformsLayout,
  DenseTextShaderModule, AlphaBlend)
- 所有四项在 S1 完全确定
- 与 Σ(ButtonTextVisual) = (PosUvLayout, TextUniformsLayout, ...) 正交

### 2.2 S2：输入系统补全

#### 2.2.1 Unicode 字符输入

在 `glfw_bindings.nelua` 中新增：

```nelua
typealias GLFWcharfun = function(window: *GLFWwindow, codepoint: uint32): void
global function glfwSetCharCallback(window: *GLFWwindow, cbfun: GLFWcharfun): GLFWcharfun <cimport, nodecl> end
```

在 `NebulaInputState` 中新增：

```nelua
global NebulaCharEvent = @record{
  codepoint: uint32,
}

global NebulaInputState = @record{
  -- ... 已有字段 ...
  char_events:      [64]NebulaCharEvent,  -- L2 帧级缓冲
  char_event_count: uint32,
}
```

GLFW char callback 将 codepoint 写入缓冲区（ring buffer 或
帧级数组）。process_input 中原语可读取。

#### 2.2.2 剪贴板集成

在 `glfw_bindings.nelua` 中新增：

```nelua
global function glfwGetClipboardString(window: *GLFWwindow): cstring <cimport, nodecl> end
global function glfwSetClipboardString(window: *GLFWwindow, string: cstring): void <cimport, nodecl> end
```

在 `nebula_core.nelua` 的 `editable` 原语中扩展 process_body：
增加 Ctrl+C / Ctrl+V / Ctrl+X 处理（调用剪贴板 API）。

#### 2.2.3 窗口 resize 通知

在 `NebulaRenderer` 或 App 框架中暴露：

```nelua
global NebulaResizeEvent = @record{
  width:  uint32,
  height: uint32,
}
```

在 `nebula_frame_render` 的 surface 重建路径中，当检测到
尺寸变化时设置标志。App 的 update 回调可读取。

---

## 3. 验收标准

1. **高密度文本渲染**：编译一个 120×40 终端网格（4800 字符），
   每个字符有不同的 fg/bg color，60fps 流畅渲染。
2. **公理合规**：新管线路径的 Σ(V) 在 S1 完全确定，无运行时
   管线创建或类型生成。
3. **回归**：现有 36/36 回归测试全绿，form_demo 编译结果字节一致。
4. **Unicode 输入**：通过 glfwSetCharCallback 接收中文 codepoint，
   写入 char_events 缓冲区。
5. **剪贴板**：Ctrl+C / Ctrl+V 在 editable 原语中可用。
6. **resize 通知**：App 层能在 update 中获取窗口新尺寸。

---

## 4. 文件清单

| 文件 | 操作 | 内容 |
|:-----|:-----|:-----|
| `src/derive/shader_compose.lua` | 修改 | 新增 `nebula_compose_dense_text_shader()` |
| `src/derive/pipeline_factory.lua` | 修改 | 新增 `gen_pipeline_dense_text()`，扩展分发链 |
| `src/renderer.nelua` | 修改 | 新增 `NebulaDenseCharVertex` record + `nebula_init_dense_char_vertex_layout` |
| `src/text_runtime.nelua` | 修改 | 新增 `nebula_dense_text_build_vertices()` |
| `src/nebula_core.nelua` | 修改 | 新增 `nebula_derive_dense_text_visual()`；editable 原语扩展剪贴板 |
| `src/glfw_bindings.nelua` | 修改 | 新增 char callback + clipboard 绑定 |
| `src/input.nelua` | 修改 | NebulaInputState 扩展 char_events |
| `examples/dense_text_demo.nelua` | 新建 | 演示 4800 字符 + per-char color |
| `tests/smoke_phase4_x.lua` | 新建 | 专项测试 |

---

## 5. 不在范围内

以下终端特有能力由应用层自行实现，不属于本 Phase：

- PTY 管理（fork/exec/openpty）
- VT100/ANSI 转义序列解析
- 终端环形缓冲区
- DEC 私有模式状态机
- 终端选区管理（双击选词等）
- IME 预编辑支持
