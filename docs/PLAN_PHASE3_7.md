# Phase 3.7：管线生成器收敛与死代码清理

**作者**：Manus AI
**日期**：2026-04-24
**前置**：Phase 3.6.3（文本选区与修饰键支持）已完成
**对应纲领**：`ARCHITECTURE_GRAND_PLAN.md` 原语 1（唯一管线生成器），消除张力 1（双脑渲染）与张力 2（管线分发的五条路径）
**预估工期**：1 周（5 个工作日）

---

## 1. 目标与动机

Phase 3.7 的核心目标是**将 Nebula 的着色器组合器和管线生成器从当前的"多代码路径分裂"状态收敛到架构纲领所定义的三条显式路径**，同时删除所有已被实质取代的死代码。

### 1.1 当前问题

经过对代码库的逐行审计，当前 `shader_compose.lua`（378 行）和 `pipeline_factory.lua`（1011 行）中存在以下架构债务：

**着色器组合器（shader_compose.lua）四路分裂**：

| 函数 | 引入 Phase | 当前状态 | 活跃调用方 |
| :--- | :--- | :--- | :--- |
| `nebula_compose_shader` | 2.2 | **半死代码**：fragment 阶段返回红色占位符 `vec4<f32>(1.0, 0.0, 0.0, 1.0)`，但 shadow 子着色器仍由此函数生成 | `nebula_core.nelua`（非 instanced 路径） |
| `nebula_compose_text_shader` | 3.2 | **活跃** | `nebula_core.nelua`（text_mode 路径） |
| `nebula_compose_instanced_shader` | 3.3 | **遗留** | `dynamic_list_demo.nelua`、`smoke_phase3_3_3.lua` |
| `nebula_compose_shader_instanced` | 3.5.1 | **活跃** | `nebula_core.nelua`（instanced 路径） |

**管线生成器（pipeline_factory.lua）五路分发**：

| 函数 | 引入 Phase | 行数 | 当前状态 | 分发条件 |
| :--- | :--- | :--- | :--- | :--- |
| `gen_pipeline_simple` | 2.3 | 47-97 | **待废弃** | `else`（默认兜底） |
| `gen_pipeline_textured_vertex` | 3.2.2 | 107-192 | **活跃** | `textured && vertex_layout=="pos_uv"` |
| `gen_pipeline_shadow` | 2.5 | 211-490 | **活跃** | `has_shadow==true` |
| `gen_pipeline_standard_instanced` | 3.5.1 | 522-722 | **活跃**（推荐路径） | `standard_instanced==true` |
| `gen_pipeline_instanced` | 3.3.4 | 725-925 | **遗留** | `instanced==true`（旧路径） |

**核心矛盾**：`nebula_core.nelua` 中的 `nebula_derive` 函数在 `instanced=false` 且 `has_shadow=false` 时，会走 `gen_pipeline_simple` 路径，使用 `nebula_compose_shader` 生成的**红色占位符着色器**。这意味着 `button_demo`、`simple_rect_demo`、`layout_demo`、`login_demo` 等未设置 `instanced=true` 注解的 demo，其主管线实际上渲染的是红色占位符。与此同时，`form_demo` 通过 `nebula_derive_app` 生成的 `FormApp:draw` 调用了 `upload` + `draw_instanced` 方法，但这些方法只存在于 `gen_pipeline_standard_instanced` 生成的管线中——而 form_demo 的 Visual 注解均未设置 `instanced=true`。**这是一个需要在 Phase 3.7 中彻底解决的架构不一致**。

### 1.2 目标状态

Phase 3.7 完成后，管线生成器应收敛为**三条显式具名路径**，由两个注解层布尔位决定：

| 路径 | 选择条件 | 着色器组合器 | 管线生成器 |
| :--- | :--- | :--- | :--- |
| **standard_instanced**（默认） | 其他全部情况 | `nebula_compose_shader_instanced` | `gen_pipeline_standard_instanced` |
| **text_vertex** | `text_mode == "ascii_sdf"` | `nebula_compose_text_shader` | `gen_pipeline_textured_vertex` |
| **shadow_multipass** | `has_shadow == true` | `nebula_compose_shader_instanced` + shadow 子着色器 | `gen_pipeline_shadow`（重构后） |

