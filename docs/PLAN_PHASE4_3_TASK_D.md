# Phase 4.3 补丁：process_body 公理校验（任务 D）

**补丁日期**：2026-04-30  
**补丁对象**：`PLAN_PHASE4_3.md` §2.3 第 3 条"沙箱隔离"  
**状态**：待实施

---

## 1. 问题溯源

PLAN_PHASE4_3 §2.3 第 3 条要求：

> 沙箱隔离：确保 `inline_process` 中的代码只能访问 `self` 和 `input`，不能调用非法的全局函数或分配 L2 内存（维护公理 B）。

2026-04-30 深度审计发现该条完全未实现。`process_body` 函数可注入任意 Nelua 代码字符串，无任何校验。

审计同时发现 §2.3 第 2 条"静态契约断言"的实现（`nebula_validate_static_asserts()`）虽已完成，但未接入 `nebula_derive_app` 编译流程，仅在测试中调用。

---

## 2. 设计推导

### 2.1 从公理出发，而非从威胁模型出发

"沙箱隔离"这个表述隐含了威胁模型思维——枚举危险模式，逐一封堵。
但这与 Nebula 的设计哲学不一致。Nebula 的安全约束不来自外部威胁，
而是从三条正交公理中**推导**出来的。

### 2.2 公理 A 推导：引用域闭合

公理 A（阶段封闭性）的判定准则：

> 给定一个操作 O，其合法阶段由输入来源决定。
> S2 仅当 O 的输入依赖用户交互或外部事件时，O 属于 S2。

`process_body` 注入的代码运行在 `process_input` 方法体中（S2 阶段）。
S2 阶段的合法输入来源已被严格限定：
- `self: <T>Context` — L1 持久层上下文
- `input: *NebulaInputState` — 帧级输入状态
- `hovered: boolean` — AABB 碰撞检测结果（函数局部参数）

因此，`process_body` 注入的代码中，**每个标识符引用必须属于以下许可域之一**：

| 许可域 | 来源 | 例子 |
| :--- | :--- | :--- |
| Context 已声明字段 | 原语的 `context_fields` 及其依赖链 | `self.value`, `self.click.just_clicked` |
| Visual 字段 | Visual Record 的已知字段 | `self.visual.size.x`, `self.visual.pos.y` |
| NebulaInputState 字段 | `input` 参数类型 | `input.mouse_x`, `input.scroll_dy` |
| 函数参数 | process_input 签名 | `hovered`, `input` |
| 局部变量声明 | `local` 语句 | `local dx = ...` |
| Nelua 关键字与内置运算 | 语言规范 | `if`, `then`, `end`, `not`, `and` |
| 框架注册的 helper | `NEBULA_HELPERS` 集合 | `nebula_clamp()`, `nebula_lerp()` |

引用不在许可域中 → 违反公理 A → S1 阶段报错。

**这不是黑名单**。"禁止 require"不是因为 require 在黑名单上，
而是因为 require 不在许可域中。正向闭合定义，域外一切都不可达。

### 2.3 公理 B 推导：L1 引用完整性

公理 B（生命周期三层）要求：

> 每个运行时数据必须显式归属其一层。层间依赖严格单向。

`process_body` 中的 `self.xxx` 引用读取的是 L1 持久层数据。
L1 数据集合在 S1 阶段由 `context_fields` 声明确定——
这是公理 B "显式归属"的直接推论。

因此：**`self.xxx` 中的 `xxx` 必须存在于该原语的 resolved context_fields 中。**
引用未声明的 L1 字段 → 违反公理 B → S1 阶段报错。

注：Nelua 的类型系统已对此提供运行时保障（对不存在的 record 字段赋值会导致编译错误），
但 task D 在 S1 阶段提前检测，提供更友好的错误信息（标注原语名和公理编号）。

### 2.4 公理 A 推导：确定性约束

公理 A 隐含确定性要求：

> 前一阶段的输出是后一阶段的**不可变**输入。

`process_body` 注入的代码应是纯确定性的——
相同输入 → 相同行为。因此禁止依赖外部状态的调用：
- `math.random`（非确定性）
- `os.time`（外部状态）
- `io.*`（S0 阶段操作，在 S2 阶段调用违反公理 A）

### 2.5 为什么 Nelua 类型系统不够

Nelua 是静态语言，类型系统确实能在编译期拦截大部分非法引用。
但有三个维度是类型系统无法覆盖的：

1. **语义定位**：类型系统报错位置在 Nelua 编译器层面，
   而 task D 在 Nebula 编译期报错，可标注具体的原语名和违反的公理。
2. **跨原语引用**：类型系统无法判断 `self.other_prim_field` 是否属于当前原语的合法域。
   task D 可以基于 resolved dependency chain 精确判定。
3. **S0/S1 阶段操作混入**：如果用户在 `##[[ ]]` 中 cimport 了 `printf`，
   类型系统不会阻止 process_body 调用 `printf`（因为 `printf` 已声明）。
   但 task D 会标记 `printf` 不在 SELF_DOMAIN ∪ INPUT_DOMAIN ∪ HELPERS 中。

