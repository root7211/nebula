# Phase 2.2 开发计划：着色器按字段组合 (Shader Composition)

> **总目标**：消除 `renderer.nelua` 中硬编码的 `RECT_SHADER_WGSL` 字符串。通过编译期推导引擎，根据 `Visual` 规格中声明的字段，自动拼装出对应的 WGSL 着色器代码。

---

## 1. 现状与挑战

在 Phase 2.1 中，我们已经实现了 Uniform 布局的自动化。目前的 `RECT_SHADER_WGSL` 虽然使用了自动生成的 `struct Uniforms`，但其渲染逻辑（SDF 圆角矩形、边框计算、抗锯齿）仍然是硬编码的。

**Phase 2.2 的核心任务**是将这些逻辑拆解为“功能片段 (Fragments)”，并根据字段的存在性进行条件组合：
- 如果有 `radius` 字段 ⇒ 注入 `sdf_rounded_rect` 逻辑。
- 如果有 `border_width` 字段 ⇒ 注入边框渲染逻辑。
- 如果没有这些字段 ⇒ 生成最简化的矩形填充着色器。

---

## 2. 技术方案

### 2.1 核心 API 设计

在 `src/nebula_core.nelua` 中新增以下 Lua 函数：

```lua
-- 根据类型规格生成完整的 WGSL 源码
function nebula_gen_wgsl_shader(type_name, opts) -> string

-- 内部维护的片段表
local WGSL_FRAGMENTS = {
  header = [[ ... VertexOutput 定义 ... ]],
  vs_main = [[ ... 全屏三角形顶点着色器 ... ]],
  sdf_rect = [[ ... 基础矩形距离函数 ... ]],
  sdf_rounded_rect = [[ ... 圆角矩形距离函数 ... ]],
  fill_logic = [[ ... 填充颜色计算 ... ]],
  border_logic = [[ ... 边框颜色叠加 ... ]],
  footer = [[ ... 最终颜色返回与 discard ... ]]
}
```

### 2.2 字段与逻辑映射表

| 字段名 | 触发的着色器片段 | 备注 |
|---|---|---|
| (Always) | `header` + `vs_main` | 基础管线结构 |
| `radius` | `sdf_rounded_rect` | 否则使用 `sdf_rect` |
| `bg_color` | `fill_logic` | 基础填充 |
| `border_color` / `border_width` | `border_logic` | 边框叠加 |

---

## 3. 实施步骤

### 第一阶段：片段化改造 (Sub-phase 2.2.1)
1. 在 `nebula_core.nelua` 中定义 `WGSL_FRAGMENTS`。
2. 实现 `nebula_gen_wgsl_shader` 基础版本，支持拼接 `Uniforms` 结构体和基础渲染逻辑。
3. **验证**：生成的着色器源码在字符串层面应与当前的 `RECT_SHADER_WGSL` 高度相似。

### 第二阶段：条件组合逻辑 (Sub-phase 2.2.2)
1. 实现根据 `nebula_parse_shape` 结果动态选择片段的逻辑。
2. 处理 `radius` 的可选性：若无 `radius` 字段，则不生成 `sdf_rounded_rect` 函数，改用简单的 `abs(p) - half_size`。
3. **验证**：创建一个不带 `radius` 的 `SimpleRectVisual`，观察生成的着色器是否更精简。

### 第三阶段：集成与回归 (Sub-phase 2.2.3)
1. 修改 `renderer.nelua`，彻底删除 `RECT_SHADER_WGSL` 常量。
2. 使用 `#[nebula_gen_wgsl_shader("NebulaRect", { ... })]#` 动态生成。
3. **验证**：`button_demo` 和 `login_demo` 渲染效果无变化。
4. **回归测试**：运行 `tools/headless_test.c` 确保像素级一致。

---

## 4. 验收标准

1. **代码清理**：`src/renderer.nelua` 中不再包含任何长段的 WGSL 字符串常量。
2. **动态性验证**：
   - 带有 `radius` 的组件生成包含 SDF 圆角逻辑的着色器。
   - 不带 `radius` 的组件生成不含该函数的精简着色器。
3. **功能完整性**：`button_demo` 的圆角、边框、颜色插值全部正常工作。
4. **性能无损**：编译期生成的字符串在运行时直接提交给 GPU，无额外开销。

---

## 5. 风险提示

- **WGSL 语法错误**：字符串拼接容易漏掉分号或括号。需在编译期增加简单的语法校验或通过 `wgpu` 的错误回调捕获。
- **字段命名冲突**：如果 Visual 规格中使用了与着色器内部变量同名的字段，可能导致编译失败。需在片段中使用 `u.` 前缀严格区分 Uniform 访问。
