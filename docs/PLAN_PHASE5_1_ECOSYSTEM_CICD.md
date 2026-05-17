# Phase 5.1：生态与 CI/CD

**创建日期**：2026-05-17
**基准状态**：Phase 5.0 已完成 | 77/77 回归全绿 | CI 覆盖 32 demo + 6 Job（smoke/compile-linux/compile-windows/compile-wasm/headless-render/static-analysis）+ GitHub Pages 部署
**更新日期**：2026-05-17

---

## 0. 动机：从"能跑"到"好用"

Phase 5.0 完成了 Nebula 编译期消解范式的理论极限——全知图构建了状态管理、绑定传播、事件路由的端到端编译期路径，440+ 断言全绿。这标志着 Nebula 的**核心能力层**已经收敛。

但一个工业级 GUI 框架的成功不仅取决于核心能力，还取决于：

| 维度 | 当前状态 | 目标状态 |
| :--- | :--- | :--- |
| **CI 质量** | 已有 6 Job 覆盖编译/测试/部署，但缺少性能回归守护、覆盖率追踪、发布自动化 | 完整的 CI/CD 流水线，含性能基线守护、覆盖率报告、语义化版本发布 |
| **开发者入门** | README 有构建说明，但缺少教程、API 文档、迁移指南 | 结构化文档站点 + 分步教程 + API 参考 |
| **包管理** | 无 | 支持 Nelua 包管理（neptune）或 Git submodule 方式分发核心库 |
| **WASM 生态** | 已有 5 个 WASM demo 可部署到 Pages，但缺少更多 demo 覆盖和在线 Playground | 完整 WASM demo 库 + 浏览器内实时编辑器 Playground |
| **社区协作** | 无 Issue 模板、无 PR 模板、无贡献指南 | 标准化的贡献流程和社区治理机制 |

Phase 5.1 的核心命题是：**把 Nebula 从一个"开发者的个人项目"升级为"可供他人使用的开源基础设施"。**

---

## 1. 总体策略

### 实施原则

1. **自动化优先**：所有可自动化的流程（测试、部署、文档生成）必须自动化，不依赖人工操作。
2. **质量门不可绕过**：CI 的性能基线和覆盖率检查是强制性的，任何 PR 不得绕过。
3. **渐进式文档**：文档不追求一次性完备，而是随功能迭代持续更新，但必须保持结构化和可发现性。
4. **向后兼容**：API 变更必须有迁移指南，破坏性变更必须有版本号标记。

### 梯队划分

```
S1 CI/CD 强化          → 性能回归守护 + 覆盖率追踪 + 发布自动化
S2 文档工程            → 文档站点 + 分步教程 + API 参考
S3 WASM 生态扩展        → 更多 WASM demo + Playground
S4 包管理支持          → Nelua 包分发 + 第三方组件生态基础
S5 社区治理            → 贡献指南 + Issue/PR 模板 + 代码审查规范
```

---

## 2. 第一梯队（S1）：CI/CD 强化

**目标**：从"能跑"升级为"可信任的质量守护系统"。

**预计产出**：修改 2 个文件 + 新增 3 个文件

### Step 1.1：性能回归守护

**文件**：`.github/workflows/perf-guard.yml`（新增）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 1.1.1 | 基准编译时间测试 | 对 32 demo 进行 `nelua -c` 计时，存储为 GitHub Actions 缓存基准 |
| 1.1.2 | 基准产物大小测试 | 记录每个 demo 的 C 代码行数、.wasm 文件大小 |
| 1.1.3 | 性能回归检测 | 对比基准值，超过 15% 退化时标注 warning，超过 30% 时 CI 失败 |
| 1.1.4 | 历史趋势图表 | 使用 GitHub Actions artifact + 简单的 Python 脚本生成趋势 Markdown 表格 |

**验收标准**：CI 能够检测并报告编译时间/产物大小的回归，PR 评论中自动显示性能变化。

### Step 1.2：测试覆盖率追踪

**文件**：`tools/gen_coverage_report.py`（新增）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 1.2.1 | 冒烟测试覆盖率统计 | 统计 `tests/smoke_*.lua` 覆盖的源文件数和行覆盖率 |
| 1.2.2 | C 代码覆盖率（可选） | 使用 `gcov` 对 `tools/headless_test.c` 进行覆盖率分析 |
| 1.2.3 | CI 集成覆盖率报告 | 在 CI 中生成并上传覆盖率报告作为 PR 注释 |

**验收标准**：每次 CI 运行后生成覆盖率报告，覆盖率不得低于 80%。

