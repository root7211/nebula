# Nebula GUI Compiler — Phase 3.5.4 已合入

> 当前仓库的**主线能力**已完成到 **Phase 2.5**。与此同时，**Phase 3.1（静态布局）、Phase 3.2.x（文本渲染子系统）、Phase 3.3.x（运行时动态列表与实例渲染）、Phase 3.4.1–3.4.4（键盘输入与基础单行 Input 组件）与 Phase 3.5.1–3.5.4（高层组件编排与渲染管线统一）已全部合入仓库**。Nebula 现已支持通过 `nebula_derive_app` 宏在编译期自动生成应用的 `init/update/draw` 代码序列，实现零样板代码的声明式 GUI 组装，同时引入了 Toggleable 正交原语与全面 Instancing 化渲染路径。

---

## 各阶段演进

| 项目 | Phase 0–2.5 | Phase 3.1 | Phase 3.2.x | Phase 3.3.x | Phase 3.4.x | Phase 3.5.x |
|---|---|---|---|---|---|---|
| 核心推导 | 形状 → 状态机/管线 | 静态 Flexbox 布局 | SDF 文本子系统 | 运行时动态列表与实例渲染 | 键盘输入与单行 Input 组件 | **编译期显式编排与全面 Instancing 化** |
| 渲染技术 | SDF 形状 + 多 Pass 阴影 | 布局对齐 | SDF 文本渲染 | Storage Buffer + Instanced 渲染 | 键盘事件流转 + 极简光标渲染 | **Standard Instanced Pipeline + 类型分组批量绘制** |
| 质量保障 | 手动验证 | 同左 | 31 项 Lua 断言 + 11 项编译回归 | 111 项断言 | 12/12 测试套件，全量回归集成 | **16/16 测试套件，150+ 项断言，全量回归通过** |

---

## 项目结构

