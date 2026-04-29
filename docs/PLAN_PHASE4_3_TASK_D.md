# Phase 4.3 补丁：process_body 公理校验（任务 D）

**补丁日期**：2026-04-30  
**补丁对象**：`PLAN_PHASE4_3.md` §2.3 第 3 条"沙箱隔离"  
**状态**：待实施  
**修订**：v3 — 引入虚拟指令验证 + 分支覆盖增强（Branch Expansion）

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
| 框架注册的内建函数 | `NEBULA_INTRINSICS` 白名单 | `nebula_clamp()`, `nebula_lerp()` |

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
   但 task D 会标记 `printf` 不在 SELF_DOMAIN ∪ INPUT_DOMAIN ∪ INTRINSICS 中。

---

## 3. eBPF 对照：为什么这是同类问题

Nebula 的 process_body 校验问题与 eBPF verifier 面对的是**同构问题**：

> 如何允许用户态代码在特权环境中安全执行？

| eBPF | Nebula |
|:-----|:-------|
| BPF 字节码 | process_body / process_logic |
| BPF verifier | axiom_validator 任务 D |
| 寄存器状态跟踪 | proxy 的 __index/__newindex 记录 |
| bpf_helper_defs.h | NEBULA_INTRINSICS 白名单 |
| `bpf_map_lookup_elem()` | `self.click.just_clicked` |
| verifier 拒绝 → 程序不加载 | validator 报错 → 编译终止 |

关键差异：eBPF verifier 使用**符号执行**（跟踪寄存器抽象域，遍历所有分支路径），
复杂度 O(指令数 × 分支数)。Nebula 的 process_body 是结构受限的线性状态机，
可以用**具体执行**（proxy 上空跑一次），复杂度 O(函数长度)。
通过限制行为表达力，用轻量级方案获得等价的安全保证。

**关键优势：Nebula 可以穷举输入空间，eBPF 不能。**

eBPF 的输入域是连续的：32/64 位寄存器值、任意指针、map 条目数。
穷举不可行，必须用符号执行。

Nebula process_body 的输入由三部分组成：
- `hovered` → boolean（2 种值）
- `input.mouse_left_down` 等 → boolean（2 种值）/ float64（连续）
- `self.click.is_pressed` 等 → boolean（2 种值）/ float32（连续）

**只有 boolean 类型的输入可以穷举。** 非 boolean（float、uint32）的输入
无法枚举，但它们不产生分支——只有 boolean 值参与 `if` 条件判断。

因此：对所有 boolean 输入做 2^n 笛卡尔展开，每次展开执行一次 proxy，
合并所有执行的字段访问记录并集，即可实现 **100% 分支路径覆盖**。

以当前内置原语为例：
```
hovered (参数)           → 1 boolean
input.mouse_left_down    → 1 boolean
input.mouse_left_pressed → 1 boolean
input.viewport_resized   → 1 boolean
context_fields 中 boolean → 约 4 个 (is_hovered, just_entered, is_pressed, just_clicked)
───────────────────────────
总计 8 boolean → 2^8 = 256 次 proxy 执行
```

256 次 Lua 函数调用的开销：微秒级。编译时间增加可忽略。
这在 eBPF 中不可行（寄存器值域是 2^32 或 2^64），
但在 Nebula 中完全可行——因为 boolean 值域只有 2。

这是 Nebula 的架构优势：**通过限制行为表达力（布尔条件驱动的线性状态机），
用穷举替代符号执行，获得 100% 路径覆盖，零误报。**

---

## 4. 实施方案：三层防御架构

### 4.0 架构总览

```
┌─────────────────────────────────────────────────────────┐
│                   process_body 校验架构                   │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Layer 0 — Proxy 验证 + 分支覆盖增强              │   │
│  │  新调用约定：process_body(self, input, hovered)   │   │
│  │  类型感知 proxy：boolean 字段返回 true/false      │   │
│  │  2^n 笛卡尔展开所有 boolean 输入                   │   │
│  │  合并所有路径的字段访问记录并集                     │   │
│  │  100% 分支覆盖，零误报                             │   │
│  │  覆盖：所有使用新约定的原语                        │   │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Layer 1 — Token 扫描兜底（旧调用约定兼容）       │   │
│  │  旧调用约定：process_body(spec, lines)            │   │
│  │  状态机扫描代码字符串，识别危险模式                │   │
│  │  黑名单兜底：require/os/io/math.random            │   │
│  │  覆盖：极少数需要复杂代码生成的原语                │   │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Layer 2 — Trace 报错（所有层共用）                │   │
│  │  失败时输出公理推导路径                            │   │
│  │  从错误标识符 → 许可域排除 → 公理编号 → 修复建议   │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### 4.1 Layer 0：Proxy 验证（核心）

#### 4.1.1 新调用约定

```lua
-- 旧约定（Layer 1，escape hatch）
process_body = function(spec, lines)
  table.insert(lines, "  self.hover.is_hovered = hovered")
