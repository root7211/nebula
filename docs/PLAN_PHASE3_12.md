# Phase 3.12 实施方案：响应式重排 (Responsive Reflow)

**目标**：在不违反公理 A（阶段封闭性）的前提下，实现窗口 Resize 时的 UI 响应式重排。

## 1. 架构背景与张力

当前 Nebula 的布局引擎（`layout_engine.lua`）完全运行在 S1 阶段（编译期）。它在 Lua 宏中执行 Flexbox 算法，将相对布局约束解算为绝对的 `x, y, w, h` 坐标，然后通过 `#[get_layout_pos("name")]#` 将这些坐标作为**硬编码的浮点数常量**注入到生成的 C/Nelua 代码中。

这种设计的优势是 S2 阶段（运行期）的布局开销为零，但代价是**失去了响应式能力**。当用户拉伸窗口时，UI 组件的坐标依然是编译时确定的常量，无法自适应新的视口尺寸。

如果将 Flexbox 引擎直接搬到 S2 阶段的 CPU 侧运行，将严重违反公理 A（后一阶段不得执行前一阶段的操作），并引入运行时的树遍历开销。

## 2. 解决方案：编译期约束降维 + 运行时线性插值

为了在保持 S2 零遍历开销的同时实现响应式，我们需要将 S1 的"绝对坐标输出"降维为"相对视口的线性函数"。

### 2.1 核心思想：坐标即函数

任何 Flexbox 布局的结果，在没有内容换行（Wrap）的情况下，其组件的最终坐标 `(x, y)` 和尺寸 `(w, h)` 都可以表示为视口尺寸 `(vw, vh)` 的线性组合：

```
x = a * vw + b
y = c * vh + d
w = e * vw + f
h = g * vh + h
```

其中 `a, b, c, d, e, f, g, h` 是在 S1 阶段可以确定性计算出的常数系数。

### 2.2 S1 阶段：多视口采样与系数推导

在 `layout_engine.lua` 中，我们不再只进行一次 `nebula_layout_solve`。

1. **基准采样**：使用基准视口尺寸（如 800x600）进行一次解算，得到 `(x0, y0, w0, h0)`。
2. **微扰采样**：使用微扰视口尺寸（如 801x601）进行第二次解算，得到 `(x1, y1, w1, h1)`。
3. **系数推导**：通过两点确定一条直线，计算出每个组件的线性系数。例如，宽度系数 `e = (w1 - w0) / (801 - 800)`，常数项 `f = w0 - e * 800`。
4. **代码生成**：将这些系数注入到生成的 Nelua 代码中，而不是绝对坐标。

### 2.3 S2 阶段：扁平化更新

在运行期，当检测到窗口 Resize 事件时：

1. **事件捕获**：`app.nelua` 捕获 GLFW 的 framebuffer resize 回调，更新 `input.viewport_w` 和 `input.viewport_h`。
2. **线性计算**：在 `<App>:update` 函数中，生成一段扁平化的代码，遍历所有组件，使用预先注入的系数和当前的视口尺寸，重新计算绝对坐标：
   ```nelua
   self.card.pos.x = 0.5 * input.viewport_w - 200.0
   self.card.size.x = 0.0 * input.viewport_w + 400.0
   ```
3. **零遍历**：这个过程是一个扁平的数组遍历（或直接展开的赋值语句），没有任何树结构，没有任何 Flexbox 逻辑，计算开销极低。

## 3. 实施路径

1. **修改 `layout_engine.lua`**：
   - 增加 `nebula_layout_derive_coefficients(root)` 函数，执行两次解算并计算系数。
   - 返回的数据结构从 `{x, y, w, h}` 变为 `{x_vw, x_c, y_vh, y_c, w_vw, w_c, h_vh, h_c}`。
2. **修改 `app_factory.lua`**：
   - 在生成 `<App>:init` 时，不再注入绝对坐标，而是注入初始视口下的计算结果。
   - 在生成 `<App>:update` 时，注入响应式更新逻辑：`if input.viewport_resized then ... end`。
3. **修改 `app.nelua`**：
   - 增加 `glfwSetFramebufferSizeCallback` 监听。
   - 在 `NebulaInputState` 中增加 `viewport_resized` 标志位。

## 4. 局限性与未来演进

这种"线性插值"方案完美解决了百分比宽度、居中对齐、Stretch 等常见响应式需求，且严格遵守公理 A。

**局限性**：它无法处理 `flex-wrap: wrap`（换行）或基于媒体查询的结构突变（如窗口变窄时从左右布局变为上下布局）。因为这些操作会导致坐标函数发生非线性突变。

**未来演进**：对于非线性突变，将在 v3 白皮书规划的 Phase 6.0（Compute Shader Layout）中彻底解决。在此之前，Phase 3.12 的线性插值方案足以覆盖 90% 的桌面工具响应式需求。
