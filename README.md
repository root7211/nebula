> 当前仓库的**主线能力**已完成到 **Phase 2.5**。与此同时，**Phase 3.1–3.5、Phase 3.6.x（Gap Buffer + 命中测试 + 文本选区）、Phase 3.7（管线收敛与死代码清理）、Phase 3.8（渲染循环封装与 FrameArena 内嵌）与 Phase 3.9（文本一等公民 + Slot Producer 重构）已全部合入仓库**。Phase 3.9 引入 `nebula_app_register_text` 将文本组件纳入编译期自动编排（原语 3），并以 `producer` 纯函数模式重构动态插槽（原语 4），彻底消除 `form_demo` 中 40 行独立文本渲染 Pass 和 `dynamic_list_demo` 中 80 行 WGPU 渲染样板。

---

## 各阶段演进

| 项目 | Phase 0–2.5 | Phase 3.1 | Phase 3.2.x | Phase 3.3.x | Phase 3.4.x | Phase 3.5.x | Phase 3.6.x | Phase 3.7 | Phase 3.8 | Phase 3.9 |
|---|---|---|---|---|---|---|---|---|---|---|
| 核心推导 | 形状 → 状态机/管线 | 静态 Flexbox 布局 | SDF 文本子系统 | 运行时动态列表与实例渲染 | 键盘输入与单行 Input 组件 | 编译期显式编排与全面 Instancing 化 | **完整文本编辑交互：Gap Buffer + 选区支持** | **管线收敛：3 着色器 + 3 路径，~630 行死代码** | **渲染循环封装：nebula_frame_render + FrameArena 内嵌** | **文本一等公民（原语 3）+ Slot Producer 重构（原语 4）** |
| 渲染技术 | SDF 形状 + 多 Pass 阴影 | 布局对齐 | SDF 文本渲染 | Storage Buffer + Instanced 渲染 | 键盘事件流转 + 极简光标渲染 | Standard Instanced Pipeline + 类型分组批量绘制 | **L1/L2 分层 + 栈上即时排版，选区双锤点同步** | **standard_instanced 默认路径，阴影着色器使用真实 SDF** | **20 行 WGPU 样板 → 1 行；FrameArena 内嵌，无堆分配** | **文本管线自动注入；Producer 函数驱动动态插槽，Arena mark/rewind 局部回收** |
| 质量保障 | 手动验证 | 同左 | 31 项 Lua 断言 + 11 项编译回归 | 111 项断言 | 12/12 测试套件，全量回归集成 | 16/16 测试套件，150+ 项断言 | **19/19 套件，260+ 项断言** | **20/20 套件，smoke_phase3_7 专项** | **21/21 套件，smoke_phase3_8 专项验证** | **18/18 套件，全量回归 571/571 零失败（含 Phase 3.9 专项）** |

---

## 项目结构

```text
nebula/
├── src/
│   ├── nebula_core.nelua           # 编译期推导引擎（含 nebula_derive_app 宏）
│   ├── nebula_arena.nelua          # ★ Phase 3.9: Frame Arena（含 mark/rewind 局部回收）
│   ├── app.nelua                   # ★ Phase 3.8: 统一输入收集 + nebula_frame_render 封装
│   ├── stb_truetype_bindings.nelua # Phase 3.2.1: stb_truetype FFI 绑定
│   ├── text_runtime.nelua          # Phase 3.2.4: 文本运行时，字形顶点装配与上传
│   ├── derive/
│   │   ├── layout_engine.lua       # Phase 3.1: 编译期静态 Flexbox 布局引擎
│   │   ├── shader_compose.lua      # Phase 3.7: 收敛为 3 个公开函数（v0.6_phase3.7）
│   │   ├── pipeline_factory.lua    # Phase 3.7: 收敛为 3 条路径（v0.7_phase3.7）
│   │   ├── interaction_factory.lua # Phase 2.4 + 3.5.3 + 3.6.3: 交互原语工厂（含选区支持）
│   │   ├── app_factory.lua         # ★ Phase 3.9: 编排工厂 v0.3（文本一等公民 + Slot Producer）
│   │   └── ... (其他派生模块)
│   └── ...
├── assets/
│   └── generated/                  # Phase 3.2.1: 自动生成的字体 SDF 图集与度量文件
├── tools/
│   ├── font_preprocessor.nelua     # Phase 3.2.1: 字体预处理工具（TTF → SDF Atlas）
│   ├── run_all_tests.sh            # ★ Phase 3.9: 全量回归测试运行器（18 项测试套件，571 项断言）
│   └── ...
├── tests/
│   ├── smoke_phase3_9.lua          # ★ Phase 3.9: 文本一等公民 & Slot Producer 专项（64 项）
│   ├── smoke_phase3_8.lua          # Phase 3.8: nebula_frame_render & FrameArena 内嵌验证
│   ├── smoke_phase3_7.lua          # Phase 3.7: 管线收敛 & 死代码清理专项测试
│   ├── smoke_phase3_6_3.lua        # Phase 3.6.3: 文本选区专项回归测试（20 项）
│   └── ... (其他测试套件)
├── examples/
│   ├── form_demo.nelua             # ★ Phase 3.9: 文本一等公民（nebula_app_register_text，主循环 2 行）
│   ├── dynamic_list_demo.nelua     # ★ Phase 3.9: Slot Producer（10,000 项实例渲染，主循环 3 行）
│   └── login_demo.nelua            # Phase 3.4.4: 登录框与键盘输入演示
├── docs/
│   ├── PLAN_PHASE3_9.md            # ★ Phase 3.9 详细任务计划
│   ├── REPORT_PHASE3_9_COMPLIANCE.md # ★ Phase 3.9 架构合规性审查报告
│   ├── REPORT_DEAD_CODE_AUDIT.md   # ★ 死代码审查与清理报告
│   ├── ARCHITECTURE_GRAND_PLAN.md  # Nebula 架构总纲领
│   └── ...
├── build.sh                        # 一键构建脚本
└── README.md
```

---

## 构建与运行

### 环境要求
- Linux x86_64 / WSL2
- GCC 11+（`sudo apt-get update && sudo apt-get install -y gcc build-essential`）
- Nelua 0.2.0-dev（含 `nelua-lua` Lua 5.4 解释器，源码编译安装）
- **wgpu-native v29.0.0.0**
- GLFW 3（`libglfw3-dev`）

### 编译与运行
```bash
chmod +x build.sh
./build.sh form_demo            # ★ Phase 3.9: 文本一等公民表单演示
./build.sh dynamic_list_demo    # ★ Phase 3.9: Slot Producer 动态列表（10,000 项）
./build.sh login_demo           # Phase 3.4.4: 登录框演示
```

### 运行 Lua 冒烟测试（无需 GPU）
```bash
nelua-lua tests/smoke_phase3_9.lua   # Phase 3.9 专项（64 项）
nelua-lua tests/smoke_phase3_8.lua   # Phase 3.8 专项（30 项）
```

### 运行全量回归测试
```bash
bash tools/run_all_tests.sh     # 运行全部 18 项测试套件（571/571 零失败）
```