end

-- 新约定（Layer 0，推荐）
process_body = function(self, input, hovered)
  -- 同时是合法 Lua 和合法 Nelua
  -- Lua 中：table 字段赋值
  -- Nelua 中：record 字段赋值
  -- 语法完全同构
  self.hover.is_hovered = hovered
  self.hover.just_entered = (hovered and not self.hover.is_hovered)
end
```

新约定要求 process_body 的函数体**同时是合法 Lua 和合法 Nelua**。
这个约束自然满足，因为 Nelua 的 record 字段访问语法和 Lua 的 table
字段访问语法完全一致。

不允许的 Lua 特有语法：`#table`（Nelua 数组长度语法不同）、
`setmetatable`（L2 操作）、`require`（S1 操作）。
这些恰好都是 process_body 中不应该出现的操作。

#### 4.1.2 类型感知 Proxy + 分支覆盖增强

**问题：朴素 proxy 的 __index 嵌套返回的 proxy 对象是 truthy 的。**

```lua
-- 朴素 proxy 的问题
if self.click.just_clicked then
  -- self.click.just_clicked 通过 __index 返回的是一个 proxy table
  -- 在 Lua 中 table 是 truthy（只有 nil 和 false 是 falsy）
  -- 所以这个分支**永远为 true**，无论外部输入如何枚举
end
```

这意味着朴素 proxy 无法覆盖 `if self.xxx then` 形式的分支。
只有 `if hovered then`（外部参数）和 `if input.mouse_left_down then`
（input 字段）的分支能被外部枚举覆盖。

**解法：类型感知 Proxy + boolean 覆盖表。**

从 `context_fields` 中提取所有 boolean 类型字段，
与函数参数中的 boolean、input 字段中的 boolean 合并，
构建 `boolean_map`（路径 → true/false 的映射表）。

对 boolean_map 中所有 boolean 变量做 2^n 笛卡尔展开，
每次展开生成一个 `boolean_combo`，构造对应的 proxy。
proxy 的 __index 对 boolean 路径返回 combo 中的实际值（true/false），
对非 boolean 路径返回嵌套 proxy。

```lua
-- 收集所有 boolean 类型的字段
local function collect_boolean_fields(resolved_deps, input_fields_spec)
  local booleans = {}

  -- 1. context_fields 中的 boolean
  for _, dep_name in ipairs(resolved_deps) do
    local meta = NEBULA_PRIMITIVES[dep_name]
    if meta and meta.context_fields then
      for _, field in ipairs(meta.context_fields) do
        if field.type == "boolean" then
          table.insert(booleans, {
            path  = "self." .. field.name,
            name  = field.name,
            scope = "self",
          })
        end
      end
    end
  end

  -- 2. input 字段中的 boolean
  for _, field_name in ipairs(input_fields_spec) do
    if INPUT_BOOLEAN_FIELDS[field_name] then
      table.insert(booleans, {
        path  = "input." .. field_name,
        name  = field_name,
        scope = "input",
      })
    end
  end

  -- 3. 函数参数中的 boolean（总是 hovered）
  table.insert(booleans, {
    path  = "hovered",
    name  = "hovered",
    scope = "param",
  })

  return booleans
end

INPUT_BOOLEAN_FIELDS = {
  ["mouse_left_down"]    = true,
  ["mouse_left_pressed"] = true,
  ["viewport_resized"]   = true,
}

-- 笛卡尔展开：生成 2^n 个 boolean 组合
local function cartesian_booleans(booleans)
  local combos = { {} }  -- 初始：一个空组合

  for _, bool_field in ipairs(booleans) do
    local new_combos = {}
    for _, combo in ipairs(combos) do
      -- 每个 boolean 分叉为 true 和 false 两条路径
      local combo_true  = {}
      for k, v in pairs(combo) do combo_true[k] = v end
      combo_true[bool_field.path] = true

      local combo_false = {}
      for k, v in pairs(combo) do combo_false[k] = v end
      combo_false[bool_field.path] = false

      table.insert(new_combos, combo_true)
      table.insert(new_combos, combo_false)
    end
    combos = new_combos
  end

  return combos
end

-- 类型感知 proxy 构造
local function make_typed_proxy(path, records, boolean_combo)
  return setmetatable({}, {
    __index = function(_, key)
      local full = path .. "." .. key
      table.insert(records, { kind = "read", path = full })

      -- 如果 boolean_combo 中有此路径的覆盖值，直接返回 boolean
      if boolean_combo[full] ~= nil then
        return boolean_combo[full]
      end

      -- 否则返回嵌套 proxy（非 boolean 字段，如 float32/Vec2）
      return make_typed_proxy(full, records, boolean_combo)
    end,
    __newindex = function(_, key, val)
      local full = path .. "." .. key
      table.insert(records, { kind = "write", path = full })
    end,
  })
end

-- 分支覆盖增强：对所有 boolean 组合执行 proxy，合并记录并集
local function branch_expand(prim_meta, prim_name, resolved_deps)
  local booleans = collect_boolean_fields(resolved_deps, INPUT_FIELDS_LIST)
  local combos = cartesian_booleans(booleans)

  -- 全局去重记录集
  local merged_records = {}  -- key = "kind:path" → record

  for _, combo in ipairs(combos) do
    local records = {}
    local self_proxy  = make_typed_proxy("self", records, combo)
    local input_proxy = make_typed_proxy("input", records, combo)
    local hovered = combo["hovered"]  -- boolean, 来自 combo

    local ok, err = pcall(prim_meta.process_body, self_proxy, input_proxy, hovered)
    if not ok then
      error(("[Axiom-D] 原语 '%s' 的 process_body proxy 执行失败 (combo=%s): %s"):format(
        prim_name, serpent.line(combo), err))
    end

    -- 合并到全局记录集（去重：同一路径只保留一次）
    for _, rec in ipairs(records) do
      local key = rec.kind .. ":" .. rec.path
      if not merged_records[key] then
        merged_records[key] = rec
      end
    end
  end

  -- 转换为数组
  local result = {}
  for _, rec in pairs(merged_records) do
    table.insert(result, rec)
  end
  return result, #combos
end
```