```text
nebula/
├── src/
│   ├── nebula_core.nelua           # 编译期推导引擎（含 nebula_derive_app 宏）
│   ├── nebula_arena.nelua          # ★ Phase 3.3.1: Frame Arena 线性分配器
│   ├── stb_truetype_bindings.nelua # Phase 3.2.1: stb_truetype FFI 绑定
│   ├── text_runtime.nelua          # Phase 3.2.4: 文本运行时，字形顶点装配与上传
│   ├── derive/
│   │   ├── layout_engine.lua       # Phase 3.1: 编译期静态 Flexbox 布局引擎
│   │   ├── shader_compose.lua      # Phase 3.2.3 + 3.3.3 + 3.5.1: 着色器组合器（含 Standard Instanced）
│   │   ├── pipeline_factory.lua    # Phase 3.2.4 + 3.3.4 + 3.5.1: 管线工厂（含 Standard Instanced 路径）
│   │   ├── interaction_factory.lua # Phase 2.4 + 3.5.3: 交互原语工厂（含 Toggleable 正交原语）
│   │   ├── app_factory.lua         # ★ Phase 3.5.2: 编译期应用编排工厂
│   │   └── ... (其他派生模块)
│   └── ...
├── assets/
│   └── generated/                  # Phase 3.2.1: 自动生成的字体 SDF 图集与度量文件
├── tools/
│   ├── font_preprocessor.nelua     # Phase 3.2.1: 字体预处理工具（TTF → SDF Atlas）
│   ├── smoke_phase3_2_2.lua        # Phase 3.2.2: 管线工厂纹理路径冒烟测试
│   ├── smoke_phase3_2_3.lua        # Phase 3.2.3: 文本着色器组合器冒烟测试
│   ├── smoke_phase3_2_4.lua        # Phase 3.2.4: TextVisual 派生引擎冒烟测试
│   ├── verify_p2_4.lua             # Phase 2.4: 交互原语工厂验证
│   └── run_all_tests.sh            # ★ Phase 3.5.4: 全量回归测试运行器（16 项测试套件）
├── tests/
│   ├── smoke_arena.lua             # ★ Phase 3.3.1: Frame Arena 冒烟测试（27 项断言）
│   ├── smoke_phase3_3_2.lua        # ★ Phase 3.3.2: Storage Buffer 冒烟测试（20 项断言）
│   ├── smoke_phase3_3_3.lua        # ★ Phase 3.3.3: Instanced 着色器冒烟测试（34 项断言）
│   ├── smoke_phase3_3_4.lua        # ★ Phase 3.3.4: Instanced 管线工厂冒烟测试（30 项断言）
│   ├── smoke_phase3_4_1.lua        # ★ Phase 3.4.1: 键盘事件收集冒烟测试
│   ├── smoke_phase3_4_2.lua        # ★ Phase 3.4.2: 文本缓冲区逻辑冒烟测试
│   ├── smoke_phase3_4_3.lua        # ★ Phase 3.4.3: 光标渲染冒烟测试
│   ├── smoke_phase3_4_4.lua        # ★ Phase 3.4.4: login_demo 升级冒烟测试
│   ├── smoke_phase3_5_1.lua        # ★ Phase 3.5.1: Standard Instanced 管线冒烟测试（44 项断言）
│   ├── smoke_phase3_5_2.lua        # ★ Phase 3.5.2: App factory 编排冒烟测试（48 项断言）
│   ├── smoke_phase3_5_3.lua        # ★ Phase 3.5.3: Toggleable 原语冒烟测试（20 项断言）
│   └── smoke_phase3_5_4.lua        # ★ Phase 3.5.4: form_demo 综合集成冒烟测试（38 项断言）
├── examples/
│   ├── layout_demo.nelua           # Phase 3.1: 布局演示
│   ├── text_demo.nelua             # Phase 3.2.5: 文本渲染完整展示（7 个文本组件）
│   ├── dynamic_list_demo.nelua     # ★ Phase 3.3.5: 动态列表演示（10,000 项，1 Draw Call）
│   ├── login_demo.nelua            # ★ Phase 3.4.4: 登录框与键盘输入演示
│   └── form_demo.nelua             # ★ Phase 3.5.4: 表单演示（nebula_derive_app + 复选框）
├── docs/
│   ├── PLAN_PHASE3.md              # Phase 3 完整规划
│   ├── PLAN_PHASE3_5.md            # ★ Phase 3.5 详细规划（已更新为哲学驱动版本）
│   ├── PHASE3_3_OVERVIEW.md        # Phase 3.3 技术规划概述
│   ├── PHILOSOPHY_ANALYSIS_PHASE3_3.md # Phase 3.3 与核心哲学的兼容性分析
│   ├── PHASE3_3_SUITABILITY_ASSESSMENT.md # Phase 3.3 适配性评估
│   └── WASM_TARGET_ANALYSIS.md     # Nebula 编译到 WebAssembly 的可行性分析
├── build.sh                        # 一键构建脚本
└── README.md
```

---

## ★ Phase 3.5 核心：高层组件编排与渲染管线统一

Phase 3.5 是 Nebula 从"图形学库"向"真正 GUI 框架"跨越的关键阶段，分为 4 个子阶段交付。所有实现严格遵循 Nebula 的三大设计哲学：**零运行时开销、形状即渲染、声明意图派生代码**。

### Phase 3.5.1 — 全面 Instancing 化

`pipeline_factory.lua` 新增 `gen_pipeline_standard_instanced` 路径，通过 `spec.standard_instanced = true` 触发。将 Phase 3.3 引入的 Instanced 渲染思想**泛化为所有标准 Visual 类型的默认多实例渲染范式**，而非仅限于动态列表。

生成的 `<T>Pipeline` 同时具备：

| 方法 | 说明 |
|---|---|
| `init(renderer, max_instances)` | 创建 Storage Buffer、BindGroup、RenderPipeline |
| `upload(renderer, data_array, count)` | 将 CPU 端实例数组整体写入 Storage Buffer |
| `draw_instanced(pass, count)` | 一次 Draw Call 渲染 `count` 个实例 |

