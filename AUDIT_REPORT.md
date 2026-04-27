# Nebula 项目代码审计报告

**审计日期**：2026-04-27  
**审计基线**：`main` 分支 HEAD（git checkout 后 working tree clean）  
**当前阶段**：Phase 4.2.2（Slug 渲染内核生产级化）

---

## 一、总览

本次审计对 nebula 项目进行了六个维度的系统性检查：模块版本断言、类型与符号引用、管线绑定布局、公理校验器白名单、函数签名一致性、以及冒烟测试覆盖度。共发现 **7 个错误**（其中 3 个为编译阻断级，4 个为运行时/逻辑错误），以及 **1 个代码卫生问题**。

---

## 二、编译阻断级错误（Severity: CRITICAL）

### BUG-1：nebula_core.nelua 模块版本断言过期（3 处）

`nebula_core.nelua` 中的版本断言仍停留在 Phase 3.7 / 3.12 时期，但对应的 `derive/*.lua` 模块已升级到 Phase 4.1。编译时会立即触发 `assert` 失败，阻断所有 Demo 的编译。

| 行号 | 断言期望值 | 模块实际返回值 | 差异 |
|------|-----------|---------------|------|
| 570 | `nebula_shader_compose_v0.6_phase3.7` | `nebula_shader_compose_v0.7_phase4.1` | 版本 + 阶段均不匹配 |
| 575 | `nebula_pipeline_factory_v0.7_phase3.7` | `nebula_pipeline_factory_v0.8_phase4.1` | 版本 + 阶段均不匹配 |
| 590 | `nebula_app_factory_v0.6_phase3.12` | `nebula_app_factory_v0.7_phase4.1` | 版本 + 阶段均不匹配 |

**修复方案**：将 `nebula_core.nelua` 第 570、575、590 行的断言字符串更新为对应模块的实际返回值。

---

### BUG-2：axiom_validator.lua L1 白名单缺少 `NebulaBuf255`

`form_demo.nelua` 中 `InputVisual` 的 `gap_buf` 字段类型为 `NebulaBuf255`（由 editable 原语的 `nebula_gen_gap_buffer_type(255)` 动态生成）。然而 `axiom_validator.lua` 的 `L1_TYPE_ALLOWLIST` 白名单中没有包含该类型，导致编译时触发 `[Axiom-B 违规]` 错误。

**根因分析**：`NebulaBuf255` 是 Phase 3.6 引入的动态生成类型，但 Phase 4.0 引入的公理校验器没有为 editable 原语注入的类型添加豁免逻辑。白名单是静态的，无法感知编译期动态生成的类型名。

**修复方案**（二选一）：

1. **动态豁免**（推荐）：在 `nebula_validate_visual_fields` 中添加对 `NebulaBuf%d+` 模式的正则豁免，即：若类型名匹配 `^NebulaBuf%d+$` 则视为合法 L1 类型。
2. **静态白名单**：在 `L1_TYPE_ALLOWLIST` 中硬编码 `["NebulaBuf255"] = true`，但这会在用户使用不同 `max_text_len` 时再次失败。

---

### BUG-3：`nebula_create_uniform_buffer` 函数不存在

`pipeline_factory.lua` 第 686 行的 Slug 管线 `init` 方法中调用了 `nebula_create_uniform_buffer`，但该函数在整个项目中**没有定义**。`renderer.nelua` 中只有 `nebula_pipeline_base_init`（内部创建 uniform buffer）和 `nebula_create_storage_buffer`，没有独立的 `nebula_create_uniform_buffer` 公共 API。

**影响范围**：任何使用 `text_mode = "slug"` 的 Visual 类型在编译时都会因链接错误而失败。当前 `form_demo` 使用 `text_mode = "ascii_sdf"` 所以未触发此问题。

**修复方案**：在 `renderer.nelua` 中新增 `nebula_create_uniform_buffer` 函数，或将 Slug 管线的 `init` 方法改为使用已有的 `nebula_pipeline_base_init` 或内联创建 uniform buffer。

---

## 三、运行时 / 逻辑错误（Severity: HIGH）

### BUG-4：standard_instanced 管线 Storage Buffer 绑定缺少顶点着色器可见性

`pipeline_factory.lua` 第 513-514 行中，`gen_pipeline_standard_instanced` 为 binding 1（Storage Buffer）设置的 visibility 仅为 `WGPUShaderStage_Fragment`：

```lua
emit("    visibility  = (@uint64)(WGPUShaderStage_Fragment),")
```

然而，`shader_compose.lua` 生成的 WGSL 着色器在**顶点着色器**中通过 `let d = instances[inst];` 读取了该 Storage Buffer。wgpu 运行时校验会检测到着色器在 VERTEX 阶段访问了一个仅对 FRAGMENT 可见的绑定，导致管线创建失败并触发 panic。

**实际表现**：编译成功，但运行时在创建 Checkbox 管线时崩溃（`wgpu uncaptured error: Shader global ResourceBinding { group: 0, binding: 1 } is not available in the pipeline layout — Visibility flags don't include the shader stage`）。

**修复方案**：将第 513 行改为：
```lua
emit("    visibility  = (@uint64)(WGPUShaderStage_Vertex) | (@uint64)(WGPUShaderStage_Fragment),")
```

---

### BUG-5：`nebula_create_storage_buffer` 签名与 Slug 管线调用不匹配

`renderer.nelua` 中 `nebula_create_storage_buffer` 的签名为：
```
(out_buf: *WGPUBuffer, renderer: *NebulaRenderer, size: uint64, label: cstring)
```