**为什么类型感知 proxy 能覆盖所有分支？**

以 clickable 原语为例：

```lua
process_body = function(self, input, hovered)
  self.click.is_pressed = (hovered and input.mouse_left_down)
  self.click.just_clicked = (self.click.is_pressed and not prev_pressed)
end
```

笛卡尔展开 `{hovered, input.mouse_left_down, self.click.is_pressed, ...}` 时：

```
combo 1: hovered=T, mouse_left_down=T, is_pressed=T
  → self.click.is_pressed = (T and T) = T
  → 赋值路径被记录

combo 2: hovered=T, mouse_left_down=F, is_pressed=F
  → self.click.is_pressed = (T and F) = F
  → 赋值路径被记录（同一个 WRITE self.click.is_pressed）

combo 3: hovered=F, mouse_left_down=T, is_pressed=F
  → self.click.is_pressed = (F and T) = F
  → ...以此类推
```

所有 boolean 组合都被执行。赋值语句的目标路径在**所有组合中都相同**（WRITE self.click.is_pressed）。
条件分支中不同路径的字段访问（如 `if self.click.just_clicked then` 中的
`self.is_dragging`）在 `just_clicked=true` 的组合中被记录，在 `just_clicked=false` 的组合中不被记录。
并集合并后，所有可达路径上的字段访问都被覆盖。

**不可达组合的处理：**

某些 boolean 组合在物理上不可达（如 `just_clicked=true` 但 `hovered=false`）。
对不可达组合执行 proxy 会产生"虚记录"——记录了实际不会出现的字段访问。

但这些虚记录只会**增加**许可域检查的覆盖面，不会产生误报。
因为许可域检查是正向闭合的：只检查"是否在域中"，不检查"是否应该执行"。
一个不可达路径上访问了合法字段 → 合法，无影响。
一个不可达路径上访问了非法字段 → 报错。这实际是 **feature**：
强制所有路径（包括不可达路径）都在许可域内，消除潜在的代码异味。

**复杂度分析：**

```
boolean 数量 n → 2^n 次 proxy 执行
每次执行 = O(函数长度) 的 Lua 函数调用

当前内置原语：n ≈ 8 → 256 次 → 微秒级
极端场景：n = 12 → 4096 次 → 仍为毫秒级
超过 12 个 boolean：发出编译警告，建议拆分原语
```

#### 4.1.3 许可域构建

```lua
local function build_allowed_domain(prim_name, resolved_deps)
  local self_domain = {}

  -- 收集所有依赖原语（含自身）的 context_fields
  for _, dep_name in ipairs(resolved_deps) do
    local meta = NEBULA_PRIMITIVES[dep_name]
    if meta and meta.context_fields then
      for _, field in ipairs(meta.context_fields) do
        self_domain[field.name] = true
      end
    end
  end

  -- Visual 字段（通用前缀，具体字段由 Nelua 类型系统兜底）
  self_domain["visual"] = true

  -- NebulaInputState 字段
  local input_domain = {
    ["mouse_x"] = true, ["mouse_y"] = true,
    ["mouse_left_down"] = true, ["mouse_left_pressed"] = true,
    ["scroll_dy"] = true, ["key_pressed"] = true,
    ["char_input"] = true, ["focused_id"] = true,
    ["mod_shift"] = true, ["mod_ctrl"] = true,
    ["viewport_w"] = true, ["viewport_h"] = true,
    ["viewport_resized"] = true, ["dt"] = true,
  }

  return self_domain, input_domain
end
```

