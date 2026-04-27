# Nebula 代码审计笔记

## 1. 模块版本断言不一致

| 模块文件 | nebula_core.nelua 期望值 | 实际返回值 | 一致? |
|---|---|---|---|
| shader_compose.lua | `nebula_shader_compose_v0.6_phase3.7` | `nebula_shader_compose_v0.7_phase4.1` | **不一致** |
| pipeline_factory.lua | `nebula_pipeline_factory_v0.7_phase3.7` | `nebula_pipeline_factory_v0.8_phase4.1` | **不一致** |
| interaction_factory.lua | `nebula_interaction_factory_v0.7_phase3.10` | `nebula_interaction_factory_v0.7_phase3.10` | 一致 |
| layout_engine.lua | `nebula_layout_engine_v0.2_phase3.12` | `nebula_layout_engine_v0.2_phase3.12` | 一致 |
| app_factory.lua | `nebula_app_factory_v0.6_phase3.12` | `nebula_app_factory_v0.7_phase4.1` | **不一致** |
| axiom_validator.lua | `nebula_axiom_validator_v1.0_phase4.0` | `nebula_axiom_validator_v1.0_phase4.0` | 一致 |
| gap_buffer_factory.lua | `nebula_gap_buffer_factory_v0.1_phase3.6` | `nebula_gap_buffer_factory_v0.1_phase3.6` | 一致 |

3 个模块版本断言不一致：shader_compose, pipeline_factory, app_factory