---

## 2. 详细任务分解

### Task 3.7.1：将 `standard_instanced` 设为默认路径（Day 1）

**目标**：修改 `nebula_core.nelua` 中的 `nebula_derive` 函数，使所有非文本、非阴影的 Visual 自动走 `standard_instanced` 路径，无需在 `nebula_annotate` 中显式声明 `instanced=true`。

**具体变更**：

1. 在 `nebula_core.nelua` 的 `nebula_derive` 函数（第 1003-1123 行）中，将 `use_instanced` 的默认值从 `reg.instanced or false` 改为 `true`，除非 `has_shadow == true`：

```lua
-- 旧逻辑
local use_instanced = reg.instanced or false

-- 新逻辑
local use_instanced = not feats.has_shadow  -- 非阴影 Visual 一律走 standard_instanced
```

2. 保留 `reg.instanced` 注解字段的读取，但将其语义从"启用 instanced"改为"覆盖 max_instances"：

```lua
local max_instances = reg.max_instances or 128
```

3. 更新 `nebula_annotate` 的文档注释，说明 `instanced` 字段已废弃，`standard_instanced` 现在是默认行为。

**验收标准**：

- `button_demo`、`simple_rect_demo`、`layout_demo`、`login_demo` 在不修改 `nebula_annotate` 调用的情况下，自动走 `standard_instanced` 路径。
- 编译期日志中出现 `[derive-instanced] ButtonVisual: standard_instanced path` 等信息。
- `form_demo` 的 `FormApp:draw` 调用 `upload` + `draw_instanced` 不再产生方法不存在的编译错误。

---

### Task 3.7.2：删除 `nebula_compose_shader` 的占位符 fragment（Day 1-2）

**目标**：消除 `shader_compose.lua` 中 `nebula_compose_shader` 函数的红色占位符 fragment 着色器。

**具体变更**：

1. 由于 Task 3.7.1 已将所有非阴影 Visual 切换到 `nebula_compose_shader_instanced`，`nebula_compose_shader` 的主着色器（`source` 字段）将不再被任何活跃路径使用。

2. 但 `nebula_compose_shader` 仍然负责生成阴影子着色器（`shadow_mask_source`、`blur_h_source`、`blur_v_source`、`composite_source`）。因此不能直接删除整个函数。

3. **重构策略**：将 `nebula_compose_shader` 拆分为两个函数：
   - `nebula_compose_shadow_shaders(opts)` — 仅生成阴影子着色器（shadow_mask / blur_h / blur_v / composite），返回 `{ shadow_mask_source, blur_h_source, blur_v_source, composite_source }`。
   - 删除原 `nebula_compose_shader` 中的主着色器生成逻辑（vertex + fragment 占位符）。

4. 更新 `nebula_core.nelua` 中的调用方：

```lua
-- 旧逻辑
local shader_result = nebula_compose_shader({...})
-- 使用 shader_result.source（占位符）和 shader_result.shadow_mask_source 等

-- 新逻辑（仅在 has_shadow 路径中）
local shadow_shaders = nebula_compose_shadow_shaders({...})
-- 主着色器使用 nebula_compose_shader_instanced 生成
local instanced_shader = nebula_compose_shader_instanced({...})
```

**验收标准**：

- `nebula_compose_shader` 函数不再存在于 `shader_compose.lua` 中。
- 新增 `nebula_compose_shadow_shaders` 函数，仅返回阴影相关着色器。
- `shadow_demo` 仍能正常编译和渲染阴影效果。
- 代码库中不再存在红色占位符 `vec4<f32>(1.0, 0.0, 0.0, 1.0)` 作为主 fragment 输出。

---

### Task 3.7.3：删除 `gen_pipeline_simple`（Day 2）

**目标**：从 `pipeline_factory.lua` 中删除 `gen_pipeline_simple` 函数及其在分发入口中的 `else` 分支。

**具体变更**：

1. 删除 `gen_pipeline_simple` 函数定义（第 47-97 行，约 50 行）。