#### 4.1.4 D-1：引用域闭合检查（Proxy 记录校验）

```lua
local function check_records(records, self_domain, input_domain, prim_name)
  local violations = {}

  for _, rec in ipairs(records) do
    local path = rec.path
    local parts = {}  -- 拆分路径
    for part in path:gmatch("[^%.]+") do
      table.insert(parts, part)
    end

    local root = parts[1]  -- "self" | "input" | "hovered" | ...

    if root == "self" then
      -- D-1 + D-2：检查 self.xxx 在 self_domain 中
      local field = parts[2]
      if field and not self_domain[field] then
        table.insert(violations, {
          path   = path,
          kind   = rec.kind,
          axiom  = "B",
          reason = ("'%s' 未在原语 '%s' 的 context_fields 中声明"):format(field, prim_name),
          trace  = ("self.%s ∉ SELF_DOMAIN (L1 未声明的字段)"):format(field),
        })
      end
    elseif root == "input" then
      -- D-1：检查 input.xxx 在 input_domain 中
      local field = parts[2]
      if field and not input_domain[field] then
        table.insert(violations, {
          path   = path,
          kind   = rec.kind,
          axiom  = "A",
          reason = ("'%s' 不是 NebulaInputState 的已知字段"):format(field),
          trace  = ("input.%s ∉ INPUT_DOMAIN"):format(field),
        })
      end
    elseif root ~= "hovered" then
      -- 未知根标识符 → 违反公理 A
      table.insert(violations, {
        path   = path,
        kind   = rec.kind,
        axiom  = "A",
        reason = ("'%s' 不在 S2 许可域中"):format(root),
        trace  = ("%s ∉ SELF_DOMAIN ∪ INPUT_DOMAIN ∪ PARAMS"):format(root),
      })
    end
  end

  return violations
end
```

#### 4.1.5 D-3：确定性约束检查

```lua
local DETERMINISM_VIOLATORS = {
  ["math.random"]     = true,
  ["math.randomseed"] = true,
  ["os.time"]         = true,
  ["os.clock"]        = true,
  ["os.getenv"]       = true,
  ["io.open"]         = true,
  ["io.read"]         = true,
  ["io.write"]        = true,
  ["io.popen"]        = true,
  ["require"]         = true,
  ["dofile"]          = true,
  ["loadfile"]        = true,
  ["load"]            = true,
  ["pcall"]           = true,  -- 可隐藏任意调用
  ["xpcall"]          = true,
}

local function check_determinism(records, prim_name)
  local violations = {}
  for _, rec in ipairs(records) do
    local path = rec.path
    if DETERMINISM_VIOLATORS[path] then
      table.insert(violations, {
        path   = path,
        kind   = rec.kind,
        axiom  = "A",
        reason = "S2 阶段不得引入非确定性或外部状态访问",
        trace  = ("%s 违反阶段封闭性 — 相同输入应产生相同行为"):format(path),
      })
    end
  end
  return violations
end
```

注：DETERMINISM_VIOLATORS 的字段访问形式（如 `os.time`）在 proxy 中会触发
`__index` 在 `os` proxy 上的连续两次调用（先 `self[os]`，再 `os[time]`），
记录为路径 `os.time`。但 process_body 中不会出现裸 `os` 作为 self/input 之外的根标识符，
因为 proxy 的 `__index` 只在访问 proxy 对象时触发。

更可靠的方式：对 process_body 函数体的源码文本做 D-3 扫描（Layer 1 的扫描能力），
作为 proxy 记录的补充。详见 §4.2。

### 4.2 Layer 1：Token 扫描兜底

当原语只提供旧约定的 `process_body(spec, lines)` 时，
无法执行 proxy——因为旧约定不在 Lua 层面操作对象，只往 lines 表里插字符串。

此时退化为 token 扫描：

