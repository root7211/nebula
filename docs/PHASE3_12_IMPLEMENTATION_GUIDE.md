# Nebula Phase 3.12: 响应式重排 (Responsive Reflow) 实现建议指南

**作者**：Manus AI
**日期**：2026-04-26
**目标阶段**：Phase 3.12
**核心目标**：在不违反公理 A（阶段封闭性）的前提下，实现窗口 Resize 时的 UI 响应式重排。

---

## 1. 架构回顾与挑战分析

在当前的 Phase 3.11 中，Nebula 已经实现了 Layout-App 统一注册。布局引擎 (`layout_engine.lua`) 在 S1 阶段（编译期）运行，将相对的 Flexbox 约束解算为绝对坐标，并通过 `app_factory.lua` 注入到 `<App>:init()` 中，作为硬编码的浮点数常量。

这种设计的优势在于 S2 阶段（运行期）实现了零布局开销，完全没有树遍历和布局计算。然而，这也导致了 UI 失去了响应式能力，无法适应窗口尺寸的变化。

Phase 3.12 的核心挑战在于：**如何在不将 Flexbox 引擎移至运行期（违反公理 A）且保持零树遍历开销的前提下，实现响应式重排？**

官方路线图 (`PLAN_PHASE3_12.md`) 提出的解决方案是：**编译期约束降维 + 运行时线性插值**。

---

## 2. 核心实现思路

### 2.1 编译期（S1 阶段）：多视口采样与系数推导

目前 `layout_engine.lua` 中的 `nebula_layout_solve` 只进行一次解算。在 Phase 3.12 中，我们需要进行**两次微扰采样**，以推导出坐标和尺寸关于视口宽度（vw）和高度（vh）的线性系数。

对于任何没有换行（wrap）的 Flexbox 布局，组件的最终坐标 `(x, y)` 和尺寸 `(w, h)` 都可以表示为：
- `x = c_x_vw * vw + c_x_c`
- `y = c_y_vh * vh + c_y_c`
- `w = c_w_vw * vw + c_w_c`
- `h = c_h_vh * vh + c_h_c`

**实现步骤建议**：

1. **修改 `layout_engine.lua`**：
   新增 `nebula_layout_derive_coefficients(root, base_w, base_h)` 函数。
   - **基准采样**：使用 `(base_w, base_h)` 调用 `nebula_layout_solve`，记录每个组件的 `(x0, y0, w0, h0)`。
   - **微扰采样**：使用 `(base_w + 1, base_h + 1)` 再次调用 `nebula_layout_solve`，记录 `(x1, y1, w1, h1)`。
   - **系数计算**：
     - `c_x_vw = x1 - x0`
     - `c_x_c = x0 - c_x_vw * base_w`
     - 以此类推计算其他 6 个系数。
   - **结果收集**：修改 `nebula_layout_collect`，返回的数据结构从 `{x, y, w, h}` 变更为 `{ c_x_vw, c_x_c, c_y_vh, c_y_c, c_w_vw, c_w_c, c_h_vh, c_h_c }`。

### 2.2 运行期（S2 阶段）：扁平化线性插值

在运行期，当窗口尺寸发生变化时，我们只需要遍历一个扁平的数组（或直接展开的赋值语句），使用预先计算好的系数重新计算绝对坐标。

**实现步骤建议**：

1. **修改 `glfw_bindings.nelua`**：
   目前绑定层缺少对 framebuffer resize 回调的支持。需要补充：
   ```nelua
   global GLFWframebuffersizefun <cimport, nodecl> = @function(window: GLFWwindow, width: int32, height: int32): void
   global function glfwSetFramebufferSizeCallback(window: GLFWwindow, callback: GLFWframebuffersizefun): GLFWframebuffersizefun <cimport, nodecl> end
   global function glfwGetFramebufferSize(window: GLFWwindow, width: *int32, height: *int32): void <cimport, nodecl> end
   ```