但 `pipeline_factory.lua` 第 717-719 行生成的 Slug 管线代码以 **5 个参数**调用它：
```
nebula_create_storage_buffer(&self.curve_buf, renderer, curves, curves_size, "label")
```

这里传入了 `curves`（data 指针）和 `curves_size`（大小），但函数定义只接受 `size` 和 `label`，没有 `data` 参数。这意味着 Storage Buffer 创建后**没有上传初始数据**，渲染时会读取未初始化的 GPU 内存。

**修复方案**：扩展 `nebula_create_storage_buffer` 的签名以接受 `data: pointer` 参数，并在创建后通过 `wgpuQueueWriteBuffer` 上传数据；或在 Slug 管线中改为先创建 buffer 再单独调用 `wgpuQueueWriteBuffer`。

---

### BUG-6：`NEBULA_SLUG_BAND_REFS` 类型不匹配（`uint16` vs `uint32`）

`assets/generated/liberation_sans_slug_metrics.nelua` 中定义：
```
global NEBULA_SLUG_BAND_REFS: [8811]uint16 <const>
```

但 `app_factory.lua` 第 494 行计算 band_refs 缓冲区大小时使用了 `#uint32`：
```lua
emit("    local _refs_sz = (@csize)(NEBULA_SLUG_TOTAL_BAND_REFS * #uint32)")
```

这导致计算出的缓冲区大小是实际数据大小的 **2 倍**（uint32 = 4 字节，uint16 = 2 字节），上传到 GPU 的数据会越界读取。同时，WGSL 着色器中 `slug_band_refs` 声明为 `array<u32>`，与 CPU 端 `uint16` 数组不匹配，会导致渲染结果完全错误。

**修复方案**：统一 CPU 端和 GPU 端的类型。要么将 `NEBULA_SLUG_BAND_REFS` 改为 `uint32` 数组（增加内存但简化逻辑），要么将 WGSL 着色器改为 `array<u16>` 并修正 `app_factory.lua` 中的大小计算为 `#uint16`。

---

### BUG-7：`text_runtime.nelua` 缺少 `require "liberation_sans_slug_metrics"`

`text_runtime.nelua` 第 1-2 行仅导入了：
```
require "renderer"
require "liberation_sans_ascii_48_metrics"
```

但第 405 行引用了 `NebulaSlugGlyph`、第 417 行引用了 `NEBULA_SLUG_ASCENT` 等符号，这些均定义在 `assets/generated/liberation_sans_slug_metrics.nelua` 中。缺少 `require "liberation_sans_slug_metrics"` 会导致 Slug 文本路径编译失败。

**当前影响**：`form_demo` 使用 `text_mode = "ascii_sdf"` 未触发此路径。但任何使用 `text_mode = "slug"` 的 Demo 都会因未解析符号而编译失败。

**修复方案**：在 `text_runtime.nelua` 第 2 行后添加：
```
require "liberation_sans_slug_metrics"
```

---

## 四、代码卫生问题（Severity: LOW）

### HYGIENE-1：`renderer.nelua` 中 `nebula_create_vertex_buffer` 重复定义

`renderer.nelua` 在第 500 行和第 1224 行各定义了一次 `nebula_create_vertex_buffer`，两者签名和实现几乎完全相同（仅参数名 `out_buffer` vs `out_buf` 不同）。这是 Phase 3.2.2 到 Phase 3.3 重构时遗留的重复代码。

**修复方案**：删除第 500-525 行的旧定义，保留第 1224 行的版本。

---

## 五、冒烟测试覆盖度评估

Phase 4.2.1 冒烟测试（`tests/smoke_phase4_2_1.lua`）**全部 43 项通过**。但该测试仅覆盖了：

- 跨平台条件编译标志的存在性
- Surface 创建路径的完整性
- 主循环宏的正确性
- 行数收敛约束

**未覆盖的关键区域**：

| 未覆盖项 | 对应 BUG |
|----------|---------|
| 模块版本断言一致性 | BUG-1 |
| 管线绑定布局与着色器可见性匹配 | BUG-4 |
| 公理校验器白名单与动态类型兼容性 | BUG-2 |
| Slug 管线辅助函数存在性 | BUG-3 |
| 函数签名参数数量匹配 | BUG-5 |
| CPU/GPU 类型一致性 | BUG-6 |

---

## 六、修复优先级建议

| 优先级 | BUG ID | 描述 | 阻断级别 |
|--------|--------|------|---------|
| P0 | BUG-1 | 版本断言过期（3 处） | 编译阻断 |
| P0 | BUG-2 | L1 白名单缺少 NebulaBuf255 | 编译阻断 |
| P0 | BUG-4 | Storage Buffer 缺少 VERTEX 可见性 | 运行时崩溃 |
| P1 | BUG-3 | nebula_create_uniform_buffer 未定义 | Slug 路径编译阻断 |
| P1 | BUG-5 | nebula_create_storage_buffer 签名不匹配 | Slug 路径运行时错误 |
| P1 | BUG-6 | band_refs uint16/uint32 类型不匹配 | Slug 渲染结果错误 |
| P1 | BUG-7 | text_runtime 缺少 slug_metrics 导入 | Slug 路径编译阻断 |
| P2 | HYGIENE-1 | nebula_create_vertex_buffer 重复定义 | 无功能影响 |

> **P0 级别的 BUG-1、BUG-2、BUG-4 是当前 `form_demo` 无法编译运行的直接原因**，修复这三个问题后 `form_demo`（ascii_sdf 路径）即可正常编译和运行。P1 级别的 BUG-3/5/6/7 均影响 Slug 文本渲染路径，需在 Phase 4.2.2 推进前修复。