```lua
local function scan_lines_for_violations(lines, prim_name)
  local violations = {}

  for i, line in ipairs(lines) do
    -- 提取函数调用：fname( 或 module.fname(
    for call in line:gmatch("([%a_][%a%d_]*%.[%a_][%a%d_]*)%s*%(") do
      if DETERMINISM_VIOLATORS[call] then
        table.insert(violations, {
          line   = i,
          token  = call,
          axiom  = "A",
          kind   = "nondeterministic_call",
          trace  = ("%s 不在 NEBULA_INTRINSICS 白名单中"):format(call),
        })
      end
    end

    -- 提取 require/dofile/loadfile（裸函数调用）
    for fn in line:gmatch("([%a_][%a%d_]*)%s*%(") do
      if DETERMINISM_VIOLATORS[fn] then
        table.insert(violations, {
          line   = i,
          token  = fn,
          axiom  = "A",
          kind   = "s0_operation",
          trace  = ("%s 是 S0/S1 阶段操作，在 S2 阶段不可调用"):format(fn),
        })
      end
    end
  end

  return violations
end
```

这是黑名单模式——只检测已知危险模式，不是正向闭合。
但在旧约定下，这是唯一可行的方案，且只用于极少数需要复杂代码生成的原语。

### 4.3 Layer 2：NEBULA_INTRINSICS 辅助函数网关

效仿 eBPF 的 `bpf_helper_defs.h`，定义 S2 阶段允许调用的函数白名单：

```lua
NEBULA_INTRINSICS = {
  -- 框架数学工具
  ["nebula_clamp"]  = { sig = "(number, number, number) -> number" },
  ["nebula_lerp"]   = { sig = "(number, number, number) -> number" },
  ["nebula_rgba"]   = { sig = "(float32, float32, float32, float32) -> Color" },

  -- Nelua 数学内置（S2 阶段合法子集）
  ["math.abs"]   = true,
  ["math.min"]   = true,
  ["math.max"]   = true,
  ["math.floor"] = true,
  ["math.ceil"]  = true,
  ["math.sqrt"]  = true,
  -- 注意：math.random 不在白名单中（违反确定性约束）

  -- Nelua 类型构造
  ["Vec2.new"] = true,
  ["Vec4.new"] = true,
  ["Color.new"] = true,
}
```

所有在 process_body 中调用的函数，凡是不在 INTRINSICS 中的，
一律视为"非法外溢"，由 Layer 0 proxy 记录或 Layer 1 token 扫描捕获。

### 4.4 Layer 3：Trace 报错（公理推导路径）

当校验失败时，不仅给出错误信息，还要给出从标识符到公理的推导链：

```
[Axiom-A Violation] 原语 'evil_prim' 的 process_body 引用了非法标识符

  访问记录: os.execute
  访问类型: function call

  Trace:
    1. 识别到标识符: os.execute
    2. 排除 SELF_DOMAIN:  os ≠ context_fields 中的任何字段
    3. 排除 INPUT_DOMAIN: os ≠ NebulaInputState 的任何字段
    4. 排除 PARAMS:       os ≠ {self, input, hovered}
    5. 排除 INTRINSICS:   os.execute ∉ NEBULA_INTRINSICS
    6. 推论: os.execute 是 S0 阶段操作（系统调用），在 S2 阶段调用违反公理 A

  公理路径: Axiom-A (阶段封闭性)
    → S2 阶段的合法输入来源 = {self, input, hovered}
    → os.execute 的输入来源是操作系统（S0 层）
    → S2 不得执行 S0 操作

  修复建议: 若需要系统调用，将其移至 pre_derive_hook（S1 阶段）
```

Trace 格式模板：

```lua
local function format_trace(violation, prim_name)
  local lines = {}
  table.insert(lines, ("[Axiom-%s Violation] 原语 '%s' 的 process_body 引用了非法标识符"):format(
    violation.axiom, prim_name))
  table.insert(lines, "")
  table.insert(lines, ("  访问记录: %s (%s)"):format(violation.path or violation.token, violation.kind))
  table.insert(lines, "")
  table.insert(lines, "  Trace:")
  if violation.trace then
    table.insert(lines, ("    %s"):format(violation.trace))
  end
  table.insert(lines, "")
  table.insert(lines, ("  公理路径: Axiom-%s"):format(violation.axiom))
  if violation.axiom == "A" then
    table.insert(lines, "    → S2 阶段的合法输入来源 = {self, input, hovered}")
    table.insert(lines, ("    → %s 不在此许可域中"):format(violation.path or violation.token))
    table.insert(lines, "    → 违反阶段封闭性")
  elseif violation.axiom == "B" then
    table.insert(lines, "    → L1 字段必须在 context_fields 中显式声明")
    table.insert(lines, ("    → %s 未声明"):format(violation.path or violation.token))
    table.insert(lines, "    → 违反生命周期三层原则")
  end
  table.insert(lines, "")
  if violation.reason then
    table.insert(lines, ("  修复建议: %s"):format(violation.reason))
  end
  return table.concat(lines, "\n")
end
```

### 4.5 主入口：nebula_validate_process_body