2. **修改 `app.nelua`**：
   - 在 `NebulaInputState` 中新增字段：
     ```nelua
     viewport_w: float32
     viewport_h: float32
     viewport_resized: boolean
     ```
   - 增加 `_nebula_framebuffer_size_callback`，并在 `nebula_input_install_callbacks` 中注册。
   - 在 `nebula_collect_input` 中，如果发生 resize，更新 `input.viewport_w` 和 `input.viewport_h`，并设置 `input.viewport_resized = true`。
   - **关键修改**：`renderer.nelua` 中的 `NebulaRenderer:init` 目前只在初始化时配置一次 Surface。当窗口 resize 时，必须调用 `wgpuSurfaceConfigure` 重新配置 Surface，否则 WebGPU 渲染会报错。这部分逻辑建议放在 `nebula_frame_render` 的开头，如果检测到 `input.viewport_resized`，则更新 `renderer.width` 和 `renderer.height` 并重新 configure。

3. **修改 `app_factory.lua`**：
   - **修改 `gen_app_init`**：不再注入绝对坐标，而是注入初始视口下的计算结果，或者直接在 init 中调用一次 update 逻辑。
   - **修改 `gen_app_update`**：注入响应式更新逻辑。
     ```nelua
     if input.viewport_resized then
       -- 扁平化的线性插值计算
       self.card.visual.pos.x = 0.5 * input.viewport_w - 200.0
       self.card.visual.size.x = 0.0 * input.viewport_w + 400.0
       -- ... 对所有注册组件生成类似代码 ...
       
       -- 更新所有管线的 viewport uniform
       self.pipe_card:update_viewport(self.renderer, input.viewport_w, input.viewport_h)
       -- ...
     end
     ```

## 3. 具体代码修改指南

### 3.1 扩展 `layout_engine.lua`

在 `layout_engine.lua` 的末尾添加：

```lua
function nebula_layout_derive_coefficients(root, base_w, base_h)
  -- 1. 基准采样
  nebula_layout_solve(root, base_w, base_h)
  local base_results = nebula_layout_collect(root)
  
  -- 2. 宽度微扰采样
  nebula_layout_solve(root, base_w + 1, base_h)
  local dw_results = nebula_layout_collect(root)
  
  -- 3. 高度微扰采样
  nebula_layout_solve(root, base_w, base_h + 1)
  local dh_results = nebula_layout_collect(root)
  
  -- 4. 计算系数
  local coeffs = {}
  for name, b in pairs(base_results) do
    local dw = dw_results[name]
    local dh = dh_results[name]
    
    local cx_vw = dw.x - b.x
    local cw_vw = dw.w - b.w
    local cy_vh = dh.y - b.y
    local ch_vh = dh.h - b.h
    
    coeffs[name] = {
      cx_vw = cx_vw, cx_c = b.x - cx_vw * base_w,
      cy_vh = cy_vh, cy_c = b.y - cy_vh * base_h,
      cw_vw = cw_vw, cw_c = b.w - cw_vw * base_w,
      ch_vh = ch_vh, ch_c = b.h - ch_vh * base_h,
    }
  end
  return coeffs
end
```

### 3.2 升级 `app_factory.lua`

在 `_solve_layout` 中，改用 `nebula_layout_derive_coefficients`：

```lua
local function _solve_layout(reg)
  -- ... 构建 root ...
  local vw = reg.root_layout.width  or 800
  local vh = reg.root_layout.height or 600
  reg.layout_coeffs = nebula_layout_derive_coefficients(root, vw, vh)
end
```

在 `gen_app_update` 中注入插值代码：

