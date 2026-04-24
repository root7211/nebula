# Nebula GUI Compiler — Phase 3.6.3 已合入

> 当前仓库的**主线能力**已完成到 **Phase 2.5**。与此同时，**Phase 3.1–3.5（布局、文本、列表、组件编排）、Phase 3.6.1（Gap Buffer）、Phase 3.6.2（命中测试）与 **Phase 3.6.3（文本选区支持）已全部合入仓库**。Nebula 现已支持完整的文本编辑交互，包括 Shift+方向键选区扩展、鼠标拖拽选区、选区内批量删除等。所有实现严格遵循 L1/L2 分层公理，选区高亮计算完全在栈上即时完成，零持久缓存。

---

## 各阶段演进

| 项目 | Phase 0–2.5 | Phase 3.1 | Phase 3.2.x | Phase 3.3.x | Phase 3.4.x | Phase 3.5.x | Phase 3.6.x |
|---|---|---|---|---|---|---|---|
| 核心推导 | 形状 → 状态机/管线 | 静态 Flexbox 布局 | SDF 文本子系统 | 运行时动态列表与实例渲染 | 键盘输入与单行 Input 组件 | 编译期显式编排与全面 Instancing 化 | **完整文本编辑交互：Gap Buffer + 选区支持** |
| 渲染技术 | SDF 形状 + 多 Pass 阴影 | 布局对齐 | SDF 文本渲染 | Storage Buffer + Instanced 渲染 | 键盘事件流转 + 极简光标渲染 | Standard Instanced Pipeline + 类型分组批量绘制 | **L1/L2 分层 + 栈上即时排版，选区双锚点同步** |
| 质量保障 | 手动验证 | 同左 | 31 项 Lua 断言 + 11 项编译回归 | 111 项断言 | 12/12 测试套件，全量回归集成 | 16/16 测试套件，150+ 项断言 | **19/19 套件，260+ 项断言** |

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
│   │   ├── shader_compose.lua      # Phase 3.2.3 + 3.3.3 + 3.5.1: 着色器组合器
│   │   ├── pipeline_factory.lua    # Phase 3.2.4 + 3.3.4 + 3.5.1: 管线工厂
│   │   ├── interaction_factory.lua # Phase 2.4 + 3.5.3 + 3.6.3: 交互原语工厂（含选区支持）
│   │   ├── app_factory.lua         # ★ Phase 3.5.2: 编译期应用编排工厂
│   │   └── ... (其他派生模块)
│   └── ...
├── assets/
│   └── generated/                  # Phase 3.2.1: 自动生成的字体 SDF 图集与度量文件
├── tools/
│   ├── font_preprocessor.nelua     # Phase 3.2.1: 字体预处理工具（TTF → SDF Atlas）
│   ├── run_all_tests.sh            # ★ Phase 3.6.3: 全量回归测试运行器（19 项测试套件）
│   └── ...
├── tests/
│   ├── smoke_phase3_6_2.lua        # ★ Phase 3.6.2: 鼠标命中测试冒烟测试
│   ├── smoke_phase3_6_3.lua        # ★ Phase 3.6.3: 文本选区支持冒烟测试
│   └── ... (其他测试套件)
├── examples/
│   ├── login_demo.nelua            # ★ Phase 3.4.4: 登录框与键盘输入演示
│   └── form_demo.nelua             # ★ Phase 3.6.3: 表单演示（选区支持 + 命中测试）
├── docs/
│   ├── PLAN_PHASE3_6.md              # Phase 3.6 整体规划
│   ├── PLAN_PHASE3_6_3.md            # Phase 3.6.3 选区支持方案
│   ├── EXPLAIN_L1_L2_LAYERS.md       # L1/L2 分层架构详解文档
│   ├── ARCHITECTURE_GRAND_PLAN.md    # ★ Nebula 架构总纲领
│   └── ...
├── build.sh                        # 一键构建脚本
└── README.md
```

---

## 构建与运行

### 环境要求

- Linux x86_64 / WSL2
- Nelua 0.2.0-dev
- GCC 11+
- **wgpu-native v29.0.0.0**

### 编译与运行

```bash
chmod +x build.sh
./build.sh form_demo            # ★ Phase 3.6.3 表单演示（选区支持 + 命中测试）
```

### 运行全量回归测试

```bash
bash tools/run_all_tests.sh     # 运行全部 19 项测试套件
```