---

## 3. 实施方案

### 3.1 新增 axiom_validator 任务 D

在 `src/derive/axiom_validator.lua` 中新增任务 D：

```
★ 任务 D：process_body 引用域校验（公理 A + B 推导）

校验 process_body 注入的代码中，所有标识符引用
是否属于当前原语的合法引用域。

公开 API：
  nebula_validate_process_body(prims)  — 校验所有已注册原语的 process_body

校验步骤：
  D-1 引用域闭合检查（公理 A）
  D-2 L1 引用完整性检查（公理 B）
  D-3 确定性约束检查（公理 A）
```

### 3.2 D-1 引用域闭合检查

```lua
function nebula_validate_process_body(prims)
  local resolved = nebula_resolve_primitives(prims)
  
  -- 构建许可域
  local self_domain = {}    -- self.xxx 中合法的 xxx
  for _, prim_name in ipairs(resolved) do
    local meta = NEBULA_PRIMITIVES[prim_name]
    if meta and meta.context_fields then
      for _, field in ipairs(meta.context_fields) do
        self_domain[field.name] = true
      end
    end
  end
  -- 追加 Visual 已知字段（通用前缀匹配）
  -- self.visual.pos.x, self.visual.size.y 等由 Visual Record 决定，
  -- 此处标记 self.visual 为许可前缀，具体字段由 Nelua 类型系统兜底
  self_domain["visual"] = true

  local input_fields = {
    "mouse_x", "mouse_y", "mouse_left_down", "mouse_left_pressed",
    "scroll_dy", "key_pressed", "char_input", "focused_id",
    "mod_shift", "mod_ctrl", "viewport_w", "viewport_h",
    "viewport_resized", "dt",
  }
  local input_domain = {}
  for _, f in ipairs(input_fields) do input_domain[f] = true end

  local keywords = {
    ["if"]=true, ["then"]=true, ["else"]=true, ["elseif"]=true, ["end"]=true,
    ["local"]=true, ["not"]=true, ["and"]=true, ["or"]=true, ["true"]=true,
    ["false"]=true, ["nil"]=true, ["return"]=true, ["do"]=true,
    ["for"]=true, ["while"]=true, ["repeat"]=true, ["until"]=true,
    ["function"]=true, ["break"]=true,
    -- Nelua 类型标注关键字
    ["global"]=true, ["record"]=true, ["enum"]=true,
  }

  -- 遍历 process_body 注入的 lines，提取标识符并检查
  for _, prim_name in ipairs(resolved) do
    local meta = NEBULA_PRIMITIVES[prim_name]
    if meta and meta.process_body then
      local lines = {}
      meta.process_body({name=prim_name}, lines)  -- 收集注入的 lines
      local violations = _check_lines(lines, self_domain, input_domain, keywords)
      for _, v in ipairs(violations) do
        error(("[axiom D] 原语 '%s' 的 process_body 注入了非法引用 '%s' (line %d): "
          .. "违反公理 %s — %s"):format(
          prim_name, v.identifier, v.line, v.axiom, v.reason))
      end
    end
  end
end
```

### 3.3 D-2 L1 引用完整性检查

在 D-1 的基础上，对 `self.xxx.yyy` 形式的引用，检查 `xxx` 是否在 `self_domain` 中。
如果 `xxx` 对应一个嵌套 record（如 `click`、`hover`），进一步检查 `yyy` 是否是该 record 的已知字段。

对于 `self.visual.*` 前缀，标记为合法但交由 Nelua 类型系统兜底
（Visual Record 的字段在编译期由 Visual 类型决定，不在原语的 context_fields 中）。

### 3.4 D-3 确定性约束检查

在 D-1 的遍历中，额外检查：

```
禁止前缀：
  io.
  os.
  math.random
  math.randomseed
```

注：这些是**必要但不充分**的检查。完整确定性保证需依赖 Nelua 的语义分析，
task D 只做 S1 阶段能廉价完成的前缀检查。

### 3.5 接入编译流程

在 `src/derive/app_factory.lua` 的 `nebula_derive_app` 函数中，
将 `nebula_validate_process_body` 与已有的 `nebula_validate_app` 并列调用：

```lua
-- 现有代码（line 927）
if nebula_validate_app then
  nebula_validate_app(app_name, reg)
end

-- 新增：task D 校验
if nebula_validate_process_body then
  local all_prims = _collect_app_primitives(reg)
  nebula_validate_process_body(all_prims)
end
```

同时将已有的 `nebula_validate_static_asserts` 接入同一位置。

---

## 4. 合法/非法代码示例

### 4.1 合法代码（全部通过校验）