### Step 1.3：语义化版本发布自动化

**文件**：`.github/workflows/release.yml`（新增）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 1.3.1 | 基于 Git tag 的自动发布 | 创建 `vX.Y.Z` tag 后自动触发 Release 流程 |
| 1.3.2 | 变更日志自动生成 | 从 commit message 中提取 `feat:`、`fix:`、`docs:` 等分类生成 CHANGELOG |
| 1.3.3 | Release artifact 打包 | 打包源码 + 预编译 WASM demo + 文档为 Release 附件 |
| 1.3.4 | 预发布验证 | 发布前自动运行完整 CI 流水线，确保所有检查通过 |

**验收标准**：创建 tag 后 5 分钟内自动生成带 CHANGELOG 和 artifact 的 GitHub Release。

### Step 1.4：CI 性能优化

**文件**：`.github/workflows/ci.yml`（修改）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 1.4.1 | 依赖缓存 | 缓存 Nelua 编译器、wgpu-native 下载、Emscripten SDK |
| 1.4.2 | Job 并行化优化 | 将 smoke-tests 和 compile-linux 设为并行（无依赖关系） |
| 1.4.3 | 矩阵测试（可选） | 使用 GitHub Actions matrix 支持多 Nelua 版本测试 |

**验收标准**：CI 总运行时间从当前的 ~8 分钟优化到 ~5 分钟以内。

---

## 3. 第二梯队（S2）：文档工程

**目标**：建立结构化的文档体系，使新开发者能在 15 分钟内完成"从 0 到 1"的体验。

**预计产出**：新增 `docs/guide/` 目录 + 多个 Markdown 文件 + 文档生成脚本

### Step 2.1：文档站点结构

**目录结构**：

```
docs/
├── guide/                      # 开发者指南
│   ├── getting-started.md      # 快速开始（15 分钟从零到运行第一个 demo）
│   ├── tutorial-01-button.md   # 教程 1：按钮组件（从零理解核心概念）
│   ├── tutorial-02-layout.md   # 教程 2：Flexbox 布局（多组件排列）
│   ├── tutorial-03-editor.md   # 教程 3：文本编辑器（完整应用实战）
│   ├── tutorial-04-custom.md   # 教程 4：自定义原语（扩展框架）
│   └── migration.md            # 版本迁移指南
├── api/                        # API 参考
│   ├── core.md                 # 核心 API（nebula_annotate / nebula_derive / nebula_app）
│   ├── sugar.md                # 语法糖 API（nebula_visual / nebula_main / require "nebula"）
│   ├── primitives.md           # 原语参考（clickable / editable / scrollable / ...）
│   └── builtins.md             # 内置组件（line_nums / status_bar / search_bar / ...）
├── design/                     # 设计文档（现有文档移至此处）
│   ├── axioms.md               # 三大公理（从 ARCHITECTURE_GRAND_PLAN.md 提取）
│   ├── phase-history.md        # Phase 演进历史
│   └── ...                     # 其他现有设计文档
└── internal/                   # 内部开发文档
    ├── contributing.md         # 贡献指南
    ├── coding-style.md         # 编码规范
    └── release-process.md      # 发布流程
```

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 2.1.1 | 快速开始文档 | 新开发者按照文档操作，15 分钟内成功运行第一个 demo |
| 2.1.2 | 4 个分步教程 | 每个教程包含可运行的完整代码示例和预期输出截图 |
| 2.1.3 | API 参考文档 | 所有公开 API 都有签名、参数说明、使用示例 |
| 2.1.4 | 设计文档重组织 | 现有 `docs/` 下的设计文档分类到 `docs/design/` |

**验收标准**：文档站点结构完整，所有教程代码可直接复制运行。

### Step 2.2：文档生成与部署

**文件**：`.github/workflows/docs-deploy.yml`（新增）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 2.2.1 | Markdown → 静态站点 | 使用轻量级方案（如 MkDocs 或 VitePress）将 Markdown 转为可浏览的文档站点 |
| 2.2.2 | 自动部署到 Pages 子路径 | 文档部署到 `nebula/docs/` 路径，与 WASM demo 共存于同一 Pages 站点 |
| 2.2.3 | PR 预览 | 使用 actions 在 PR 中生成文档预览链接 |

**验收标准**：文档站点可通过 `https://root7211.github.io/nebula/docs/` 访问，内容随 main 分支更新自动发布。

### Step 2.3：内联注释规范

