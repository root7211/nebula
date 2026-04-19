# Nebula GUI Compiler — Phase 1

> "形即（Shape-Is）"范式的编译期代码生成阶段：开发者只写**形状声明 + 注解**，框架在编译期自动派生 `State` 枚举、`StateMachine` 与 `Context` 全部样板代码。运行时仍然只是数据插值与一次 GPU 提交。

Phase 1 在 Phase 0 的"编译期推导引擎可看到形状"基础上，进一步把 Phase 0 中需要在 demo 文件内手写的 **状态枚举 / 状态机记录与方法 / 运行时上下文** 全部下沉到 `nebula_derive()`，由 Lua 预处理器在编译期通过 `aster.parse + inject_statement` 直接注入到调用点。

---

## 与 Phase 0 的对比

| 项目 | Phase 0 | Phase 1 |
|---|---|---|
| 状态枚举 `<T>State` | 手写 | **`nebula_derive` 自动生成** |
| 状态机 `<T>StateMachine` 记录 + 方法 | 手写 | **`nebula_derive` 自动生成** |
| 上下文 `<T>Context` 记录 + `init` / `update` / `to_uniforms` | 手写 | **`nebula_derive` 自动生成** |
| 状态间属性插值（`lerp_color` / `lerp_f32` / …） | 手写调用链 | **按字段类型自动派生调用** |
| `nebula_annotate` / `nebula_gen_wgsl_uniform` | 已有 | 完全保留，向后兼容 |
| Uniform std140 padding | 手写 `_pad` | 仍手写（**Phase 2 的目标**） |
| 着色器 WGSL | 硬编码字符串 | 仍硬编码（**Phase 2 的目标**） |

---

## 项目结构

```text
nebula/
├── src/
│   ├── nebula_core.nelua      # 编译期推导引擎 + ★ nebula_derive() 生成器
│   ├── wgpu_bindings.nelua    # wgpu-native v29.0.0.0 的 Nelua FFI 绑定
│   ├── glfw_bindings.nelua    # GLFW 3 的 Nelua FFI 绑定
│   ├── primitives.nelua       # 交互原语层（HoverableState、ClickableState）
│   └── renderer.nelua         # WebGPU 渲染层（Phase 0 沿用）
├── examples/
│   ├── button_demo.nelua      # Phase 1 单组件 Demo（仅形状 + 注解 + derive）
│   └── login_demo.nelua       # Phase 1 多组件 Demo（Card / Input / Button 全派生）
├── docs/
│   └── DESIGN_PHASE1.md       # Phase 1 设计说明
├── tools/
│   └── headless_test.c        # 离屏渲染验证工具
├── build.sh                   # 一键构建脚本（与 Phase 0 兼容）
└── README.md
```

---

## Phase 1 的核心 API：`nebula_derive(type_name)`

调用者只需要：

```nelua
global ButtonVisual = @record{
  pos: Vec2, size: Vec2, radius: float32,
  default_bg_color:  Color, hovered_bg_color:  Color, pressed_bg_color:  Color,
  default_border_color: Color, hovered_border_color: Color, pressed_border_color: Color,
  default_border_width: float32, hovered_border_width: float32, pressed_border_width: float32,
}

##[[
nebula_annotate("ButtonVisual", {
  states     = {"default", "hovered", "pressed"},
  primitives = {"hoverable", "clickable"},
  transitions = {
    {from="default", to="hovered", tween="ease_out", duration=0.15},
    {from="hovered", to="default", tween="ease_out", duration=0.15},
    {from="hovered", to="pressed", tween="none",     duration=0.0},
    {from="pressed", to="hovered", tween="ease_out", duration=0.1},
  },
})
]]

## nebula_derive("ButtonVisual")
```

`nebula_derive` 在编译期发出：

- `global ButtonState = @enum{ Default=0, Hovered=1, Pressed=2 }`
- `global ButtonStateMachine = @record{...}` 及其 `init / transition_to / update / get_t` 方法（`transitions` 拓扑展开为 if-else 链）。
- `global ButtonContext = @record{ visual, sm, hover, click, current_bg_color, current_border_color, current_border_width }` 及 `init / update / to_uniforms`，自动按字段类型选择 `lerp_color` 或 `lerp_f32`。
- 命名约定：源类型若以 `Visual` 结尾（如 `ButtonVisual`），派生符号自动剥离后缀（`Button*`）；否则保留原名（`Foo*`）。

**编译期日志**会输出形如：

```text
[derive] ButtonVisual: emit State + StateMachine + Context (3 props, 4 transitions)
```

---

## 实现要点

| 层次 | 实现方式 | 零开销验证 |
|------|---------|-----------|
| 注解注册 | `nebula_annotate(type_name, spec)` | 仅在编译期 Lua 表存活 |
| 形状解析 | `nebula_parse_shape` 遍历 `T.value.fields` | 无运行时反射 |
| 代码生成 | Lua 拼接 Nelua 源码 → `aster.parse` → 逐条 `inject_statement` | 注入产物等价于手写代码 |
| 命名映射 | `<Visual>` 后缀剥离 → 派生 `<Base>State / <Base>StateMachine / <Base>Context` | 静态确定 |
| 状态优先级 | `pressed > hovered > default` 自动展开为 if-else | 无虚分发 |
| 属性插值 | `Color → lerp_color`、`float32 → lerp_f32`、`Vec2 → lerp_vec2` | 全部内联 |

---

## 构建与运行

### 环境要求

- Linux x86_64 / WSL2
- Nelua 0.2.0-dev（[GitHub 安装](https://github.com/edubart/nelua-lang)）
- GCC 11+
- GLFW 3：`sudo apt install libglfw3-dev`
- wgpu-native v29.0.0.0：

```bash
mkdir -p vendor && cd vendor
wget https://github.com/gfx-rs/wgpu-native/releases/download/v29.0.0.0/wgpu-linux-x86_64-release.zip
unzip wgpu-linux-x86_64-release.zip -d wgpu-native
rm wgpu-linux-x86_64-release.zip
```

### 编译

```bash
chmod +x build.sh
./build.sh button_demo   # 单组件 Phase 1 Demo
./build.sh login_demo    # 多组件 Phase 1 Demo
```

### 运行

```bash
LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/button_demo
# 或在无显示环境下使用 Xvfb
Xvfb :99 -screen 0 1024x768x24 &
DISPLAY=:99 LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/button_demo
```

---

## 已知遗留问题

1. **多管线渲染稳定性**：`login_demo` 在 Phase 0 即存在多 pipeline 并发渲染的运行时显示问题。Phase 1 的派生器侧验证已通过（编译 + 初始化日志均正常），但实际窗口呈现需要在带显示的环境下进一步验证。
2. **Input 的 focus 状态**：派生器目前默认仅识别 `hovered` / `pressed` 优先级；`focused` 仍由 demo 在 `update` 后通过显式 `transition_to` 驱动。Phase 1.1 计划：在注解中支持自定义状态优先级映射。

---

## Phase 2 展望

- WGSL 着色器按字段自动组合（`radius` → SDF 圆角矩形分支、`shadow` → 高斯模糊 Pass）。
- Uniform 内存布局完全自动化，删除手写 `_pad` 字段。
- 原语自动派生（`hoverable` 直接从 `pos/size` 字段派生 AABB 测试代码）。
