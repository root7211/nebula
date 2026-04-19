# Phase 1 设计说明：`nebula_derive()` 编译期生成器

> **目标**：将 Phase 0 中需要在 `examples/*.nelua` 内部手写的 `<Visual>State` 枚举、`<Visual>StateMachine`、`<Visual>Context` 全部下沉为编译期自动派生。开发者最终只需要写"形状声明 + 注解"，框架自动生成剩余结构性代码。

---

## 1. 设计原则

1. **零运行时开销**：所有派生代码通过 `## emit` 在 Nelua 编译期注入到源文件，等价于手写代码，不存在任何 Lua 闭包、表查询、虚分发。
2. **命名约定即契约**：派生器约定 `<Visual>State`、`<Visual>StateMachine`、`<Visual>Context` 三个全局类型名，避免开发者与 Lua 元数据通信的额外语法。
3. **与 Phase 0 完全后向兼容**：保留 `nebula_annotate`、`nebula_gen_wgsl_uniform`、`nebula_calc_uniform_size` 等已有 API；`renderer.nelua` / `primitives.nelua` 不需要任何修改。
4. **渐进式迁移**：Phase 1 先派生 `button_demo` 的"单组件交互按钮"形态。`login_demo` 中的 `Input`（带 focused 状态）由 Phase 1.1 通过派生器扩展支持，而不是阻塞 Phase 1 主线。

---

## 2. 公开 API

```lua
nebula_derive(type_name)
  -- 在编译期立即向当前编译单元 emit 以下符号：
  --   global <type_name>State           : enum { Default=0, ... }
  --   global <type_name>StateMachine    : record { current, target, progress, duration, tween }
  --   global <type_name>Context         : record { visual, sm, hover?, click?, current_<prop>... }
  --   <type_name>StateMachine:init/transition_to/update/get_t
  --   <type_name>Context:init/update/to_uniforms
```

调用方式：

```nelua
##[[ nebula_annotate("ButtonVisual", { ... }) ]]
## nebula_derive("ButtonVisual")
```

---

## 3. 派生规则

### 3.1 状态枚举

- 状态名首字母大写后作为枚举项：`{"default","hovered","pressed"}` → `Default=0, Hovered=1, Pressed=2`。
- 第一个状态固定为初始状态（与 Phase 0 行为一致）。

### 3.2 状态机记录

```nelua
global <T>StateMachine = @record{
  current:  <T>State,
  target:   <T>State,
  progress: float32,
  duration: float32,
  tween:    uint8,   -- 0=none, 1=ease_out, 2=ease_in
}
```

- `transition_to(new_target)`：根据注解中的 `transitions` 列表展开为 if-else 链；同 Phase 0 的手写逻辑一致。
- `update(dt)` / `get_t()`：与 Phase 0 完全相同的算法。

### 3.3 运行时上下文

依据注解中的 `primitives` 列表自动注入字段：

| 注解原语 | 注入字段 |
|---|---|
| `hoverable` | `hover: HoverableState` |
| `clickable` | `click: ClickableState` |

依据 `state_fields` 中收集到的"视觉属性 → 类型"映射，为每个属性生成 `current_<prop>: <type>` 字段。

`update(mx, my, is_btn_down, dt)`：
1. 调用原语 update（顺序：hoverable → clickable）。
2. 按"压下 > 悬停 > 默认"优先级 transition 到对应状态。本规则在 Phase 1 内默认适用于带 `clickable` 的形状；不带 `clickable` 的退化为只有 hover/default 两态。
3. 推进状态机。
4. 对每个视觉属性，在 `sm.current` 与 `sm.target` 间做 `lerp_<type>` 插值，写入 `current_<prop>`。

`to_uniforms(vw, vh)`：构造与 Phase 0 完全一致的 `NebulaRectUniforms`，字段映射保持兼容（`bg_color`、`border_color`、`border_width`）。

### 3.4 类型→插值函数 映射

| 字段类型 | 插值函数 |
|---|---|
| `Color` | `lerp_color` |
| `float32` | `lerp_f32` |
| `Vec2` | `lerp_vec2` |

---

## 4. 实现策略

由于 Nelua 的 `## emit` 块需要写在源代码可执行位置，派生器的实现采用如下结构：

```lua
function nebula_derive(type_name)
  local code = nebula_gen_runtime_code(type_name)  -- 生成完整 Nelua 源码字符串
  static_assert(code ~= nil, ...)
  inject_statements(code)                          -- 等价于把字符串当作 Nelua 源代码插入
end
```

`inject_statements` 借助 Nelua 提供的 `context:add_statements` 或 `aster.parse` 能力。最简实现：在 `## block` 里使用 `inject_astnode(...)` 接口；若该 API 不可用，则退化为生成单独的 `.nelua` 片段并 `require`。Phase 1 采用**字符串 emit + `pragma` 注入**的方式：

```nelua
## local code = nebula_gen_runtime_code("ButtonVisual")
## inject_astnode( aster.parse(code) )
```

实测发现 Nelua 在预处理器内可使用 `## inject_statement(astnode)` 把字符串解析后的 AST 注入到当前位置。Phase 1 实现以此为准；若兼容性不足，将退化到"用户在 `## [[ ... ]]` 块中显式 `emit_ln(code)`"的方案。

---

## 5. 验收标准

1. `examples/button_demo.nelua` 删除全部手写状态机/上下文代码后，仍可成功 `./build.sh button_demo` 编译。
2. 编译期日志输出 `[derive] generated <T>State / <T>StateMachine / <T>Context` 字样，便于调试。
3. 生成的可执行文件在无显示环境下与 Phase 0 行为一致（GLFW 初始化失败也算编译链接成功的验证）。
4. `nebula_calc_uniform_size("ButtonVisual")` 仍输出 64 字节（与 Phase 0 推导引擎当前结果一致）。
5. 派生器对 `login_demo` 中的 `CardVisual`（无原语、无转换）也能成功派生为"静态 Context"。

---

## 6. Phase 1 不包含的工作

- std140 padding 自动化（属于 Phase 2 的渲染策略推导）。
- 着色器自动组合（Phase 2）。
- 多组件布局（Phase 3）。
- 文本渲染（Phase 4+）。
- `login_demo` 多管线渲染 bug 的根因修复（属 Phase 0 遗留问题，将单独立 issue）。
