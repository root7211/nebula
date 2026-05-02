# Terminal Emulator — Nebula 终端模拟器原型

基于 Phase 4.X Dense Text 渲染通道的最小可用终端模拟器。

## 架构

```
键盘输入 → GLFW callback → UTF-8/ANSI 编码 → PTY write → /bin/bash
                                                              ↓
GPU 渲染 ← DenseCharInstance[1920] ← TermBuffer ← ANSI parser ← PTY read
```

### 模块划分

| 文件 | 职责 |
|:-----|:-----|
| `examples/term/pty_bindings.nelua` | POSIX PTY C FFI 绑定（forkpty/read/write/fcntl） |
| `examples/term/ansi_parser.nelua` | ANSI/VT100 转义序列状态机 |
| `examples/term/term_buffer.nelua` | 终端单元格缓冲区（80×24 + 200 行滚动回看） |
| `examples/term_demo.nelua` | 终端模拟器主程序入口 |

所有终端应用代码位于 `examples/` 目录，不污染 `src/` 框架核心。

### 渲染层

复用 Phase 4.X Dense Text 管线（`nebula_derive` + `text_mode = "dense"`）：

- 每个终端单元格 = 1 个 `DenseCharInstance`（32 字节）
- 80×24 = 1920 个实例 → 单次 instanced draw call
- Per-cell 独立前景色 + 背景色（packed RGBA8）
- SDF 字形 atlas + Storage Buffer

### ANSI 解析器

逐字节状态机，支持：

- **SGR**（Select Graphic Rendition）：ANSI 16 色、256 色、TrueColor（38;2;r;g;b）
- **CSI 光标移动**：CUU/CUD/CUF/CUB/CUP（上/下/左/右/绝对定位）
- **CSI 清屏/擦行**：ED (CSI J) / EL (CSI K)
- **控制字符**：BS/TAB/LF/CR/BEL
- **OSC**：窗口标题等（静默忽略）

### PTY 层

- `forkpty()` 创建伪终端 + 子进程
- 子进程 `execvp("/bin/bash")`，设置 `TERM=xterm-256color`
- 父进程非阻塞读取（`O_NONBLOCK` + `EAGAIN` 处理）
- 每帧最多消耗 64KB PTY 输出

### 键盘输入

- 可打印字符：GLFW char callback → UTF-8 编码 → PTY write
- 特殊键：GLFW key callback → ANSI 转义序列转换
  - 方向键 → `ESC[A/B/C/D`
  - Home/End → `ESC[H/F`
  - Delete → `ESC[3~`
  - Ctrl+A~Z → 0x01~0x1A
  - Enter → CR, Backspace → DEL (0x7F)

### 光标

- 块光标（反色样式）
- 0.5 秒闪烁周期

## 构建与运行

```bash
./build.sh term_demo
LD_LIBRARY_PATH=vendor/wgpu-native/lib ~/.cache/nelua/term_demo
```

需要 Linux + GPU（Vulkan 或其他 WebGPU 后端）+ GLFW + libutil。

## 公理合规

- **公理 A**：TermVisual 编译期推导 → DenseTextPipeline 确定性映射
- **公理 B**：L0 管线/PTY fd，L1 TermBuffer 持久缓冲区，L2 帧级 DenseCharInstance 数组
- **公理 C**：形即渲染 — 声明 `text_mode = "dense"` 即得完整渲染管线

## 当前限制

- 仅 ASCII 渲染（CJK 需集成 Phase 4.2.3 的 dense text CJK 扩展）
- 无 alternate screen 支持（vim/htop 等全屏应用）
- 无鼠标事件转发
- 无窗口大小调整时的 PTY TIOCSWINSZ 同步
- 无选区复制/粘贴