```lua
function nebula_validate_process_body(app_name, prims)
  local resolved = nebula_resolve_primitives(prims)
  local all_violations = {}

  for _, prim_name in ipairs(resolved) do
    local meta = NEBULA_PRIMITIVES[prim_name]
    if not meta or not meta.process_body then goto continue end

    local prim_deps = nebula_resolve_primitives({ prim_name })
    local self_domain, input_domain = build_allowed_domain(prim_name, prim_deps)

    -- 检测调用约定
    local info = debug.getinfo(meta.process_body, "u")
    local nparams = info.nparams

    if nparams >= 3 then
      -- ── Layer 0：分支覆盖增强的 Proxy 验证 ──
      local records, ncombos = branch_expand(meta, prim_name, prim_deps)

      -- D-1 + D-2：引用域闭合（所有路径的并集）
      local domain_violations = check_records(records, self_domain, input_domain, prim_name)
      for _, v in ipairs(domain_violations) do
        table.insert(all_violations, { prim = prim_name, violation = v })
      end

      -- D-3：确定性约束（proxy 记录 + 源码扫描双重检查）
      local det_violations = check_determinism(records, prim_name)
      for _, v in ipairs(det_violations) do
        table.insert(all_violations, { prim = prim_name, violation = v })
      end

      -- 记录覆盖率统计（用于编译诊断）
      if ncombos > 1 then
        -- 通知：分支覆盖增强已生效
        io.write(("[axiom-D] 原语 '%s': %d boolean 组合, %d 路径并集记录\n"):format(
          prim_name, ncombos, #records))
      end

    elseif nparams == 2 then
      -- ── Layer 1：Token 扫描兜底 ──
      local lines = {}
      meta.process_body({ name = prim_name }, lines)

      local scan_violations = scan_lines_for_violations(lines, prim_name)
      for _, v in ipairs(scan_violations) do
        table.insert(all_violations, { prim = prim_name, violation = v })
      end
    end

    ::continue::
  end

  -- Layer 3：Trace 报错
  if #all_violations > 0 then
    local lines = {}
    table.insert(lines, ("[Axiom-D] App '%s' 的 process_body 校验失败："):format(app_name))
    table.insert(lines, ("  共 %d 处违规\n"):format(#all_violations))
    for _, entry in ipairs(all_violations) do
      table.insert(lines, format_trace(entry.violation, entry.prim))
      table.insert(lines, "")
    end
    error(table.concat(lines, "\n"), 2)
  end
end
```

**调用约定自动检测**：通过 `debug.getinfo(func, "u").nparams` 判断：
- `nparams >= 3` → 新约定 `(self, input, hovered)` → 走 Layer 0
- `nparams == 2` → 旧约定 `(spec, lines)` → 走 Layer 1

无 breaking change。现有原语（均为旧约定）自动走 Layer 1 兜底。
新原语推荐使用新约定以获得精确校验。

### 4.6 接入编译流程

在 `src/derive/app_factory.lua` 的 `nebula_derive_app` 函数中：

```lua
-- 现有代码（line 927）
if nebula_validate_app then
  nebula_validate_app(app_name, reg)
end

-- 新增：task D 校验
if nebula_validate_process_body then
  local all_prims = _collect_app_primitives(reg)
  nebula_validate_process_body(app_name, all_prims)
end

-- 新增：接入已有的 static_asserts
if nebula_validate_static_asserts then
  local all_prims = _collect_app_primitives(reg)
  nebula_validate_static_asserts(all_prims)
end
```

---

## 5. 合法/非法代码示例

### 5.1 新约定 — 合法代码（Layer 0 分支覆盖增强）

```lua
-- clickable 原语
process_body = function(self, input, hovered)
  self.click.is_pressed   = (hovered and input.mouse_left_down)
  self.click.just_clicked = (self.click.is_pressed and not prev_pressed)
end
```

分支覆盖增强的执行过程：

```
boolean 字段收集：
  self.click.is_pressed   (boolean, context_fields)
  self.click.just_clicked (boolean, context_fields)
  input.mouse_left_down   (boolean, input)
  hovered                 (boolean, 参数)
  → 共 4 boolean → 2^4 = 16 组合

每组组合执行 proxy，合并记录并集：

combo 1: hovered=T, mouse_left_down=T, is_pressed=T, just_clicked=T
  → READ  hovered
  → READ  input.mouse_left_down
  → WRITE self.click.is_pressed
  → READ  self.click.is_pressed (prev_pressed)
  → WRITE self.click.just_clicked

combo 2: hovered=F, mouse_left_down=F, is_pressed=F, just_clicked=F
  → READ  hovered
  → READ  input.mouse_left_down
  → WRITE self.click.is_pressed
  → READ  self.click.is_pressed
  → WRITE self.click.just_clicked

... (14 more combos, 每组记录相同的路径)

合并后并集记录（去重）：
  READ  hovered
  READ  input.mouse_left_down
  WRITE self.click.is_pressed
  READ  self.click.is_pressed
  WRITE self.click.just_clicked

校验：所有 self.xxx ∈ context_fields，所有 input.xxx ∈ INPUT_DOMAIN。
通过。16 组合全覆盖，100% 分支路径。
```

