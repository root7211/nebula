# Phase 2.2 开发计划：着色器按字段组合 (Shader Composition)

> **总目标**：消除 `renderer.nelua` 中硬编码的 `RECT_SHADER_WGSL` 字符串。通过编译期推导引擎，根据 `Visual` 规格中声明的字段，自动拼装出对应的 WGSL 着色器代码。

---

## 1. 现状与挑战

在 Phase 2.1 中，我们已经实现了 Uniform 布局的自动化。目前的 `RECT_SHADER_WGSL` 虽然使用了自动生成的 `struct Uniforms`，但其渲染逻辑（SDF 圆角矩形、边框计算、抗锯齿）仍然是硬编码的。

**Phase 2.2 的核心任务**是将这些逻辑拆解为"功能片段 (Fragments)"，并根据字段的存在性进行条件组合：
- 如果有 `radius` 字段 ⇒ 注入 `sdf_rounded_rect` 逻辑。
- 如果有 `border_width` 字段 ⇒ 注入边框渲染逻辑。
- 如果没有这些字段 ⇒ 生成最简化的矩形填充着色器。

**Phase 2.2 的范围限制**：本阶段仅处理单 Pass 渲染。多 Pass 渲染（如 Shadow 高斯模糊）以及管线工厂派生明确推迟至 Phase 2.3。

---

## 2. 技术方案

### 2.1 模块化架构

着色器组合逻辑独立封装为 `src/derive/shader_compose.lua` 模块，与 `nebula_core.nelua` 解耦。这是 Phase 2 整体代码膨胀缓解策略的第一步，为后续 `pipeline_factory.lua`、`primitive_inline.lua` 等模块的拆分建立范式。

```text
src/
├── nebula_core.nelua          # 集成入口：nebula_gen_wgsl_shader()
└── derive/
    └── shader_compose.lua     # WGSL 片段表 + 组合器 nebula_compose_shader()
```

### 2.2 核心 API 设计

在 `src/nebula_core.nelua` 中新增以下 Lua 函数：

```lua
-- 根据注解类型名生成完整的 WGSL 着色器
function nebula_gen_wgsl_shader(type_name, opts) -> {
  source,           -- 完整 WGSL 源码（含 vs_main + fs_main）
  features,         -- {"radius", "fill", "border"}
  required_passes,  -- {"main"}（Phase 2.2 固定为单 Pass）
}

-- 根据手动指定的字段列表生成着色器（供 renderer.nelua 使用）
function nebula_gen_wgsl_shader_from_fields(spec) -> result, layout
```

在 `src/derive/shader_compose.lua` 中实现底层组合器：

```lua
-- 内部维护的片段表
local WGSL_FRAGMENTS = {
  binding          = function(opts) ... end,  -- @group(0) @binding(0)
  vertex_output    = function(opts) ... end,  -- VertexOutput 定义
  vs_main          = function(opts) ... end,  -- 全屏三角形顶点着色器
  sdf_rounded_rect = function(opts) ... end,  -- 圆角矩形距离函数
  sdf_rect         = function(opts) ... end,  -- 简单矩形距离函数
  fs_main          = function(opts) ... end,  -- Fragment 着色器（按特性组合）
}

-- 公开 API
function nebula_compose_shader(opts) -> { source, features, required_passes }
```

### 2.3 字段与逻辑映射表

| 字段名 | 触发的着色器片段 | 备注 |
|---|---|---|
| (Always) | `binding` + `vertex_output` + `vs_main` | 基础管线结构 |
| `radius` | `sdf_rounded_rect` | 否则使用 `sdf_rect` |
| `bg_color` | `fill_logic`（在 `fs_main` 内） | 基础填充 |
| `border_color` + `border_width` | `border_logic`（在 `fs_main` 内） | 边框叠加 |

### 2.4 兼容性策略

Phase 2.2 生成的着色器继续使用 Phase 2.1 的兼容 Uniform 布局（96 字节，`force_viewport_align=16`）。`Context:to_uniforms` 的返回类型仍为 `NebulaRectUniforms`，不在本阶段修改。真正的布局解耦（删除 `_pad` 填充）在 Phase 2.3 与 Pipeline 重构同步进行。

