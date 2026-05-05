# Terminal Emulator v2 Demo — Sugar 化终端模拟器

> **目标**: 用 Nebula L2 sugar 重写 `term_demo.nelua`（489 行），验证 sugar 体系对非编辑器应用的通用性
> **预期**: ~60-80 行主文件 + 已有的 `term/` 模块（pty_bindings + ansi_parser + term_buffer）
> **日期**: 2026-05-06
> **前置**: Phase 4.9.1 已完成（text_editor_demo 886→19 行，46.6x）

---

## 1. 诊断：v1 的 489 行里有什么

| 段落 | 行数 | 功能 | sugar 可消除？ |
|------|------|------|---------------|
| 配置常量 | ~10 | WIN_W/H, GRID, CELL_W/H, ORIGIN | 可合并到 app spec |
| Visual record + derive | ~15 | `TermVisual` record + nebula_annotate/derive | ✅ `dense = N` |
| PTY 管理 | ~55 | `start_shell()` + `stop_shell()` | ❌ 应用逻辑 |
| 键盘回调 | ~95 | `term_key_callback` + `term_char_callback` | 部分可框架化 |
| main 初始化 | ~50 | glfw + renderer + font + pipeline + init | ✅ `nebula_init` 已有 |
| 主循环读 PTY | ~25 | 非阻塞读 + ANSI feed | ❌ 应用逻辑 |
| 构建实例数组 | ~45 | 遍历 grid → DenseCharInstance | ✅ Producer 模式 |
| 光标渲染 | ~28 | 反色块光标 | ❌ 应用逻辑 |
| GPU 提交 | ~60 | surface texture + encoder + pass + submit + present | ✅ 框架已有 |
| cleanup | ~8 | deinit + terminate | ✅ 框架已有 |

**核心发现**: 489 行中约 250 行是 GPU 渲染样板（可被框架吸收），约 100 行是 PTY/键盘应用逻辑（不可消除），约 140 行是"胶水"（初始化、配置、循环控制，可大幅压缩）。

---

## 2. 设计思路

### 2.1 终端 vs 编辑器的根本差异

| 维度 | text_editor_demo | term_demo |
|------|-----------------|-----------|
| 数据流 | 用户输入 → Gap Buffer → Producer 读取 | PTY 输出 → TermBuffer → Producer 读取 |
| 原语 | `multiline_editable` (交互式) | 无原语（纯展示） |
| 键盘 | 框架处理（process_input） | 自定义回调（转发到 PTY） |
| 组件类型 | EditorBgVisual + 4 个 DenseText | 1 个 DenseText（全屏 grid） |
| 布局 | 搜索栏 + 行号 + 编辑区 + 状态栏 | 单一全屏 grid |
| 光标 | 框架渲染 | 自定义反色块 |

**结论**: 终端模拟器不适合 `nebula_editor_main`，它需要自定义主循环。但 **组件声明 + DenseText 管线** 部分完全可复用 sugar。

### 2.2 Sugar 复用点

| Sugar | 编辑器用法 | 终端用法 |
|-------|-----------|---------|
| `dense = N` | ✅ 4 个 DenseText | ✅ 1 个全屏 grid |
| `nebula_app` | ✅ 声明 6 个组件 | ✅ 声明 1 个组件 + 自定义 loop |
| `nebula_visual` | ✅ EditorBgVisual | ❌ 不需要（纯 DenseText） |
| `builtin` | ✅ line_nums/status_bar/search_bar/edit_area | ❌ 不适用（无内置 Producer） |
| `cell = { w, h }` | ✅ 10×16 | ✅ 12×18（终端用等宽字体更大） |
| `highlight_builtins` | ✅ 语法高亮 | ❌ 不适用（ANSI 颜色） |
| `nebula_editor_main` | ✅ 一行启动 | ❌ 需要自定义循环 |

### 2.3 终端专用新功能

v2 需要引入一个轻量扩展：

**`nebula_terminal_main(app_type, opts)`** — 终端专用主循环模板

类似 `nebula_editor_main`，但：
- 不读取 `multiline_editable` 的编辑状态
- 注册自定义 key/char callback（转发到 PTY）
- 主循环内：读 PTY → feed ANSI → 构建实例 → GPU 提交
- 光标闪烁定时器
- 自动处理 window close + cleanup