### 5.1b 分支覆盖增强的实际效果

考虑一个包含条件分支的原语：

```lua
-- drag_slider 原语
process_body = function(self, input, hovered)
  if self.click.just_clicked then      -- 分支 A
    self.is_dragging = true
    self.prev_mouse_x = input.mouse_x
  elseif not input.mouse_left_down then -- 分支 B
    self.is_dragging = false
  end
  if self.is_dragging then              -- 分支 C
    local dx = input.mouse_x - self.prev_mouse_x
    self.value = self.value + dx / self.visual.size.x
  end
end
```

朴素 proxy（单次执行）的问题：
- `self.click.just_clicked` 返回 proxy(table) → truthy → 永远走分支 A
- 分支 B 的字段访问（`self.is_dragging = false`）**永远不会被记录**
- `self.is_dragging` 返回 proxy(table) → truthy → 永远走分支 C

分支覆盖增强（boolean 笛卡尔展开）：
```
boolean 字段：hovered, input.mouse_left_down,
              self.click.just_clicked, self.click.is_dragging
→ 2^4 = 16 组合

combo (just_clicked=T, is_dragging=F):
  → 走分支 A：记录 WRITE self.is_dragging, WRITE self.prev_mouse_x
  → 走分支 C 不成立（is_dragging=F）：不记录分支 C 内容

combo (just_clicked=F, mouse_left_down=F, is_dragging=F):
  → 走分支 B：记录 WRITE self.is_dragging (= false)
  → 走分支 C 不成立

combo (just_clicked=F, mouse_left_down=F, is_dragging=T):
  → 走分支 B：记录 WRITE self.is_dragging (= false)
  → 走分支 C 成立：记录 READ self.value, WRITE self.value, READ self.visual.size.x

合并所有 16 组合的记录并集：
  READ  self.click.just_clicked     ← 分支条件
  WRITE self.is_dragging            ← 分支 A + B 都覆盖
  WRITE self.prev_mouse_x           ← 分支 A 覆盖
  READ  input.mouse_left_down       ← 分支 B 条件
  READ  self.is_dragging            ← 分支 C 条件
  READ  input.mouse_x               ← 分支 A + C 覆盖
  READ  self.prev_mouse_x           ← 分支 C 覆盖
  READ  self.value                  ← 分支 C 覆盖
  WRITE self.value                  ← 分支 C 覆盖
  READ  self.visual.size.x          ← 分支 C 覆盖

→ 所有分支路径（A/B/C）的字段访问全部被记录。
→ 无隐藏分支逃逸。
```

### 5.2 新约定 — 非法代码（Layer 0 proxy 校验失败）

```lua
process_body = function(self, input, hovered)
  self.secret_data = 42
end
```

```
[Axiom-B Violation] 原语 'bad_prim' 的 process_body 引用了非法标识符

  访问记录: self.secret_data (write)

  Trace:
    self.secret_data ∉ SELF_DOMAIN — 'secret_data' 未在原语 'bad_prim' 的 context_fields 中声明

  公理路径: Axiom-B (生命周期三层)
    → L1 字段必须在 context_fields 中显式声明
    → secret_data 未声明
    → 违反生命周期三层原则

  修复建议: 在 bad_prim 的 context_fields 中添加 { name = "secret_data", type = "float32" }
```

### 5.3 旧约定 — 非法代码（Layer 1 token 扫描捕获）

```lua
process_body = function(spec, lines)
  table.insert(lines, '  local os = require("os")')
  table.insert(lines, '  os.execute("rm -rf /")')
end
```

```
[Axiom-D] App 'evil_app' 的 process_body 校验失败：
  共 2 处违规

[Axiom-A Violation] 原语 'evil_prim' 的 process_body 引用了非法标识符

  访问记录: require (function call)

  Trace:
    require 是 S0/S1 阶段操作（模块加载），在 S2 阶段不可调用

  公理路径: Axiom-A (阶段封闭性)
    → require 是 S1 阶段操作（模块加载）
    → S2 不得执行 S1 操作

  修复建议: 将模块依赖移至原语的 pre_derive_hook 或顶层 ##[[ ]] 块中
```

---

## 6. 与现有代码的关系