---

## 3. 实施步骤

### 第一阶段：模块化拆分 (Sub-phase 2.2.1)
1. 创建 `src/derive/shader_compose.lua`，定义 `WGSL_FRAGMENTS` 片段表。
2. 实现 `nebula_compose_shader` 组合器。
3. **验证**：模块可被 `require` 加载，返回版本标识。

### 第二阶段：集成与替换 (Sub-phase 2.2.2)
1. 在 `nebula_core.nelua` 中 `require "derive.shader_compose"`。
2. 实现 `nebula_gen_wgsl_shader` 和 `nebula_gen_wgsl_shader_from_fields`。
3. 修改 `renderer.nelua`，用 `nebula_gen_wgsl_shader_from_fields` 替换硬编码的 `RECT_SHADER_WGSL`。
4. **验证**：`button_demo` 和 `login_demo` 编译通过，编译期日志输出 `[shader]` 信息。

### 第三阶段：边界验证 (Sub-phase 2.2.3)
1. 新增 `examples/simple_rect_demo.nelua`：仅 `pos`、`size`、`bg_color`，无 `radius`、无 `border`。
2. **验证**：编译期日志显示 `features=[fill]`，生成的着色器使用 `sdf_rect` 而非 `sdf_rounded_rect`。

### 第四阶段：测试基础设施解耦 (Sub-phase 2.2.4)
1. 创建 `tools/export_shader_fixture.nelua`：编译期导出 `fixture_shader.h`。
2. 重构 `tools/headless_test.c`：`#include "fixture_shader.h"` 替代硬编码。
3. **验证**：`headless_test.c` 编译通过，Uniform 布局和着色器源码与引擎推导产物保持同步。

---

## 4. 验收标准

1. **代码清理**：`src/renderer.nelua` 中不再包含任何长段的 WGSL 字符串常量。
2. **动态性验证**：
   - 带有 `radius` 的组件生成包含 SDF 圆角逻辑的着色器。
   - 不带 `radius` 的组件生成不含该函数的精简着色器。
3. **功能完整性**：`button_demo` 的圆角、边框、颜色插值全部正常工作。
4. **性能无损**：编译期生成的字符串在运行时直接提交给 GPU，无额外开销。
5. **编译期日志**：每个着色器生成输出形如：
   ```text
   [shader] NebulaRectUniforms: features=[radius, fill, border]  (96B uniforms, 1 pass)
   ```
6. **测试解耦**：`headless_test.c` 通过 `fixture_shader.h` 引用自动生成的着色器。

---

## 5. 风险提示

- **WGSL 语法错误**：字符串拼接容易漏掉分号或括号。需在编译期增加简单的语法校验或通过 `wgpu` 的错误回调捕获。
- **字段命名冲突**：如果 Visual 规格中使用了与着色器内部变量同名的字段，可能导致编译失败。需在片段中使用 `u.` 前缀严格区分 Uniform 访问。
- **兼容性约束**：Phase 2.2 必须保持与 Phase 2.1 的 96 字节 Uniform 布局二进制等价，不可提前切换到紧凑布局。

---

## 6. 不在 Phase 2.2 范围

- **Shadow / 多 Pass 渲染**：推迟至 Phase 2.3（管线工厂派生）。
- **`to_uniforms` 重构**：推迟至 Phase 2.3（与 Pipeline 类型解耦同步）。
- **Uniform 紧凑布局**：推迟至 Phase 2.3（删除 `force_viewport_align=16`）。
- **`shadow_demo.nelua`**：推迟至 Phase 2.3（依赖多 Pass 管线）。

---

## 7. 新增文件清单

| 文件 | 用途 |
|---|---|
| `src/derive/shader_compose.lua` | WGSL 片段表 + 组合器 |
| `examples/simple_rect_demo.nelua` | 边界验证 Demo（无 radius、无 border） |
| `tools/export_shader_fixture.nelua` | 编译期着色器 Fixture 导出工具 |
| `tools/fixture_shader.h` | 自动生成的 C 头文件（供 headless_test.c 使用） |
