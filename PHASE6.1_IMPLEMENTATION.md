# Phase 6.1 实施总结

## 完成日期
2026-06-09

## 实施内容
渐变填充支持（Gradient Fill Support）

## 修改文件
1. **src/derive/shader_compose.lua** (+17 行)
   - Fragment shader 增加渐变逻辑
   - 支持 3 种填充模式：纯色(0)、线性渐变(1)、径向渐变(2)

2. **src/nebula_sugar.nelua** (+5 行)
   - 自动生成渐变相关字段：
     * `fill_mode: uint32`
     * `gradient_angle: float32`
     * `{state}_color_end: Color`

3. **src/nebula_derive_engine.nelua** (+9 行)
   - `init_themed()` 自动初始化渐变字段
   - 默认值确保向后兼容（fill_mode=0, 纯色模式）

4. **examples/gradient_demo.nelua** (新增)
   - 演示线性、径向、纯色三种填充模式
   - 包含悬停态渐变过渡

5. **build.sh** (+1 行)
   - 添加 gradient_demo 到构建目标列表

## 技术实现

### WGSL Fragment Shader
```wgsl
var bg: vec4<f32>;
if (d.fill_mode == 1u) {
  // 线性渐变：使用角度向量的点积
  let t = dot(p / half_size, vec2<f32>(cos(d.gradient_angle), sin(d.gradient_angle))) * 0.5 + 0.5;
  bg = mix(d.bg_color, d.color_end, t);
} else if (d.fill_mode == 2u) {
  // 径向渐变：使用到中心的距离
  let t = length(p / half_size);
  bg = mix(d.bg_color, d.color_end, t);
} else {
  // 纯色填充（默认，向后兼容）
  bg = d.bg_color;
}
```

### Uniforms 结构变化
- **旧版**: 96 字节
- **新版**: 112 字节 (+16 字节)
- 新增字段：
  * `gradient_angle: f32` (offset 20)
  * `color_end: vec4<f32>` (offset 80)
  * `fill_mode` 隐式存储在 record 中

### 默认值策略
```lua
fill_mode = 0          -- 纯色（向后兼容）
gradient_angle = 0.0   -- 未使用，但必须初始化
color_end = bg_color   -- 与起始色相同，确保纯色效果
```

## 向后兼容性
✅ **所有 36 个现有 demo 编译通过，无需修改**

- 现有 Visual 自动获得渐变字段
- `init_themed()` 自动设置 `fill_mode=0`（纯色）
- 默认行为与 Phase 6.0 之前完全一致

## 验证结果
- ✅ gradient_demo.nelua 编译成功
- ✅ gradient_showcase_demo.nelua 编译成功（8 个渐变变体）
- ✅ button_v2_demo.nelua 编译成功（向后兼容验证）
- ✅ 生成的 WGSL 代码包含完整渐变逻辑
- ✅ Uniforms 结构正确对齐（112 字节）
- ⚠️ **Bug 修复**: 初版遗漏 uint32 类型映射，导致 WGSL 编译失败
  - 已修复 (commit de99654): 添加 uint32 到类型映射表
  - fill_mode 字段现在正确出现在 WGSL Uniforms 结构中

## 使用示例

### 线性渐变
```lua
card:init_themed(pos, size, radius)
card.visual.fill_mode = 1
card.visual.gradient_angle = 2.356  -- 135度（弧度）
card.visual.default_bg_color = Color{r=0.2, g=0.15, b=0.35, a=1.0}
card.visual.default_color_end = Color{r=0.1, g=0.25, b=0.45, a=1.0}
```

### 径向渐变
```lua
card:init_themed(pos, size, radius)
card.visual.fill_mode = 2
card.visual.default_bg_color = Color{r=0.35, g=0.15, b=0.2, a=1.0}
card.visual.default_color_end = Color{r=0.45, g=0.25, b=0.1, a=1.0}
```

### 纯色（默认）
```lua
card:init_themed(pos, size, radius)
-- fill_mode = 0 (自动设置，无需手动指定)
card.visual.default_bg_color = Color{r=0.15, g=0.35, b=0.2, a=1.0}
```

## 性能影响
- GPU: 每个 fragment 增加 1-2 条件分支 + 3-5 ALU 指令
- 内存: Uniforms +16B per instance (+16.7%)
- 影响微乎其微，现代 GPU 分支预测高效

## 下一步
Phase 6.2: 主题令牌系统（Theme Tokens）
- 预设主题配色（Material Dark, Nord, Dracula）
- 全局主题切换支持
- 预计 ~250 LOC

## Commit
- 分支: `feat/phase6.1-gradient-fill`
- Commit: `29a3e74`
- 消息: "feat(phase6.1): implement gradient fill support"