```lua
process_body = function(spec, lines)
  table.insert(lines, "  if self.click.just_clicked then")       -- self.click ∈ domain
  table.insert(lines, "    self.is_dragging = true")              -- self.is_dragging ∈ domain
  table.insert(lines, "    self.prev_mouse_x = input.mouse_x")   -- input.mouse_x ∈ domain
  table.insert(lines, "  elseif not input.mouse_left_down then")  -- input.mouse_left_down ∈ domain
  table.insert(lines, "    self.is_dragging = false")
  table.insert(lines, "  end")
  table.insert(lines, "  if self.is_dragging then")
  table.insert(lines, "    local dx = input.mouse_x - self.prev_mouse_x")  -- local 声明
  table.insert(lines, "    self.value = self.value + dx / self.visual.size.x") -- self.visual 合法
  table.insert(lines, "  end")
end
```

### 4.2 非法代码（触发 task D 报错）

```lua
process_body = function(spec, lines)
  -- 非法：require 不在许可域中（违反公理 A）
  table.insert(lines, '  local os = require("os")')
  -- 报错：[axiom D] 原语 'evil_prim' 的 process_body 注入了非法引用 'require'
  --        (line 1): 违反公理 A — S2 阶段不得执行 S1 阶段的模块加载操作
end
```

```lua
process_body = function(spec, lines)
  -- 非法：other_component_id 不在当前原语的 self_domain 中（违反公理 B）
  table.insert(lines, "  self.other_component_id = 99")
  -- 报错：[axiom D] 原语 'cross_ref' 的 process_body 注入了非法引用 'self.other_component_id'
  --        (line 1): 违反公理 B — 'other_component_id' 未在原语 'cross_ref' 的 context_fields 中声明
end
```

```lua
process_body = function(spec, lines)
  -- 非法：math.random 依赖外部状态（违反公理 A 确定性约束）
  table.insert(lines, "  self.value = math.random()")
  -- 报错：[axiom D] 原语 'random_prim' 的 process_body 注入了非法引用 'math.random'
  --        (line 1): 违反公理 A — S2 运行时不得引入非确定性（相同输入应产生相同行为）
end
```

---

## 5. 与现有代码的关系

### 5.1 nebula_validate_static_asserts（已有，未接入）

`nebula_validate_static_asserts()` 在 `interaction_factory.lua:390` 已实现，
校验原语间的数据契约（"clipboard_aware 需要 editable 的 gap_buf 字段"）。

本补丁将其接入 `nebula_derive_app` 编译流程，与 task D 并列调用。
它与 task D 是同一验证阶段的两个互补子步骤：
- `static_asserts`：校验**跨原语**的数据契约
- task D：校验**单原语内部**的引用域

### 5.2 NebuaInputState 字段列表的维护

task D 需要知道 `NebulaInputState` 的合法字段列表。
当前该列表硬编码在 `_check_lines` 中。

长期方案：从 `nebula_core.nelua` 的 `NebulaInputState` record 声明中自动提取。
短期方案：维护一个 `INPUT_FIELDS` 表，与 `nebula_core.nelua` 的 record 定义保持同步。
新增 input 字段时在两处同时更新（已有 precedent：`context_fields` 也是手动维护的）。

### 5.3 helper 函数注册

当前阶段不引入 `NEBULA_HELPERS` 白名单机制。
所有已知的 process_body 实现中不存在框架外部函数调用需求。

当 Phase 4.5（语法糖）引入公共工具函数时，再扩展 task D 的许可域。
届时新增 `nebula_register_helper(name, signature)` API。

---

## 6. 验收标准

1. **task D 实现**：`axiom_validator.lua` 新增 `nebula_validate_process_body()` 函数，
   能对注入代码做引用域闭合检查（D-1）、L1 引用完整性检查（D-2）、确定性约束检查（D-3）。
2. **管线集成**：`app_factory.lua` 的 `nebula_derive_app` 流程中调用 task D 和 `static_asserts`。
3. **正向测试**：slider_demo 的 process_body 通过校验（无报错）。
4. **负向测试**：注入 `require`/`os.execute`/`math.random`/非法 self 引用时，
   S1 阶段抛出包含公理编号的语义错误。
5. **回归测试**：37/37 全绿，所有现有 demo 编译无变化。
6. **代码量**：task D 核心逻辑 ≤ 100 行，测试 ≤ 80 行。

---

## 7. 不在本补丁范围内

- **helper 函数白名单**（`NEBULA_HELPERS`）：推迟到 Phase 4.5
- **Lua 函数层面的安全**（S0/S1 阶段）：不在 Nebula 的安全模型内
  （用户 .nelua 中的 `##[[ ]]` 本身就拥有完全的编译期控制权，
  这和 C 宏/Rust proc-macro 本质相同）
- **代码终止性检查**（禁止无限循环）：当前所有 process_body 实现均为无循环线性代码段，
  待出现循环需求时再引入（参考 BPF 的 1M 指令上限模型）
- **栈深度约束**（local 变量数量上限）：Nelua 编译器已管理栈帧，
  不在 task D 的职责范围内