参数：
```lua
nebula_terminal_main("TermApp", {
  grid       = { cols = 80, rows = 24 },
  cell       = { w = 12.0, h = 18.0 },
  shell      = "/bin/bash",      -- 默认
  title      = "Nebula Terminal",
  fill       = "nebula_fill_term_grid",  -- 自定义 Producer
})
```

---

## 3. 终态目标：term_demo_v2.nelua（~55 行）

```nelua
-- term_demo_v2.nelua — 终端模拟器 v2（Sugar 化）
require "nebula"
require "pty_bindings"
require "ansi_parser"
require "term_buffer"

-- 自定义 Producer: TermBuffer → DenseCharInstance
## cinclude "<stdio.h>"
global function nebula_fill_term_grid(
  app: auto, instances: *[0]DenseCharInstance, count: *uint32, max: uint32
): void
  local tb = &app._term_buf  -- 由 nebula_terminal_main 注入
  local grid = &app.grid
  local idx: uint32 = 0
  for row = 0, < grid.rows do
    for col = 0, < grid.cols do
      local cell = tb:get_cell(row, col)
      nebula_dense_grid_fill_instance(
        &instances[idx], row, col, cell.codepoint,
        grid.origin_x, grid.origin_y, grid.cell_w, grid.cell_h,
        cell.fg, cell.bg)
      idx = idx + 1
    end
  end
  count[0] = idx
end

-- App 声明（1 个全屏 DenseText 组件）
## nebula_app("TermApp", {
##   cell = { w = 12.0, h = 18.0 },
##   grid = { cols = 80, rows = 24 },
##   components = {
##     { name = "grid", dense = 2048, producer = "nebula_fill_term_grid",
##       flex_grow = 1 },
##   },
## })

-- 终端主循环（PTY + ANSI + 光标闪烁 + 自定义键盘）
## nebula_terminal_main("TermApp", {
##   shell = "/bin/bash",
##   title = "Nebula Terminal",
## })
```

### 行数预算

| 段落 | 行数 | 说明 |
|------|------|------|
| require + cinclude | 5 | nebula + pty + ansi + term_buf |
| Producer 函数 | 15 | `nebula_fill_term_grid`（应用逻辑，不可消除） |
| nebula_app | 8 | 组件声明 + dense/sugar |
| nebula_terminal_main | 4 | 终端主循环入口 |
| **总计** | **~32 行主代码 + 注释 ≈ 55 行** | |

压缩比: 489 → 55 行 (**8.9x**)

---

## 4. `nebula_terminal_main` 实现方案

### 4.1 生成代码结构

`nebula_terminal_main("TermApp", opts)` 在 S1 生成 ~150 行 Nelua 源码：

```nelua
-- 生成的 main() 函数结构：
local function main(): int32
  -- 1. 标准 Nebula 初始化
  local renderer: NebulaRenderer
  local app: TermApp
  if not nebula_init(&renderer, &app, "Nebula Terminal", 1220, 440) then
    return 1
  end

  -- 2. PTY 初始化
  local pty_master_fd: cint = -1
  local pty_child_pid: pid_t = 0
  -- ... forkpty + start_shell ...

  -- 3. 自定义键盘回调注册
  glfwSetKeyCallback(renderer.window, _term_key_handler)
  glfwSetCharCallback(renderer.window, _term_char_handler)

  -- 4. TermBuffer + ANSI Parser 初始化
  app._term_buf:init(24, 80)
  local parser: AnsiParser
  parser:init()

  -- 5. 主循环
  while glfwWindowShouldClose(renderer.window) == 0 do
    glfwPollEvents()

    -- 光标闪烁
    ...

    -- 读 PTY + ANSI feed
    local buf: [8192]uint8
    while true do
      local n = nebula_pty_read(pty_master_fd, &buf[0], 8192)
      if n <= 0 then break end
      for i = 0, < (@csize)(n) do
        local ev: AnsiEvent
        if parser:feed(buf[i], &ev) then
          app._term_buf:handle_event(&ev, &parser)
        end
      end
    end

    -- Nebula 标准渲染管线（DenseText auto-producer）
    nebula_frame_begin(&renderer, &app)
    nebula_frame_end(&renderer, &app)
  end

  -- 6. Cleanup
  stop_shell()
  nebula_deinit(&renderer, &app)
  return 0
end
main()
```