**架构意义**：消除了原有"单实例管线"与"Instanced 管线"的双轨制，确立了统一的多实例渲染范式。

### Phase 3.5.2 — 编译期显式编排

新增 `src/derive/app_factory.lua`，实现 `nebula_derive_app` 宏的编译期代码生成逻辑。

**使用方式：**

```nelua
## nebula_app_begin("FormApp")
##   nebula_app_register_component("card",        "CardVisual")
##   nebula_app_register_component("email_input", "InputVisual", {component_id=1})
##   nebula_app_register_component("login_btn",   "ButtonVisual")
## nebula_app_end()
## nebula_derive_app("FormApp")
```

**生成内容（93 行，完全等价于手写代码）：**

```nelua
-- 自动生成的 FormApp record（含共享 Pipeline 字段）
global FormApp = @record{
  card:        CardContext,
  email_input: InputContext,
  login_btn:   ButtonContext,
  pipe_card:   CardPipeline,     -- 共享 Pipeline（max_instances 自动计算）
  pipe_input:  InputPipeline,    -- InputVisual 有 2 个实例，max_instances=2
  pipe_button: ButtonPipeline,
  vw: float32, vh: float32,
}

-- 自动生成的 init/update/draw 方法（显式调用序列，无任何运行时黑盒）
function FormApp:init(renderer, vw, vh): boolean  ...  end
function FormApp:update(input, dt): void           ...  end
function FormApp:draw(pass): void                  ...  end
```

**核心设计原则**：生成的代码与手写代码完全等价，无虚函数、无反射、无运行时分发。同类型组件自动合并为一个 Instanced 批次，通过 `draw_instanced` 一次绘制。

**动态插槽支持**：通过 `nebula_app_register_slot` 声明占位符，生成器在 `draw` 方法中内联 Arena 遍历代码，实现静态表单与动态列表的无缝融合。

### Phase 3.5.3 — Toggleable 正交原语

`interaction_factory.lua` 新增 `nebula_gen_toggle_state(spec)` 函数，生成与主状态机**完全正交**的开关状态。

**生成的 Nelua 代码结构：**

```nelua
-- 正交状态记录（不是主状态机的一个状态）
global NebulaToggleState = @record{
  is_on:        boolean,  -- 当前开关状态
  just_toggled: boolean,  -- 本帧是否发生翻转
}

-- 追加到 process_input 末尾，不干扰主状态机优先级
function CheckboxContext:process_toggle(input: *NebulaInputState): void
  self.toggle.just_toggled = false
  if self.click.just_clicked then
    self.toggle.is_on = not self.toggle.is_on
    self.toggle.just_toggled = true
  end
end
```

**正交性保证**：`is_on` 不是主状态机的一个状态，不会与 `hovered`/`pressed`/`focused` 产生优先级冲突，可以同时为真。

### Phase 3.5.4 — form_demo 综合演示

`examples/form_demo.nelua` 使用 Phase 3.5 的全部新能力重写了 `login_demo`，新增"记住密码"复选框。

**代码量对比：**

| 指标 | login_demo (Phase 3.4.4) | form_demo (Phase 3.5.4) | 变化 |
|---|---|---|---|
| 应用组装代码 | ~250 行 | ~120 行 | **↓ 52%** |
| 手动管线初始化 | 8 行 | 1 行 (`form:init(...)`) | **↓ 87%** |
| 手动 update 调用 | 4 行 | 1 行 (`form:update(...)`) | **↓ 75%** |
| 手动 draw 调用 | 6 行 | 1 行 (`form:draw(pass)`) | **↓ 83%** |
| 新增组件（复选框） | — | 零额外样板代码 | ✓ |

```bash
bash build.sh form_demo
./build/form_demo
```

---

## ★ Phase 3.3 核心：运行时动态列表与实例渲染

Phase 3.3 是 Nebula 从"静态界面渲染"向"动态高性能应用"跨越的关键阶段，分为 5 个子阶段交付。

### Phase 3.3.1 — Frame Arena 分配器

