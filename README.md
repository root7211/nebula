# Nebula GUI Compiler — Phase 0

> "形即（Shape-Is）"范式的最小可验证实现：从带注解的 `record` 规格中，通过编译期推导引擎自动派生 GPU 渲染管线与状态机。

Nebula 是一个基于 Nelua 和 WebGPU (wgpu-native v29) 的零开销 GUI 框架。在 Phase 0 中，我们验证了核心的"形即"架构：开发者只需定义数据规格，框架在编译期自动派生 WGSL Uniform 布局和状态转换逻辑，运行时仅执行纯粹的数据插值和 GPU 提交，无需任何虚函数调用或复杂的对象树遍历。

## 项目结构

```text
nebula/
├── src/
│   ├── nebula_core.nelua      # 编译期推导引擎（Shape Parser、WGSL 生成器、状态机生成器、lerp 库）
│   ├── wgpu_bindings.nelua    # wgpu-native v29.0.0.0 的 Nelua FFI 绑定
│   ├── glfw_bindings.nelua    # GLFW 3 的 Nelua FFI 绑定
│   ├── primitives.nelua       # 交互原语层（HoverableState、ClickableState）
│   └── renderer.nelua         # WebGPU 渲染层（设备初始化、Surface 格式查询、SDF 渲染管线）
├── examples/
│   └── button_demo.nelua      # Phase 0 Demo：带悬停/点击动画的交互按钮
├── tools/
│   └── headless_test.c        # 离屏渲染验证工具（C 语言，用于测试着色器和 Uniform 布局）
├── build.sh                   # 一键构建脚本
└── README.md                  # 项目文档
```

## Phase 0 验证的核心假设

**开发者只需编写规格，框架在编译期派生一切结构性代码。**

在 `examples/button_demo.nelua` 中，开发者只需定义 `ButtonVisual` 并附加状态注解：

```nelua
global ButtonVisual = @record{
  pos: Vec2, size: Vec2, radius: float32,
  default_bg_color: Color, hovered_bg_color: Color, pressed_bg_color: Color,
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
```

**编译期推导引擎（`nebula_core.nelua`）自动输出：**

```text
=== [编译期] 推导引擎输出 ===
派生的 WGSL Uniform 结构体：
struct NebulaUniforms {
  pos: vec2<f32>,
  size: vec2<f32>,
  radius: f32,
  bg_color: vec4<f32>,
  border_color: vec4<f32>,
  border_width: f32,
  viewport: vec2<f32>,
}

状态机节点：default, hovered, pressed
视觉属性数量：3
Uniform 字节大小：96
===========================
```

## 构建与运行

### 环境要求

- **操作系统**：Linux x86_64 或 Windows WSL2 (Ubuntu)
- **编译器**：GCC 11+ 或 Clang
- **语言**：Nelua 0.2.0-dev（需安装到 PATH 中）
- **依赖库**：GLFW 3（`sudo apt install libglfw3-dev`）
- **WebGPU**：wgpu-native v29.0.0.0

### 安装 wgpu-native

本项目依赖 wgpu-native v29。由于体积较大，未包含在代码库中。请按照以下步骤下载并解压到 `vendor` 目录：

```bash
mkdir -p vendor
cd vendor
wget https://github.com/gfx-rs/wgpu-native/releases/download/v29.0.0.0/wgpu-linux-x86_64-release.zip
unzip wgpu-linux-x86_64-release.zip -d wgpu-native
rm wgpu-linux-x86_64-release.zip
cd ..
```

### 编译与运行

```bash
# 赋予执行权限
chmod +x build.sh

# 编译并运行 Demo
./build.sh
```

**运行指引：**

- **Linux / WSL2 (带图形界面)**：
  ```bash
  LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/button_demo
  ```
  *(注：WSL2 环境下会自动通过 d3d12 层使用 Vulkan 后端。请确保已启用 WSLg 以显示窗口。)*

- **无头服务器 (使用 Xvfb)**：
  ```bash
  Xvfb :99 -screen 0 1024x768x24 &
  DISPLAY=:99 LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/button_demo
  ```

## 技术要点与 Phase 0 修复记录

| 层次 | 实现方式 | 零开销验证 |
|------|---------|-----------|
| **编译期推导引擎** | Nelua `##[[...]]` 预处理器块，Lua 执行 | 不产生任何运行时代码 |
| **WGSL 生成** | 遍历 `record` 字段，映射到 WGSL 类型 | 着色器字符串在编译期确定 |
| **状态机** | 从 `transitions` 注解展开 if-else 链 | 无虚表、无动态分发 |
| **动画插值** | 内联的 `lerp_color` / `lerp_f32` 调用 | 纯数据变换，直接映射到 Uniform |
| **GPU 渲染** | wgpu-native v29 + 全屏三角形 SDF | 每帧仅 1 次 draw call |

在 Phase 0 的开发中，我们解决了几个关键的 WebGPU 适配问题：
1. **Surface 格式查询**：放弃硬编码格式，使用 `wgpuSurfaceGetCapabilities` 动态查询，并强制过滤 sRGB 格式（如 `BGRA8UnormSrgb`），避免了在 WSL2 下因 Gamma 编码导致的黑屏问题。
2. **WGSL 坐标系**：在 Fragment Shader 中直接使用 `@builtin(position).xy` 获取像素坐标，无需通过 Varying 传递。
3. **Present 顺序**：严格遵循 `wgpuSurfacePresent` → `wgpuTextureViewRelease` → `wgpuTextureRelease` 的生命周期顺序，避免了交换链错误。
4. **Uniform 内存对齐**：根据 std140 规则，在 Nelua 结构体中手动添加 `_pad` 字段，确保 `vec4` (16字节) 和 `vec2` (8字节) 的严格对齐，最终布局大小为 96 字节。

## Phase 1 展望

在当前的 Phase 0 代码中，`ButtonContext`、`ButtonStateMachine` 和 Uniform 结构体仍需在 `button_demo.nelua` 中手动展开以验证架构可行性。

在 Phase 1 中，这些代码将由推导引擎从 `nebula_annotate` 注解中**完全自动生成**。届时，开发者只需提供 `ButtonVisual` 的 `record` 定义和注解，框架将在编译期生成所有的状态机、上下文和插值样板代码，实现真正的"形即"零开销抽象。