2. 修改 `nebula_gen_pipeline_source` 分发入口（第 931-957 行），将 `else` 分支改为 `error()`：

```lua
function nebula_gen_pipeline_source(spec)
  if spec.has_shadow then
    return gen_pipeline_shadow(...)
  elseif spec.standard_instanced then
    return gen_pipeline_standard_instanced(...)
  elseif spec.textured and spec.vertex_layout == "pos_uv" then
    return gen_pipeline_textured_vertex(...)
  else
    error("nebula_gen_pipeline_source: unrecognized spec — all standard Visuals must use standard_instanced path")
  end
end
```

3. 同时删除旧的 `spec.instanced` 分支（见 Task 3.7.4）。

**验收标准**：

- `gen_pipeline_simple` 函数不再存在于代码库中。
- 分发入口不再有 `else` 兜底分支，取而代之的是显式 `error()`。
- 所有现有 demo 仍能正常编译（因为 Task 3.7.1 已将它们切换到 `standard_instanced`）。

---

### Task 3.7.4：删除 `gen_pipeline_instanced` 和 `nebula_compose_instanced_shader`（Day 2-3）

**目标**：删除 Phase 3.3 引入的旧 instanced 路径，包括着色器组合器和管线生成器。

**具体变更**：

1. 从 `shader_compose.lua` 中删除 `nebula_compose_instanced_shader` 函数（约 120 行）。

2. 从 `pipeline_factory.lua` 中删除 `gen_pipeline_instanced` 函数（第 725-925 行，约 200 行）。

3. 从 `nebula_gen_pipeline_source` 分发入口中删除 `spec.instanced` 分支。

4. **迁移 `dynamic_list_demo.nelua`**：这是唯一使用旧 instanced 路径的 demo。需要将其迁移到 `standard_instanced` 路径：
   - 将 `ListItemInstanceData` 改为通过 `nebula_annotate` + `nebula_derive` 自动派生的 `ListItemUniforms`。
   - 将手动调用 `nebula_compose_instanced_shader` + `nebula_gen_pipeline_source({instanced=true})` 替换为 `nebula_derive("ListItemVisual")`。
   - 将 `ListItemInstancedPipeline` 替换为自动派生的 `ListItemPipeline`（standard_instanced 类型）。
   - 更新 `pipe:init` 调用签名：从 `init(&renderer, max_count)` 到 `init(&renderer, max_count)`（签名兼容）。
   - 更新 `pipe:draw(pass, count)` 到 `pipe:draw_instanced(pass, count)`。

**验收标准**：

- `nebula_compose_instanced_shader` 函数不再存在于 `shader_compose.lua` 中。
- `gen_pipeline_instanced` 函数不再存在于 `pipeline_factory.lua` 中。
- `dynamic_list_demo` 已迁移到 `standard_instanced` 路径，仍能正常编译和运行。
- 代码库中不再存在 `InstancedPipeline` 命名模式。

---

### Task 3.7.5：重构阴影路径以使用 `standard_instanced` 着色器（Day 3-4）

**目标**：将阴影多 Pass 管线的主着色器从旧的占位符切换到 `nebula_compose_shader_instanced` 生成的着色器，使阴影 Visual 也能享受 SDF 圆角矩形和边框渲染。

**具体变更**：

1. 修改 `nebula_core.nelua` 中的阴影路径逻辑：

```lua
-- 旧逻辑：阴影与 instanced 互斥
has_shadow = (not use_instanced) and feats.has_shadow

-- 新逻辑：阴影路径也使用 instanced 着色器作为主着色器
if feats.has_shadow then
  local shadow_shaders = nebula_compose_shadow_shaders({...})
  local main_shader = nebula_compose_shader_instanced({...})
  pipeline_spec = {
    has_shadow = true,
    wgsl_source = main_shader.source,  -- 使用 instanced 着色器而非占位符
    shadow_mask_source = shadow_shaders.shadow_mask_source,
    blur_h_source = shadow_shaders.blur_h_source,
    blur_v_source = shadow_shaders.blur_v_source,
    composite_source = shadow_shaders.composite_source,
    ...
  }
end
```