`src/nebula_arena.nelua` 实现了一个零 GC 的线性内存分配器。每帧开始时调用 `nebula_arena_reset` 将游标归零，帧内所有动态分配均从预分配的后备内存块中线性取出，帧末整体"释放"（仅移动游标）。

```nelua
-- 使用示例：栈上后备内存，零堆分配
local arena_backing: [4096]uint8
local arena: NebulaArena
nebula_arena_init(&arena, &arena_backing[0], 4096)

-- 每帧
nebula_arena_reset(&arena)
local items = nebula_arena_alloc_array(&arena, #MyRecord, 16)
```

| 接口 | 复杂度 | 说明 |
|---|---|---|
| `nebula_arena_init` | O(1) | 初始化，绑定后备内存 |
| `nebula_arena_reset` | O(1) | 帧末归零游标，更新峰值统计 |
| `nebula_arena_alloc` | O(1) | 对齐分配，溢出返回 `nilptr` |
| `nebula_arena_alloc_array` | O(1) | 数组分配，含整数溢出保护 |

### Phase 3.3.2 — Storage Buffer 基础设施

在 `renderer.nelua` 中新增两个公共 GPU Buffer 创建 API：

- `nebula_create_storage_buffer(renderer, size, label, out_buf)` — 创建 `WGPUBufferUsage_Storage | CopyDst` 缓冲区
- `nebula_create_vertex_buffer(renderer, size, label, init_data, out_buf)` — 创建 `WGPUBufferUsage_Vertex | CopyDst` 缓冲区

两者均为现有 API 的**零破坏性扩展**，不修改任何已有函数签名。

### Phase 3.3.3 — Instanced 着色器组合器

`shader_compose.lua` 新增 `nebula_compose_instanced_shader(spec)` 函数，生成基于 `@builtin(instance_index)` 的 WGSL 着色器。

**生成的 WGSL 核心结构：**

```wgsl
// binding 0: 视口 Uniform（vec2<f32> 屏幕尺寸）
@group(0) @binding(0) var<uniform> viewport: Viewport;

// binding 1: 所有实例的数据数组（Storage Buffer）
@group(0) @binding(1) var<storage, read> instances: array<InstanceData>;

@vertex fn vs_main(
  @builtin(vertex_index)   vid: u32,
  @builtin(instance_index) iid: u32,
) -> VertexOutput {
  let inst = instances[iid];  // 通过 instance_index 索引数据
  // 每实例 6 顶点（两个三角形），无顶点缓冲
  ...
}
```

支持 `has_radius`（SDF 圆角）和 `has_border`（边框渲染）两个特性标志。

### Phase 3.3.4 — Instanced 管线工厂

`pipeline_factory.lua` 新增 `gen_pipeline_instanced` 路径，通过 `spec.instanced = true` 触发。生成的 `<T>InstancedPipeline` 包含以下 API：

| 方法 | 说明 |
|---|---|
| `init(renderer, max_instances)` | 创建 Storage Buffer、BindGroup、RenderPipeline |
| `update_viewport(renderer, vw, vh)` | 更新视口 Uniform（每次 resize 调用） |
| `upload(renderer, data, count)` | 将 CPU 端实例数组整体写入 Storage Buffer |
| `draw(pass, count)` | 一次 `wgpuRenderPassEncoderDraw(pass, 6, count, 0, 0)` |

**核心优势**：无论列表有多少项，始终只需 **1 个 BindGroup + 1 次 Draw Call**，彻底解决了 WebGPU 绑定数量瓶颈。

### Phase 3.3.5 — 动态列表 Demo

`examples/dynamic_list_demo.nelua` 展示了 Phase 3.3 的完整能力：

- **10,000 个列表项**，每帧只渲染可见的约 15 项（视锥裁剪）
- **1 次 Draw Call** 渲染所有可见项
- **Frame Arena** 管理每帧的 `ListItemInstanceData` 数组，零堆分配
- **鼠标滚轮滚动**，支持全列表范围（10,000 × 44px）
- **Hover 高亮**：通过 `component_id` 焦点链维护，hover 时边框变蓝