### 4.2 PTY 组件注入

`nebula_terminal_main` 在 `TermApp` record 生成时注入两个额外字段：

```
_term_buf: TermBuffer    -- 终端字符缓冲区
grid: TermGridConfig     -- { cols, rows, cell_w, cell_h, origin_x, origin_y }
```

这通过在 `nebula_app` 之后、`nebula_terminal_main` 之前，用 `inject_statement` 注入 record 字段扩展来实现。

### 4.3 键盘处理

沿用 v1 的 `term_key_callback` + `term_char_callback` 逻辑，但封装为 `nebula_terminal_main` 内部的生成代码。关键映射：

| GLFW Key | ANSI 序列 | 功能 |
|----------|----------|------|
| ENTER (257) | CR (0x0D) | 回车 |
| BACKSPACE (259) | DEL (0x7F) | 退格 |
| UP/DOWN/LEFT/RIGHT | ESC[A/B/C/D | 方向键 |
| HOME/END | ESC[H / ESC[F | 行首/行尾 |
| DELETE | ESC[3~ | 删除 |
| Ctrl+A-Z | 0x01-0x1A | 控制字符 |

### 4.4 文件结构

```
src/nebula_core.nelua:
  + nebula_terminal_main(app_type, opts)  -- ~200 行生成代码

examples/term_demo_v2.nelua:              -- ~55 行（新）
examples/term/pty_bindings.nelua:         -- 119 行（不变）
examples/term/ansi_parser.nelua:          -- 389 行（不变）
examples/term/term_buffer.nelua:          -- 295 行（不变）
```

---

## 5. 实施步骤

| # | 任务 | 文件 | 预计 |
|---|------|------|------|
| 1 | 验证 v1 term_demo 仍可编译运行 | build.sh | 5min |
| 2 | 实现 `nebula_terminal_main` | nebula_core.nelua | 2h |
| 3 | 创建 `term_demo_v2.nelua` | examples/ | 30min |
| 4 | 注册 v2 target | build.sh | 5min |
| 5 | 编译运行 + 交互测试 | terminal | 15min |
| 6 | regression 77/77 | run_all_tests.sh | 2min |
| 7 | commit + push | git | 5min |

**总预计**: ~3 小时

---

## 6. 与编辑器 demo 的对称性验证

| 维度 | text_editor_demo_v3 | term_demo_v2 |
|------|---------------------|--------------|
| 行数 | 19 | ~55 |
| 原始行数 | 886 | 489 |
| 压缩比 | 46.6x | 8.9x |
| DenseText 组件 | 4 个 (search/line_nums/edit/status) | 1 个 (全屏 grid) |
| Producer | 4 个 builtin | 1 个自定义 |
| 主循环 | `nebula_editor_main` | `nebula_terminal_main` |
| 键盘处理 | 框架内置 | 自定义回调 |
| 布局 | 多组件嵌套 | 单组件全屏 |

**验证目标**: 证明 sugar 体系（dense/builtin/app/main）是**应用类型无关**的。编辑器和终端是两种完全不同的交互模式，但共享相同的组件声明 + DenseText 管线。

---

## 7. 风险

| 风险 | 缓解 |
|------|------|
| PTY 在 WSL 下行为异常 | v1 已验证 PTY 可用，复用相同逻辑 |
| `nebula_terminal_main` 生成代码过长（200行） | 分阶段：先手写 v2 main()，再逐步模板化 |
| TermBuffer/AnsiParser 需要注入到 App record | `inject_statement` 扩展 record 字段 |
| 光标闪烁需要 dt 计算 | `nebula_frame_begin` 已提供 `dt` |
| v1 的键盘回调需要 pty_master_fd 全局变量 | 模板化后通过 app record 传递 |

---

## 8. 后续可能性

如果 v2 验证成功，可进一步：

1. **Tab bar**: 多终端标签页（多个 TermBuffer，一个 DenseText grid）
2. **滚动回看**: TermBuffer 已有 scrollback，加 scrollbar 组件
3. **分割视图**: 多个终端 grid 用 `children` 布局
4. **主题切换**: 终端默认配色 (Solarized/Monokai) 通过 `nebula_theme_*` 切换
5. **标题栏**: 复用 `nebula_builtin_status_bar` 显示当前目录/进程名

---

*文档版本: 1.0*
*最后更新: 2026-05-06*
