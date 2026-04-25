# Demo 升级分析

## 可直接升级的 Demo（使用 nebula_derive_app + nebula_frame_render）

### 1. button_demo.nelua (Phase 2.4 → 3.9)
- 单个 ButtonVisual 组件，hoverable + clickable
- 升级方式：nebula_app_begin + nebula_app_register_component("button", "ButtonVisual") + nebula_frame_render
- 无文本、无 slot

### 2. simple_rect_demo.nelua (Phase 2.4 → 3.9)
- 单个 SimpleRectVisual 组件，hoverable
- 升级方式：同 button_demo，nebula_app_register_component("rect", "SimpleRectVisual")
- 无文本、无 slot

### 3. layout_demo.nelua (Phase 3.1 → 3.9)
- 7 个组件：card(CardVisual), title_rect(SimpleRectVisual), close_btn(ButtonVisual), email_input(InputVisual), password_input(InputVisual), cancel_btn(ButtonVisual), login_btn(ButtonVisual)
- 编译期 Flexbox 布局（需保留）
- 升级方式：nebula_app_begin + 7 个 nebula_app_register_component + nebula_frame_render
- 注意：InputVisual 此处无 editable 原语，仅 focusable；无 gap_buf 字段
- 无文本、无 slot

### 4. login_demo.nelua (Phase 3.6 → 3.9)
- 4 个形状组件 + 2 个文本组件
- 与 form_demo 几乎一模一样，直接参照 form_demo 改造
- 升级方式：nebula_app_register_component x4 + nebula_app_register_text x2 + nebula_frame_render
- 保留 Enter 键业务逻辑

## 需要特殊处理的 Demo

### 5. shadow_demo.nelua (Phase 2.5 → 3.9)
- ShadowButtonPipeline 使用 4-Pass 阴影渲染（3 个离屏 Pass + 1 个 Surface Pass）
- ShadowButtonPipeline:init 需要 (renderer, WIN_W, WIN_H) 而非 (renderer, max_instances)
- 有 update_uniforms / draw_shadow / draw_composite / draw 等特殊 API
- 问题：app_factory 的 gen_app_draw 只支持 standard_instanced 管线的 upload + draw_instanced
- 结论：shadow_demo 的 4-Pass 渲染无法直接用 nebula_frame_render 封装，因为 draw_shadow 需要在 Surface Pass 之前执行离屏 Pass，而 nebula_frame_render 只创建一个 Surface Pass
- **策略：保持手动渲染循环，但使用 nebula_derive_app 管理 App record + update**
  - 或者：不强行升级，保留原样作为低层 API 的示例
  - **最终决定：由于 shadow pipeline 的 4-pass 架构与 nebula_frame_render 的单 pass 模型不兼容，此 Demo 无法使用 Phase 3.9 API 升级。保留原样。**

### 6. text_demo.nelua (Phase 3.2.5 → 3.9)
- 纯文本展示，7 个 TextContext，无形状组件
- 手动加载字体图集、手动 update_uniforms、手动 draw_buffer
- 问题：nebula_app_register_text 要求 bound_to 绑定到 editable 组件，但此 Demo 是独立文本
- app_factory 的文本支持仅限于"绑定到 editable 组件的标签"
- 有动态更新（帧计数器每秒更新）
- **策略：此 Demo 无法使用当前 Phase 3.9 API 升级。保留原样。**

### 7. uniform_layout_test.nelua (Phase 2.1)
- 纯编译期测试，无 GLFW/WGPU，无渲染循环
- **策略：无需升级，保留原样。**