**文件**：`docs/internal/coding-style.md`（新增）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 2.3.1 | 源码注释规范 | 所有公开 API 必须有文档注释（格式：`/// docstring` 或 `--[[ doc ]]`） |
| 2.3.2 | Lua 宏注释规范 | `derive/` 下的 Lua 生成器代码必须有清晰的注释说明生成的代码结构 |
| 2.3.3 | 注释覆盖率检查 | CI 中新增步骤检查源码注释覆盖率 |

**验收标准**：核心源码文件（`src/nebula_core.nelua`、`src/derive/app_factory.lua` 等）的注释覆盖率不低于 60%。

---

## 4. 第三梯队（S3）：WASM 生态扩展

**目标**：扩大 WASM demo 覆盖面，建立浏览器内可交互的 Playground。

**预计产出**：新增 3 个 WASM demo + 1 个 Playground 应用

### Step 3.1：WASM demo 扩展

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 3.1.1 | `code_browser_demo` WASM 化 | 修复当前 WASM 渲染问题，使代码浏览器可在浏览器中运行 |
| 3.1.2 | `term_demo_v2` WASM 化 | 终端模拟器 WASM 版本（需处理 PTY 的浏览器适配） |
| 3.1.3 | `json_viewer_demo` WASM 化 | JSON 浏览器 WASM 版本 |
| 3.1.4 | `slider_demo` WASM 化 | 可编程原语验证的 WASM 版本 |
| 3.1.5 | `scrollable_demo` WASM 化 | 滚动容器 WASM 版本 |
| 3.1.6 | `dropdown_demo` WASM 化 | 下拉选择器 WASM 版本 |

**验收标准**：所有 WASM demo 均可在 Chrome 113+ 中正常运行，Pages 站点完整更新。

### Step 3.2：WASM 渲染修复

**文件**：`build_wasm.sh`、`src/app.nelua`（修改）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 3.2.1 | Surface 创建修复 | 确保 WebGPU Surface 在 WASM 环境下正确从 Canvas 创建 |
| 3.2.2 | 主循环适配 | 验证 `emscripten_set_main_loop` 回调正确执行 |
| 3.2.3 | 资源预加载 | 验证 `--preload-file` 正确打包字体和 SDF 图集 |
| 3.2.4 | 错误诊断工具 | 新增 WASM 专用的错误输出（浏览器 console.log 桥接） |

**验收标准**：WASM CI Job 从当前的 1 个 demo 验证扩展到至少 3 个 demo 验证。

### Step 3.3：在线 Playground（长期愿景）

**文件**：`playground/`（新增目录）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 3.3.1 | 前端编辑器 | 基于 Monaco Editor 的在线代码编辑器（Nebula 语法高亮） |
| 3.3.2 | WASM 沙箱 | 在 iframe 中运行用户编译的 WASM 代码 |
| 3.3.3 | 预置示例 | 内置 10 个可运行的示例代码（从教程中提取） |
| 3.3.4 | 代码分享 | 生成可分享的 URL（代码编码在 URL fragment 中） |

**技术选型**：由于 Nelua 编译到 C 需要在服务端完成，Playground 的编译步骤需要后端支持。可选方案：
- **方案 A**：预编译所有示例为 WASM，前端只做展示和切换
- **方案 B**：搭建轻量后端服务（Cloudflare Workers 或 Vercel Edge Function）处理编译
- **方案 C**：纯前端方案——使用 WebAssembly 版的 Nelua 编译器（如果未来存在）

**建议**：Phase 5.1 先实现方案 A（预编译展示），方案 B/C 留给后续迭代。

**验收标准**：Playground 可通过 `https://root7211.github.io/nebula/playground/` 访问，至少包含 10 个可运行的预置示例。

---

## 5. 第四梯队（S4）：包管理支持

**目标**：使 Nebula 可作为依赖库被其他 Nelua 项目引用。

**预计产出**：修改 2 个文件 + 新增 2 个文件

### Step 4.1：Nelua 包分发

**文件**：`neptune.json` 或 `nebula.pkg.json`（新增）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 4.1.1 | 包元数据定义 | 名称、版本、描述、依赖、入口文件 |
| 4.1.2 | 入口文件规范 | `nebula.nelua` 作为统一入口（`require "nebula"` 即可使用） |
| 4.1.3 | 依赖声明 | 声明对 `nelua-lang` 版本的要求（`>= 1.0`） |
| 4.1.4 | 打包脚本 | `tools/pack.nelua` — 生成可分发的包文件 |

**验收标准**：用户可通过 `neptune install nebula` 或 Git submodule 方式引入 Nebula，并运行最小 demo。

### Step 4.2：第三方组件生态基础

