# 文档状态索引

**更新日期**：2026-05-25

本文档集中标注 `docs/` 下所有规划文档的当前状态。

## 归档（Phase 已完成，文档保留为历史参考）

| 文件 | Phase | 状态 | 说明 |
| :--- | :--- | :--- | :--- |
| `DESIGN_PHASE1.md` | Phase 1 | 归档 | Phase 1 已完成，设计哲学已融入主线 |
| `PLAN_PHASE2.md` | Phase 2 | 归档 | Phase 2 已完成，管线生成体系已落地 |
| `PLAN_PHASE3.md` | Phase 3 | 归档 | Phase 3 已完成，多组件系统已落地 |
| `PLAN_PHASE3_6.md` | Phase 3.6 | 归档 | Gap Buffer 生命周期设计，已实现 |
| `PLAN_PHASE4_1.md` | Phase 4.1 | 归档 | Slug 渲染引擎设计，已完成 |
| `PLAN_PHASE4_1_IMPL.md` | Phase 4.1 | 归档 | Slug 渲染引擎实现详情，已完成 |
| `PLAN_PHASE4_2_3_CJK.md` | Phase 4.2.3 | 归档 | HarfBuzz + CJK 集成，S0/S1/S2 已完成 |
| `PLAN_PHASE4_3.md` | Phase 4.3 | 归档 | 可编程原语注册表，已完成 |
| `PLAN_PHASE4_3_TASK_D.md` | Phase 4.3 | 归档 | process_body 公理校验，已完成并接入编译流程 |
| `PLAN_PHASE4_5_S3_SUGAR.md` | Phase 4.5-S3 | 归档 | 语法糖深化实施方案，已完成 |
| `PLAN_PHASE4_7_BEFORE_4_5.md` | Phase 4.7→4.5 | 归档 | 调序方案已完成，已按此路径实施 |
| `PLAN_PHASE4_8_EDITOR.md` | Phase 4.8 | 归档 | 编辑器功能规划，S1-S6 + NL 已完成 |
| `PLAN_PHASE4_9_FIFTY_LINES.md` | Phase 4.9 | 归档 | 50 行终态收敛方案，已完成（最终 19 行） |
| `PLAN_PHASE4_9_1_SYNTAX.md` | Phase 4.9.1 | 归档 | 语法打磨终态，已完成 |
| `PLAN_PHASE4_X_DENSE_TEXT.md` | Phase 4.X | 归档 | 高密度文本渲染通道，Step 1-5 已完成 |
| `PLAN_PHASE4_X_JSON_VIEWER.md` | Phase 4.X-J | 归档 | JSON Viewer 实施方案，已完成 |
| `PLAN_NESTED_LAYOUT.md` | Phase 4.8-NL | 归档 | 嵌套布局实施方案，已完成 |
| `PLAN_TERM_DEMO.md` | Phase 4.X-T | 归档 | 终端模拟器原型方案，已完成 |
| `PLAN_TERM_DEMO_V2.md` | Phase 4.X-T2 | 归档 | Terminal v2 sugar 方案，已完成 |
| `REPORT_PHASE4_2_2_BENCH.md` | Phase 4.2.2 | 归档 | Storage Buffer 基准测试报告，PASSED |
| `PLAN_SYNTAX_UNIFICATION.md` | Phase 4.6 | 归档 | 语法统一化方案，已完成 |
| `PLAN_PHASE5_3_RENDER_REGISTRY.md` | Phase 5.3 | 归档 | 渲染侧可编程注册表，Step 1-5 已完成（107 条断言全绿） |
| `PLAN_PHASE5_4_ANIMATION.md` | Phase 5.4 | 归档 | 声明式动画系统深化，Step 1-5 已完成（149 条断言全绿） |

## 活跃（仍在指导开发）

| 文件 | 说明 |
| :--- | :--- |
| `ARCHITECTURE_GRAND_PLAN.md` | 架构总纲领 — 持续维护的根文档 |
| `PLAN_ERA2_MASTER.md` | Era II 实施总计划 — Phase 5.0 已完成，Phase 5.1/5.2 规划中 |
| `PHASE_IMPORTANCE_SCORECARD.md` | Phase 重要度评分卡 — 新 Phase 加入时需更新 |
| `TEXT_EDITOR_ROADMAP.md` | 文本编辑器长期愿景 — 历史参考 + 未来方向 |
| `ROADMAP_INDUSTRY_RESEARCH.md` | 行业对标研究 — 持续相关 |
| `WASM_TARGET_ANALYSIS.md` | WebAssembly 可行性分析 — WASM 渲染问题修复前持续相关 |
| `PLAN_ARCHITECTURE_AUDIT.md` | 架构审计与整改方案 — 全代码库审计发现的 P0-P3 问题清单与五梯队实施计划 |
| `PLAN_PHASE5_1_ECOSYSTEM_CICD.md` | Phase 5.1 生态与 CI/CD — 5 梯队：CI/CD 强化 → 文档工程 → WASM 生态 → 包管理 → 社区治理 |
| `PLAN_PHASE5_2_SUGAR_FIX.md` | Phase 5.2 语法糖体系修复 — R1/R2/R3/R4/R5 已完成 |
| `PLAN_PHASE5_OMNISCIENT_GRAPH.md` | Phase 5.0 全知图与端到端特化路径 — ✅ 已完成（S1a-S5 五个梯队，440+ 断言全绿） |

## 历史资产

| 文件 | 说明 |
| :--- | :--- |
| `screenshots/` | login_demo 截图（4 张）— 早期 UI 展示 |

## 维护指南

- 当 Phase 标记为"已完成"时，对应 PLAN 文件状态更新为"归档"
- 归档文件不删除，保留为设计决策的历史参考
- 新文档添加到"活跃"区，完成后再移至"归档"