```lua
if reg.layout_coeffs and next(reg.layout_coeffs) then
  emit("  if input.viewport_resized then")
  for _, comp in ipairs(reg.components) do
    local c = reg.layout_coeffs[comp.name]
    if c then
      emit(("    self.%s.visual.pos.x = %.4f * input.viewport_w + %.4f"):format(comp.name, c.cx_vw, c.cx_c))
      emit(("    self.%s.visual.pos.y = %.4f * input.viewport_h + %.4f"):format(comp.name, c.cy_vh, c.cy_c))
      emit(("    self.%s.visual.size.x = %.4f * input.viewport_w + %.4f"):format(comp.name, c.cw_vw, c.cw_c))
      emit(("    self.%s.visual.size.y = %.4f * input.viewport_h + %.4f"):format(comp.name, c.ch_vh, c.ch_c))
    end
  end
  -- 还需要生成代码更新各管线的 viewport
  for vt, group in pairs(reg.type_groups) do
    emit(("    self.pipe_%s:update_viewport(self.renderer, input.viewport_w, input.viewport_h)"):format(group.base:lower()))
  end
  emit("  end")
end
```

### 3.3 完善 `renderer.nelua` 和 `app.nelua`

当检测到 Resize 时，必须重新配置 WebGPU Surface，否则呈现会失败。

在 `app.nelua` 的 `nebula_frame_render` 中：

```nelua
  if input.viewport_resized then
    renderer.width = (@uint32)(input.viewport_w)
    renderer.height = (@uint32)(input.viewport_h)
    
    local surf_cfg = WGPUSurfaceConfiguration{
      nextInChain     = nilptr,
      device          = renderer.device,
      format          = renderer.format,
      usage           = 0x00000010,
      viewFormatCount = 0,
      viewFormats     = nilptr,
      alphaMode       = 1,
      width           = renderer.width,
      height          = renderer.height,
      presentMode     = WGPUPresentMode_Fifo,
    }
    wgpuSurfaceConfigure(renderer.surface, &surf_cfg)
  end
```

## 4. 阴影与多 Pass 管线的特殊处理

需要特别注意的是，Phase 3.10.5 引入了多 Pass 阴影渲染（`gen_pipeline_shadow`）。阴影管线在 `init` 时创建了离屏渲染纹理（`tex_a`, `tex_b`），它们的尺寸目前是固定在 `init` 时的 `win_w` 和 `win_h` 的。

当视口改变时，除了更新主画布的 Surface，**还必须重建阴影的离屏纹理和相关的 BindGroup**。

**建议**：
在 `pipeline_factory.lua` 的 `gen_pipeline_shadow` 中，新增一个 `resize_render_targets(renderer, new_w, new_h)` 方法。当 `app.nelua` 检测到 `viewport_resized` 时，除了更新主画布，还要遍历调用所有阴影管线的这个 resize 方法。

## 5. 测试演进策略

在实现上述功能时，建议按照以下步骤演进测试：

1. **修改 `smoke_phase3_11.lua`**：
   目前的测试断言依赖于 `reg.layout_results` 中的绝对坐标。需要将其更新为断言 `reg.layout_coeffs` 中的线性系数。例如，对于一个居中的组件，其 `cx_vw` 应该是 0.5。

2. **新增 `smoke_phase3_12.lua`**：
   专门测试生成的 `<App>:update` 中是否包含了正确的 `input.viewport_resized` 分支，以及系数注入的正确性。

3. **运行 Demo 验证**：
   编译并运行 `layout_demo`，手动拉伸窗口，验证 UI 组件是否能够平滑地进行响应式重排，且没有明显的性能下降或渲染闪烁。

## 6. 总结

Phase 3.12 的“编译期约束降维 + 运行时线性插值”方案是极其优雅的，它完美地兼顾了公理 A（阶段封闭性）和运行时的极致性能。通过在 S1 阶段进行多点采样，我们将复杂的 Flexbox 树遍历降维成了 O(N) 的扁平化线性计算，这正是 Nebula 架构哲学魅力的体现。

在具体实施时，最需要关注的是 WebGPU 底层资源的生命周期管理（Surface 重新配置、离屏纹理重建），确保底层渲染管线能够正确响应上层坐标的变化。