2. 修改 `gen_pipeline_shadow` 中的主管线生成逻辑，使其兼容 `standard_instanced` 的着色器格式（Storage Buffer 绑定布局）。

3. 注意：此任务的复杂度较高，因为 `gen_pipeline_shadow` 的主管线目前使用 Uniform Buffer 而非 Storage Buffer。如果改动过大，可以暂时保留阴影路径使用独立的单实例 Uniform Buffer 方案，但主着色器必须替换为非占位符版本。

**替代方案**（如果完整重构风险过高）：

- 将 `nebula_compose_shader` 中的红色占位符 fragment 替换为 `nebula_compose_shader_instanced` 中的 SDF fragment 逻辑的**单实例版本**（即不使用 Storage Buffer，而是直接从 Uniform Buffer 读取字段）。
- 这样阴影路径的主管线仍然使用 Uniform Buffer，但着色器不再是占位符。

**验收标准**：

- `shadow_demo` 的主组件渲染正确的 SDF 圆角矩形（而非红色占位符）。
- 阴影效果（4-Pass 模糊）仍然正常工作。
- 编译期不再生成包含红色占位符的 WGSL 代码。

---

### Task 3.7.6：更新测试套件（Day 4）

**目标**：更新所有受影响的回归测试，删除对已废弃路径的断言，新增对收敛后路径的验证。

**具体变更**：

1. **删除或重写 `smoke_phase3_3_3.lua`**：该测试验证 `nebula_compose_instanced_shader` 的存在性和输出格式。由于该函数已被删除，测试需要：
   - 删除对 `nebula_compose_instanced_shader` 的所有断言。
   - 保留对 `nebula_compose_shader_instanced` 的验证（如果尚未被其他测试覆盖）。
   - 保留对 `nebula_compose_text_shader` 未被破坏的验证。

2. **更新 `smoke_phase3_3_4.lua`**：该测试验证 `gen_pipeline_instanced` 的输出。由于该函数已被删除：
   - 删除对 `ListItemInstancedPipeline` 的断言。
   - 新增断言：验证 `gen_pipeline_simple` 不再存在（调用应触发 error）。

3. **更新 `smoke_phase3_5_1.lua`**：该测试的"向后兼容"部分验证旧 simple 路径和旧 instanced 路径仍然存在。由于这些路径已被删除：
   - 删除"向后兼容"断言（`CardPipeline` 的 uniform-buffer-only 断言、`ListItemInstancedPipeline` 的存在性断言）。
   - 新增断言：验证 `standard_instanced=true` 是唯一的标准路径。

4. **新增 `smoke_phase3_7.lua`**：Phase 3.7 的专属回归测试，验证：
   - `nebula_compose_shader` 不再存在（或已被重命名为 `nebula_compose_shadow_shaders`）。
   - `nebula_compose_instanced_shader` 不再存在。
   - `gen_pipeline_simple` 不再存在。
   - `gen_pipeline_instanced` 不再存在。
   - `nebula_gen_pipeline_source` 在未指定 `standard_instanced` / `has_shadow` / `textured` 时触发 `error()`。
   - `nebula_compose_shader_instanced` 仍然正常工作。
   - `nebula_compose_text_shader` 仍然正常工作。
   - `gen_pipeline_standard_instanced` 生成的管线包含 `upload` / `draw_instanced` / `draw_single` 方法。
   - `gen_pipeline_textured_vertex` 生成的管线包含 `draw_buffer` 方法。
   - 模块版本号更新为 `nebula_pipeline_factory_v0.7_phase3.7`。

**验收标准**：

- `bash tools/run_all_tests.sh` 全部通过。
- 测试套件数量从 19 项更新为 N 项（删除 0-2 项旧测试，新增 1 项）。
- 断言总数保持在 250+ 项。

---

### Task 3.7.7：更新 Examples 和文档（Day 4-5）

**目标**：确保所有 demo 在新架构下正常工作，并更新相关文档。

**具体变更**：