**文件**：`docs/guide/custom-component.md`（新增）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 4.2.1 | 自定义原语文档 | 详细说明 `nebula_register_primitive` API 的使用方式 |
| 4.2.2 | 自定义 Producer 文档 | 说明 Slot Producer 和 DenseText Producer 的扩展方法 |
| 4.2.3 | 组件模板 | 提供 `template_component.nelua` — 可复制粘贴的组件模板 |
| 4.2.4 | 示例组件仓库 | 提供 2-3 个独立的第三方组件示例（如 DatePicker、Toast 通知等） |

**验收标准**：开发者按照文档可以在 30 分钟内编写并测试一个自定义 Nebula 组件。

### Step 4.3：模板项目

**文件**：`template/`（新增目录）

| 子任务 | 内容 | 验收 |
| :--- | :--- | :--- |
| 4.3.1 | `template/minimal/` | 最小项目模板（1 个 demo + build.sh） |
| 4.3.2 | `template/editor/` | 文本编辑器项目模板（含完整配置） |
| 4.3.3 | `template/README.md` | 模板使用说明 |

**验收标准**：用户复制模板目录后即可开始自己的项目开发，无需额外配置。

---

## 6. 第五梯队（S5）：社区治理

**目标**：建立标准化的贡献流程和社区治理机制。

**预计产出**：新增 5 个文件

### Step 5.1：贡献指南

**文件**：`CONTRIBUTING.md`（新增）

| 内容 | 说明 |
| :--- | :--- |
| 开发环境搭建 | 详细的本地开发环境配置步骤 |
| 编码规范 | Nelua 和 Lua 的编码规范（缩进、命名、注释） |
| 提交流程 | commit message 格式规范（`feat:`、`fix:`、`docs:` 等） |
| 测试要求 | 新功能必须包含冒烟测试，回归测试全绿 |
| PR 流程 | PR 标题和描述模板，代码审查检查清单 |

### Step 5.2：Issue 和 PR 模板

**文件**：`.github/ISSUE_TEMPLATE/`（新增）

| 模板 | 用途 |
| :--- | :--- |
| `bug_report.md` | Bug 报告模板（环境、复现步骤、预期/实际行为） |
| `feature_request.md` | 功能请求模板（动机、设计方案、影响范围） |
| `doc_improvement.md` | 文档改进请求模板 |
| `PULL_REQUEST_TEMPLATE.md` | PR 模板（变更说明、测试验证、相关 Issue） |

### Step 5.3：代码审查规范

**文件**：`docs/internal/review-checklist.md`（新增）

| 检查项 | 说明 |
| :--- | :--- |
| 公理合规 | 变更是否违反三大公理？S1/S2 阶段划分是否正确？ |
| 生命周期 | 数据是否归属正确的生命周期层（L0/L1/L2）？ |
| 测试覆盖 | 是否有对应的冒烟测试？回归测试是否全绿？ |
| 向后兼容 | 是否破坏现有 API？如有破坏性变更，是否有迁移指南？ |
| 性能影响 | 编译时间是否显著增加？产物大小是否膨胀？ |
| 文档同步 | 是否有对应的文档更新？ |

### Step 5.4：变更日志规范

**文件**：`CHANGELOG.md`（新增）

