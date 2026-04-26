# Phase 3.12 方案评估调研笔记

## 关键发现

### 1. 线性性验证结果
- 7 个场景中 21/24 个组件通过线性性验证
- 场景 6 (子元素总尺寸超过视口) 产生 65px 误差
- 根因: `max(0, free_space)` clamp 操作在临界点处引入分段线性行为

### 2. 数学分析
- Nebula Flexbox 引擎只有以下操作: 加法、减法、除法、max(0, x)
- 布局结果是视口的 **分段线性函数** (piecewise linear)，而非全局线性函数
- 唯一的非线性源: `max(0, free_space)` clamp
- 临界点可精确计算: threshold = main_total + total_gap + padding

### 3. 业界方案
- **Cassowary** (Apple Auto Layout): 增量约束求解器，运行时求解线性约束系统
- **ORCSolver** (CHI 2020): 处理 OR-constraints 的分支定界算法，支持分段布局切换
- **CSS Flexbox**: 运行时树遍历求解
- 所有主流方案都在运行时求解，没有发现"编译期预计算系数"的先例

### 4. 方案 D (clamp 感知) 验证结果
- 在溢出区域和正常区域分别采样，得到两组线性系数
- 运行时使用 if-else 分支选择正确的系数组
- 在场景 6 中验证通过: 预测值与实际值完全匹配 (误差 < 0.1)
