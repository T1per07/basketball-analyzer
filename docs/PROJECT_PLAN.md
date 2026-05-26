# Basketball Shot Analyzer - 项目规划

## 项目概述

基于手机摄像头的篮球投篮分析系统，支持多种投篮类型识别、命中率统计、距离估算和轨迹分析。

## 核心功能

### 1. 投篮类型识别
| 类型 | 检测方法 | 关键特征 |
|------|---------|---------|
| 三分球 | 距离估算 + 远距离检测 | 球员在三分线外，抛物线弧度大 |
| 中距离 | 距离估算 | 球员在三分线内、罚球区外 |
| 上篮 | 动作序列检测 | 球员移动速度快，低弧度，近距离 |
| 扣篮 | 高度检测 + 近距离 | 球员跳跃高度接近篮筐，极近距离 |
| 罚球 | 位置检测 | 球员在罚球线固定位置 |

### 2. 核心统计
- **命中率**：总命中率、各类型命中率、分区命中率
- **距离分析**：平均投篮距离、最远命中、距离分布
- **轨迹分析**：抛物线拟合、出手角度、入筐角度
- **热力图**：球场投篮位置分布

### 3. 视频分析流程
```
输入视频 → 逐帧处理 → 目标检测 → 轨迹跟踪 → 事件判定 → 统计输出
```

## 技术架构

### 后端 (Python)
```
backend/
├── app.py                    # FastAPI 主入口
├── config/
│   └── settings.py           # 配置文件
├── models/
│   ├── detection.py          # 目标检测模型
│   ├── tracking.py           # 跟踪模型
│   └── trajectory.py         # 轨迹分析模型
├── services/
│   ├── video_processor.py    # 视频处理服务
│   ├── shot_analyzer.py      # 投篮分析服务
│   ├── stats_calculator.py   # 统计计算服务
│   └── court_mapper.py       # 球场映射服务
└── utils/
    ├── geometry.py           # 几何计算工具
    ├── video_utils.py        # 视频工具
    └── visualization.py      # 可视化工具
```

### 前端 (React + TypeScript)
```
frontend/
├── src/
│   ├── components/
│   │   ├── VideoUploader/    # 视频上传组件
│   │   ├── VideoPlayer/      # 视频播放器（带标注）
│   │   ├── StatsPanel/       # 统计面板
│   │   ├── ShotChart/        # 投篮热力图
│   │   ├── TrajectoryView/   # 轨迹分析视图
│   │   └── CourtMap/         # 球场地图
│   ├── pages/
│   │   ├── Home.tsx          # 首页
│   │   ├── Analysis.tsx      # 分析页面
│   │   └── History.tsx       # 历史记录
│   ├── hooks/
│   │   ├── useVideoUpload.ts
│   │   └── useAnalysis.ts
│   └── styles/
│       └── tokens.css        # 设计令牌
```

## 技术栈

### 后端
- **Python 3.9+**
- **FastAPI** - REST API 框架
- **Supervision** - CV 工具库（检测、跟踪、标注）
- **Ultralytics YOLOv8/YOLO11** - 目标检测
- **OpenCV** - 视频处理
- **NumPy/SciPy** - 数值计算、曲线拟合

### 前端
- **React 18** + **TypeScript**
- **Vite** - 构建工具
- **Tailwind CSS** - 样式框架
- **D3.js** - 数据可视化（热力图）
- **HTML5 Video** - 视频播放

## 开发阶段

### Phase 1 - 核心分析引擎 ✅ 当前阶段
- [x] 项目结构搭建
- [ ] 篮球检测模型集成
- [ ] 篮筐检测
- [ ] 球跟踪（ByteTrack）
- [ ] 抛物线轨迹拟合
- [ ] 命中判定逻辑
- [ ] 距离估算
- [ ] 投篮类型分类

### Phase 2 - 统计与可视化
- [ ] 命中率统计（按类型、区域）
- [ ] 距离统计分析
- [ ] 热力图生成
- [ ] 轨迹可视化
- [ ] 标注视频输出

### Phase 3 - Web 服务
- [ ] FastAPI 后端服务
- [ ] 视频上传 API
- [ ] 分析结果 API
- [ ] WebSocket 实时进度

### Phase 4 - 前端界面
- [ ] 前端项目初始化
- [ ] 视频上传页面
- [ ] 分析结果展示
- [ ] 统计图表
- [ ] 历史记录

### Phase 5 - 移动端适配
- [ ] 响应式设计
- [ ] 摄像头实时分析
- [ ] PWA 支持

## 参考资源

### GitHub 项目
- [chonyy/basketball-shot-detection](https://github.com/chonyy/basketball-shot-detection) - 投篮检测 + 姿态分析 (140 stars)
- [josephattalla/Basketball-Shot-Detection](https://github.com/josephattalla/Basketball-Shot-Detection) - YOLOv8 投篮追踪
- [nitinhemaraj/Basketball-shot-detection](https://github.com/nitinhemaraj/Basketball-shot-detection) - YOLOv8 + 轨迹预测
- [avishah3/AI-Basketball-Shot-Detection-Tracker](https://github.com/avishah3/AI-Basketball-Shot-Detection-Tracker) - 实时检测分析

### 数据集
- [Roboflow Universe](https://universe.roboflow.com/) - 搜索 "basketball" 获取标注数据集
- 自录制视频：三分、上篮、扣篮、中距离各 20+ 段

## 检测模型方案

### 篮球检测
- 方案 A：使用预训练 YOLO 模型 + COCO 数据集中的 "sports ball" 类别
- 方案 B：在 Roboflow 篮球数据集上微调 YOLO
- 推荐：先用方案 A 验证，效果不佳再用方案 B 微调

### 篮筐检测
- 方案 A：使用目标检测模型检测篮筐
- 方案 B：使用颜色+形状特征检测（篮筐橙色+圆形）
- 推荐：方案 A 更鲁棒

### 距离估算原理
```
已知：篮球真实直径 = 24.1cm
测量：篮球在图像中的像素直径
计算：距离 = (真实直径 × 焦距) / 像素直径
```
需要相机标定或使用标准篮球尺寸估算。