| 版本 | 内容 |
| :--- | :--- |
| 格式 | 遵循 [Keep a Changelog](https://keepachangelog.com/) 规范 |
| 分类 | Added / Changed / Deprecated / Removed / Fixed / Security |
| 自动化 | 通过 release workflow 自动生成，人工补充说明 |

### Step 5.5：安全策略

**文件**：`SECURITY.md`（新增）

| 内容 | 说明 |
| :--- | :--- |
| 安全漏洞报告流程 | 如何报告安全相关的问题 |
| 支持版本 | 哪些版本仍然接受安全修复 |
| 已知限制 | 框架当前已知的安全限制（如沙箱隔离的边界） |

---

## 7. 不做列表（明确排除）

| 项目 | 理由 |
| :--- | :--- |
| 完整的 Nelua 编译器 WASM 化 | 复杂度极高，不属于 Nebula 框架本身的职责 |
| 多语言国际化（i18n） | 文档当前以中文为主，国际化留给社区贡献或后续迭代 |
| 商业级技术支持合同 | 开源项目初期不适宜引入商业约束 |
| 自动性能优化 | 性能回归检测是 CI 的职责，自动优化需要复杂的 profiling 基础设施 |
| 完整的 LSP 支持 | Nelua 语言的 LSP 是上游项目的职责，Nebula 可提供语法高亮规则 |

---

## 8. 与三大公理的关系

Phase 5.1 作为生态建设阶段，本身不直接涉及核心架构变更，但所有生态工具和工作流程必须与公理体系保持一致：

| 公理 | Phase 5.1 中的体现 |
| :--- | :--- |
| **Axiom A（阶段封闭）** | CI 中新增的"编译期 vs 运行时"检查点，确保未来 PR 不引入阶段违反 |
| **Axiom B（生命周期）** | 代码审查规范中包含生命周期检查项 |
| **Axiom C（形即渲染）** | 文档中明确标注每个 API 对应的管线签名映射规则 |

---

## 9. 风险与缓解

| 风险 | 影响 | 缓解 |
| :--- | :--- | :--- |
| 文档编写耗时过长 | 拖慢 Phase 进度 | 采用渐进式策略，先写核心 API 和教程，细节随功能迭代持续补充 |
| Playground 编译服务成本高 | 无法在 Phase 5.1 内实现完整 Playground | 先做方案 A（预编译展示），完整 Playground 留给后续 |
| CI 性能优化导致缓存失效 | 增加 CI 运行时间 | 使用 fine-grained 缓存 key（基于 lockfile hash），确保缓存命中率 |
| 包管理方案与 Nelua 官方冲突 | 未来 Nelua 引入官方包管理后不兼容 | 使用通用格式（JSON 元数据），避免锁定特定包管理器 |

---

## 10. 里程碑与验收标准

### 里程碑 1：CI/CD 强化完成

- [ ] 性能回归守护上线，CI 可自动检测编译时间/产物大小变化
- [ ] 测试覆盖率报告集成到 PR 流程
- [ ] 语义化版本发布自动化（创建 tag → 自动 Release）
- [ ] CI 总运行时间 ≤ 5 分钟

### 里程碑 2：文档站点上线

- [ ] `docs/guide/` 目录下有完整的快速开始 + 4 个教程
- [ ] `docs/api/` 目录下有所有公开 API 的参考文档
- [ ] 文档站点通过 GitHub Pages 可访问
- [ ] 新开发者可在 15 分钟内从零运行第一个 demo

### 里程碑 3：WASM 生态扩展完成

- [ ] 至少 8 个 WASM demo 可正常运行
- [ ] WASM CI Job 覆盖至少 3 个 demo
- [ ] Playground（方案 A）上线，包含至少 10 个预置示例

### 里程碑 4：包管理支持就绪

- [ ] 包元数据文件就绪
- [ ] 模板项目可用（minimal + editor）
- [ ] 自定义组件文档 + 示例完成

### 里程碑 5：社区治理机制建立

- [ ] CONTRIBUTING.md + Issue/PR 模板 + 代码审查规范全部就绪
- [ ] CHANGELOG.md 初始化
- [ ] SECURITY.md 发布

---

## 11. 与后续 Phase 的关系

Phase 5.1 完成后，Nebula 的生态基础设施将支撑以下未来工作：

| 后续 Phase | 依赖 Phase 5.1 的内容 |
| :--- | :--- |
| **Phase 5.2：动画系统** | CI 性能守护确保动画不引入回归；文档教程展示动画 API |
| **Phase 5.3：IME 输入法集成** | WASM Playground 提供在线验证环境 |
| **Phase 5.4：主题系统** | 包管理支持使第三方主题可独立分发 |
| **Phase 6.0：组件市场** | 第三方组件生态基础 + 包管理是组件市场的前置条件 |

---

## 12. 综合重要度评分

| 维度 | 得分 | 评分理由 |
| :--- | :--- | :--- |
| **A. 架构奠基性** | **6** | Phase 5.1 不引入新的核心抽象，主要是基础设施和流程建设 |
| **B. 公理合规性** | **7** | CI 中的公理检查和代码审查规范有助于防止未来 PR 违反公理 |
| **C. 开发者体验** | **10** | 文档、教程、Playground、包管理是开发者体验最大的跃升 |
| **D. 工业化就绪度** | **10** | CI/CD、发布自动化、社区治理是工业级项目的必要条件 |
| **E. 下游解锁度** | **9** | 解锁了所有未来 Phase 的社区协作和生态扩展能力 |
| **综合分** | **82** | `(6×0.30 + 7×0.20 + 10×0.20 + 10×0.15 + 9×0.15) × 10` |

**排名对比**：Phase 5.1（82 分）与 Phase 4.2.3 CJK 集成（82 分）并列，在综合排名中位于第 9 位，属于"能力扩展"层次（80-89 分）。