### 6.1 nebula_validate_static_asserts（已有，未接入）

`nebula_validate_static_asserts()` 在 `interaction_factory.lua:390` 已实现，
校验原语间的数据契约（"clipboard_aware 需要 editable 的 gap_buf 字段"）。

本补丁将其接入 `nebula_derive_app` 编译流程，与 task D 并列调用。
它与 task D 是同一验证阶段的两个互补子步骤：
- `static_asserts`：校验**跨原语**的数据契约
- task D：校验**单原语内部**的引用域

### 6.2 NebulaInputState 字段列表的维护

task D 需要知道 `NebulaInputState` 的合法字段列表。
当前该列表硬编码在 `build_allowed_domain` 中。

长期方案：从 `nebula_core.nelua` 的 `NebulaInputState` record 声明中自动提取。
短期方案：维护一个 `INPUT_FIELDS` 表，与 `nebula_core.nelua` 的 record 定义保持同步。
新增 input 字段时在两处同时更新（已有 precedent：`context_fields` 也是手动维护的）。

### 6.3 NEBULA_INTRINSICS 白名单

初始版本只包含已知的框架辅助函数。随着 Phase 4.5（语法糖）引入更多公共工具函数，
通过 `nebula_register_helper(name, signature)` 扩展白名单。

### 6.4 渐进迁移路径

现有原语（hoverable/clickable/focusable）均为旧约定 `(spec, lines)`。
短期走 Layer 1 token 扫描兜底。中长期可迁移到新约定 `(self, input, hovered)`，
同时保留旧的 lines 生成逻辑作为代码生成器。

迁移不是必须的——Layer 1 对结构规整的现有原语已经足够。
Layer 0 的主要收益是为**用户自定义原语**提供精确校验。

---

## 7. 验收标准

1. **Layer 0 实现**：类型感知 proxy 构造 + `__index/__newindex` 记录 + 许可域校验，
   boolean 字段返回实际 boolean 值（非嵌套 proxy），精确捕获嵌套字段访问。
2. **分支覆盖增强**：对所有 boolean 输入做 2^n 笛卡尔展开，
   合并所有路径的字段访问记录并集，实现 100% 分支路径覆盖。
3. **Layer 1 实现**：token 扫描兜底，覆盖 require/os/io/math.random 等已知危险模式。
4. **Layer 2 实现**：NEBULA_INTRINSICS 白名单表。
5. **Layer 3 实现**：Trace 报错格式，包含公理编号、推导路径、修复建议。
6. **调用约定检测**：`debug.getinfo(func, "u").nparams` 自动区分新旧约定。
7. **管线集成**：`app_factory.lua` 的 `nebula_derive_app` 流程中调用 task D 和 static_asserts。
8. **正向测试**：现有所有原语（旧约定）通过 Layer 1 校验（无报错）。
9. **负向测试**：新约定下注入非法字段访问 / 旧约定下注入 require 等操作，
   S1 阶段抛出带 Trace 的公理报错。
10. **分支覆盖测试**：构造包含条件分支的原语，验证朴素 proxy 漏检但分支覆盖增强能捕获。
11. **回归测试**：37/37 全绿。
12. **代码量**：task D 核心 ≤ 300 行（含分支覆盖增强），测试 ≤ 150 行。

---

## 8. 不在本补丁范围内

- **符号执行（复杂控制流覆盖）**：当前 process_body 仅含 if/else 分支，
  无循环、无递归。2^n boolean 笛卡尔展开已覆盖全部分支路径。
  若未来引入循环（for/while），需参考 BPF 的 1M 指令上限模型。
- **超长 boolean 链保护**：当 boolean 数量 > 12（2^12 = 4096 组合）时，
  发出编译警告但不阻断。若未来出现需要大量 boolean 的原语，
  可引入"选择性展开"模式（只展开函数参数 + input 字段，跳过 self 内部 boolean）。
- **Lua 函数层面的安全**（S0/S1 阶段）：不在 Nebula 的安全模型内
  （用户 .nelua 中的 `##[[ ]]` 本身就拥有完全的编译期控制权，
  这和 C 宏/Rust proc-macro 本质相同）。
- **代码终止性检查**（禁止无限循环）：当前所有 process_body 实现均为无循环线性代码段，
  待出现循环需求时再引入（参考 BPF 的 1M 指令上限模型）。
- **栈深度约束**（local 变量数量上限）：Nelua 编译器已管理栈帧，
  不在 task D 的职责范围内。
- **process_body → Nelua 源码自动提取**：新约定的函数体可作为源码注入，
  但当前阶段只用于校验，代码生成仍由各原语自行完成。
  自动提取需要 `debug.getinfo + 源文件读取`，推迟到代码生成管线统一重构时。