1. **`button_demo.nelua`**：移除 `instanced=true` 注解（如果有的话），验证自动走 `standard_instanced` 路径。由于 `gen_pipeline_simple` 已删除，需要更新 demo 中的 Pipeline 初始化调用：
   - `pipe:init(&renderer)` → `pipe:init(&renderer, 1)`（单实例）。
   - `pipe:update_uniforms(...)` + `pipe:draw(pass)` → `pipe:upload(...)` + `pipe:draw_instanced(pass, 1)`。
   - 或使用 `pipe:draw_single(&renderer, pass, &uniforms)` 便捷方法。

2. **`simple_rect_demo.nelua`**：同上。

3. **`layout_demo.nelua`**：同上。

4. **`login_demo.nelua`**：同上。

5. **`shadow_demo.nelua`**：验证阴影路径在 Task 3.7.5 重构后仍然正常。

6. **`form_demo.nelua`**：验证 `FormApp:draw` 的 `upload` + `draw_instanced` 调用现在能正确匹配 `standard_instanced` 管线。

7. **`dynamic_list_demo.nelua`**：已在 Task 3.7.4 中迁移。

8. **更新 `README.md`**：在 Phase 历史中新增 Phase 3.7 条目。

9. **更新 `build.sh`**：更新注释中的 Phase 信息。

10. **更新模块版本号**：
    - `shader_compose.lua`：更新返回值为 `"nebula_shader_compose_v0.5_phase3.7"`。
    - `pipeline_factory.lua`：更新返回值为 `"nebula_pipeline_factory_v0.7_phase3.7"`。

**验收标准**：

- 所有 7 个 demo 均能通过 `./build.sh <demo_name>` 成功编译。
- `README.md` 包含 Phase 3.7 的更新记录。
- 模块版本号已更新。

---

### Task 3.7.8：代码行数收敛验证（Day 5）

**目标**：验证代码清理的量化成果。

**预期收敛**：

| 文件 | 清理前行数 | 预期清理后行数 | 删减量 |
| :--- | :--- | :--- | :--- |
| `shader_compose.lua` | 378 | ~260 | ~120 行（删除 `nebula_compose_shader` 主着色器 + `nebula_compose_instanced_shader`） |
| `pipeline_factory.lua` | 1011 | ~500 | ~510 行（删除 `gen_pipeline_simple` + `gen_pipeline_instanced`） |
| **合计** | 1389 | ~760 | **~630 行** |

**验收标准**：

- `pipeline_factory.lua` 行数 ≤ 550 行。
- `shader_compose.lua` 行数 ≤ 280 行。
- `wc -l src/derive/shader_compose.lua src/derive/pipeline_factory.lua` 合计 ≤ 830 行。

---

## 3. 任务依赖关系

```
Task 3.7.1 ──→ Task 3.7.2 ──→ Task 3.7.3 ──→ Task 3.7.6
                                    │
Task 3.7.1 ──→ Task 3.7.4 ──────→ Task 3.7.6
                                    │
Task 3.7.2 ──→ Task 3.7.5 ──────→ Task 3.7.6 ──→ Task 3.7.7 ──→ Task 3.7.8
```

- **Task 3.7.1** 是所有后续任务的前置：必须先将 `standard_instanced` 设为默认路径，才能安全删除旧路径。
- **Task 3.7.2** 和 **Task 3.7.4** 可以并行进行（分别处理着色器和管线的不同部分）。
- **Task 3.7.5** 依赖 Task 3.7.2（需要 `nebula_compose_shadow_shaders` 已就位）。
- **Task 3.7.6** 必须在所有代码变更完成后进行。
- **Task 3.7.7** 和 **Task 3.7.8** 是最终验证阶段。

---

## 4. 风险与缓解

### 风险 1：阴影路径重构复杂度

`gen_pipeline_shadow` 的主管线使用 Uniform Buffer 绑定布局，而 `standard_instanced` 使用 Storage Buffer。直接将阴影主管线切换到 Storage Buffer 可能需要修改 `gen_pipeline_shadow` 中约 280 行的 BindGroupLayout / BindGroup / Pipeline 创建代码。