```bash
bash build.sh dynamic_list_demo
./build/dynamic_list_demo
```

---

## ★ Phase 3.2.5 核心：演示完善与全面回归测试

### text_demo 展示内容

| 组件 | 字号 | 颜色 | 用途 |
|---|---|---|---|
| 标题 | 48px | 白色 | 大字号 SDF 清晰度验证 |
| 副标题 | 28px | 蓝色 | 中等字号与颜色区分 |
| 正文（4 行） | 20px | 绿色 | 多行换行与行高计算验证 |
| ASCII 符号 | 16px | 橙色 | 全 ASCII 范围覆盖 |
| 小字号 | 14px | 灰色 | SDF 极小字号清晰度极限 |
| 帧计数器 | 24px | 白色 | **动态文本更新**（每秒刷新） |
| 大字号 | 64px | 淡紫色 | 大字号 SDF 质量验证 |

---

## 构建与运行

### 环境要求

- Linux x86_64 / WSL2
- Nelua 0.2.0-dev
- GCC 11+
- **wgpu-native v29.0.0.0**：需放置在 `vendor/wgpu-native`

### 编译与运行

```bash
chmod +x build.sh
./build.sh shadow_demo          # Phase 2.5 阴影演示
./build.sh layout_demo          # Phase 3.1 布局演示
./build.sh text_demo            # Phase 3.2.5 文本渲染完整展示
./build.sh dynamic_list_demo    # Phase 3.3.5 动态列表演示（10,000 项）
./build.sh login_demo           # Phase 3.4.4 登录框与键盘输入演示
./build.sh form_demo            # ★ Phase 3.5.4 表单演示（nebula_derive_app + 复选框）
```

### 运行全量回归测试

```bash
bash tools/run_all_tests.sh     # 运行全部 16 项测试套件（150+ 项断言）
```

---

## 阶段状态汇总

### Phase 2 主线进度 (Completed)
- [x] **Phase 2.1 – 2.5** — 自动对齐、着色器组合、管线工厂、交互原语、多 Pass 阴影。

### Phase 3 子阶段进度 (In Progress)
- [x] **Phase 3.1** — 编译期静态 Flexbox 布局系统。
- [x] **Phase 3.2.1** — 字体预处理工具链与 SDF 生成。
- [x] **Phase 3.2.2** — GPU 纹理上传与文本顶点缓冲区基础设施。
- [x] **Phase 3.2.3** — 文本着色器合成器（SDF 采样渲染）。
- [x] **Phase 3.2.4** — `TextVisual` 派生与 `text_demo` 演示。
- [x] **Phase 3.2.5** — 演示完善与全面回归测试。
- [x] **Phase 3.3.1** — Frame Arena 零 GC 线性分配器。
- [x] **Phase 3.3.2** — Storage Buffer GPU 基础设施。
- [x] **Phase 3.3.3** — Instanced 着色器组合器（`@builtin(instance_index)`）。
- [x] **Phase 3.3.4** — Instanced 管线工厂（`<T>InstancedPipeline`）。
- [x] **Phase 3.3.5** — 动态列表 Demo 与全量回归测试集成。
- [x] **Phase 3.4.1** — 键盘事件收集基础设施。
- [x] **Phase 3.4.2** — `InputContext` 文本缓冲区逻辑。
- [x] **Phase 3.4.3** — 极简光标渲染。
- [x] **Phase 3.4.4** — `login_demo` 升级与全量回归测试集成。
- [x] **Phase 3.5.1** — 全面 Instancing 化：Standard Instanced Pipeline 统一渲染范式。
- [x] **Phase 3.5.2** — 编译期显式编排：`nebula_derive_app` 宏与 `app_factory.lua`。
- [x] **Phase 3.5.3** — Toggleable 正交原语：`nebula_gen_toggle_state` 与正交状态机。
- [x] **Phase 3.5.4** — `form_demo` 综合演示与全量回归测试集成（16/16 套件通过）。
- [ ] **Phase 3.6** — （待规划）
