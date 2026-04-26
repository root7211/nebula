# Phase 3.11: Layout-App 统一注册与 30 行愿景兑现

## 目标与背景

在 Phase 3.10 之前，Nebula 的布局引擎（`layout_engine.lua`）和 App 编排工厂（`app_factory.lua`）是两个独立的系统。开发者必须手动声明两套结构：一套用于 Flexbox 解算，一套用于 App 注册。更糟糕的是，解算出的坐标需要通过 `get_layout_pos` 等辅助函数，手动注入到每个组件的 `init` 调用中。

这不仅违反了 DRY（Don't Repeat Yourself）原则，也使得代码中充斥着样板代码和魔法数字。

Phase 3.11 的核心目标是：**将布局约束直接嵌入到 App 注册 API 中，在编译期自动完成解算和坐标注入，彻底消除手写魔法数字，并提供便利性 API 封装，兑现"30 行代码构建应用"的愿景。**

## 核心改动

### 1. 统一注册 API

在 `app_factory.lua` 中引入了新的布局声明方式：

- **`nebula_app_set_root_layout(app_name, spec)`**：声明根节点的布局约束（如视口尺寸、主轴方向、对齐方式）。
- **`layout` 字段**：在 `nebula_app_register_component` 的 `opts` 中新增 `layout` 字段，允许组件声明自身的尺寸和内部布局约束。
- **嵌套子节点**：通过 `layout.children` 数组，可以直接声明纯布局占位符或嵌套组件，无需为每个层级单独注册 Visual。

### 2. 编译期自动解算与注入

在 `nebula_app_end()` 被调用时，工厂会自动：
1. 遍历所有注册的组件，根据 `layout` 字段构建一棵完整的 Flexbox 布局树。
2. 调用 `layout_engine.lua` 进行解算。
3. 将解算结果存入 `layout_results` 表。

在 `nebula_app_generate()` 生成代码时，工厂会自动将 `layout_results` 中的坐标和尺寸作为**编译期常量**，注入到每个组件的 `visual.pos` 和 `visual.size` 字段中。

### 3. 便利性 API 封装

在 `app.nelua` 中新增了三个全局便利函数，封装了繁琐的 GLFW 和 WGPU 初始化/清理流程：

- **`nebula_init(renderer, app, title, width, height)`**：一行代码完成 GLFW 初始化、窗口创建、渲染器初始化和 App 初始化。
- **`nebula_should_close()`**：封装 `glfwWindowShouldClose`。
- **`nebula_shutdown(renderer)`**：封装资源释放和 GLFW 清理。

## 成果展示

重构后的 `form_demo.nelua` 主循环从原来的 60 多行收缩到了极简的形态：

```nelua
local function main(): int32
  local renderer: NebulaRenderer
  local app: FormApp

  if not nebula_init(&renderer, &app, "Nebula Phase 3.11", WIN_W, WIN_H) then
    return 1
  end

  -- ... 仅需初始化颜色/圆角等外观属性，pos/size 已在编译期自动注入 ...

  local input: NebulaInputState
  local prev_time = glfwGetTime()

  while not nebula_should_close() do
    nebula_poll_events()
    local now = glfwGetTime()
    local dt  = (@float32)(now - prev_time)
    prev_time = now
    nebula_collect_input(_nebula_window, &input, dt)
    nebula_frame_render(&renderer, &app, &input, dt, 0.09, 0.09, 0.10)
  end

  nebula_shutdown(&renderer)
  return 0
end
```

## 测试覆盖

新增了 `tests/smoke_phase3_11.lua` 专项回归测试（65 项断言），覆盖了：
- API 存在性与调用顺序（支持预注册）。
- 布局解算结果的数学正确性。
- 生成代码中编译期常量的注入情况。
- 向后兼容性（无 `layout` 字段的旧代码依然可用）。
- 行数收敛验证（确保精简效果）。

全量回归测试（Phase 3.8 / 3.9 / 3.11）已达到 **159/159 通过**。

## 下一步计划

Phase 3.11 的完成，标志着 Nebula v2 路线图的正式收口。接下来将进入 Phase 3.12，利用 Phase 3.11 建立的统一布局树，实现**编译期微扰采样 + 运行时线性插值**的响应式重排方案。