**缓解**：Task 3.7.5 提供了替代方案——生成一个"单实例版本"的 SDF 着色器，保持 Uniform Buffer 绑定布局不变。这样只需替换 WGSL 源码，不需要修改管线创建逻辑。阴影路径的完整 Storage Buffer 迁移可以推迟到 Phase 3.8。

### 风险 2：`dynamic_list_demo` 迁移

`dynamic_list_demo` 使用了自定义的 `ListItemInstanceData` record（64 字节，手动对齐），与 `nebula_derive` 自动生成的 `<T>Uniforms` 布局可能不一致。

**缓解**：将 `ListItemInstanceData` 的字段定义为标准的 Visual record（`ListItemVisual`），通过 `nebula_annotate` + `nebula_derive` 自动生成 `ListItemUniforms`。需要确保自动生成的 std140 布局与手动定义的 64 字节布局兼容。如果不兼容，可以在 `nebula_annotate` 中新增 `force_uniform_size` 选项来强制对齐。

### 风险 3：现有 demo 的 API 迁移

`button_demo` 等 demo 中手写的渲染循环使用了 `gen_pipeline_simple` 生成的 API（`pipe:init(&renderer)` 无 max_instances 参数、`pipe:update_uniforms(...)` + `pipe:draw(pass)`）。切换到 `standard_instanced` 后，这些 API 将不再存在。

**缓解**：`gen_pipeline_standard_instanced` 已经提供了 `draw_single` 便捷方法，可以一行替代 `update_uniforms` + `draw`。迁移工作量可控。

---

## 5. 不变量（Phase 3.7 完成后必须成立）

1. `pipeline_factory.lua` 的分发入口 `nebula_gen_pipeline_source` 只有三条路径：`has_shadow` → `gen_pipeline_shadow`、`standard_instanced` → `gen_pipeline_standard_instanced`、`textured` → `gen_pipeline_textured_vertex`。无 `else` 兜底。
2. `shader_compose.lua` 只有三个公开函数：`nebula_compose_shader_instanced`、`nebula_compose_text_shader`、`nebula_compose_shadow_shaders`。
3. 代码库中不存在红色占位符 `vec4<f32>(1.0, 0.0, 0.0, 1.0)` 作为主 fragment 输出。
4. 代码库中不存在 `InstancedPipeline` 命名模式（旧 Phase 3.3 路径）。
5. 所有 7 个 demo 均能成功编译。
6. `bash tools/run_all_tests.sh` 全部通过，断言总数 ≥ 250。
7. `app_factory.lua` 生成的 `upload` + `draw_instanced` 调用与所有 Visual 的管线类型一致。

---

## 6. 与后续 Phase 的接口

Phase 3.7 完成后，为后续 Phase 扫清了以下障碍：

- **Phase 3.8（渲染循环与 FrameArena）**：所有 demo 已统一使用 `standard_instanced` 管线，`nebula_frame_render` 可以安全地假设所有管线都支持 `upload` + `draw_instanced` API。
- **Phase 3.9（文本一等公民）**：`app_factory.lua` 不再需要处理 `gen_pipeline_simple` 生成的旧 API，可以专注于集成 `text_vertex` 路径。
- **Phase 4.0（公理校验器）**：`axiom_lint.lua` 可以简单地检查 `nebula_compose_shader` 是否不存在（而非检查其输出是否为占位符），降低校验器的复杂度。

---

## 参考文献

- `docs/ARCHITECTURE_GRAND_PLAN.md` — 架构总纲领，原语 1 定义。
- `src/derive/shader_compose.lua` — 当前着色器组合器（378 行）。
- `src/derive/pipeline_factory.lua` — 当前管线生成器（1011 行）。
- `src/nebula_core.nelua` — 编译期推导引擎（1190 行）。
- `src/derive/app_factory.lua` — App 编排工厂（346 行）。
- `tests/smoke_phase3_3_3.lua` — Phase 3.3 着色器测试。
- `tests/smoke_phase3_3_4.lua` — Phase 3.3 管线测试。
- `tests/smoke_phase3_5_1.lua` — Phase 3.5.1 向后兼容测试。
