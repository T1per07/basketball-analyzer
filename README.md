# Basketball Shot Analyzer / 篮球投篮分析系统

基于计算机视觉的篮球投篮分析系统。上传手机拍摄的投篮视频，自动检测投篮、分析轨迹、统计命中率。

A computer vision-based basketball shot analysis system. Upload phone-recorded shooting videos to automatically detect shots, analyze trajectories, and calculate shooting statistics.

## 功能 / Features

- **投篮检测 / Shot Detection** — HSV 颜色检测 + UP/DOWN 状态机 + 三方法投票命中判定
- **轨迹分析 / Trajectory Analysis** — 抛物线拟合，出手角度、入筐角度、R² 置信度
- **投篮分类 / Shot Classification** — 三分球 / 中距离 / 上篮，基于篮筐像素宽度的距离估算
- **统计面板 / Statistics** — 命中率、按类型统计、距离分布
- **视频处理 / Video Processing** — ffmpeg 帧提取 + 逐帧分析管线
- **跨平台 / Cross-Platform** — Flutter 移动端 + Python 后端

## 技术栈 / Tech Stack

| 层 / Layer | 技术 / Technology |
|---|---|
| 检测 / Detection | HSV 颜色空间 + 连通组件分析 / HSV color space + connected components |
| 轨迹 / Trajectory | 最小二乘抛物线拟合 / Least-squares polynomial fitting |
| 后端 / Backend | Python 3.10+ / FastAPI / WebSocket |
| 移动端 / Mobile | Flutter / Dart (跨平台 / cross-platform) |
| 前端 / Frontend | React 19 / TypeScript / Vite / Tailwind CSS 4 |
| 部署 / Deploy | Docker / docker-compose |

## 快速开始 / Quick Start

### Flutter 移动端 / Flutter Mobile App

```bash
cd basketball_analyzer_app
flutter pub get
flutter test           # 运行测试 / Run tests
flutter run            # 启动应用 / Launch app
```

**依赖 / Dependencies:** Flutter SDK, ffmpeg (in PATH)

### Python 后端 / Python Backend

```bash
# Windows
start.bat

# Unix
chmod +x start.sh && ./start.sh
```

### 手动启动 / Manual Start

```bash
# 后端 / Backend
cd backend
pip install -r requirements.txt
python app.py

# 前端 / Frontend
cd frontend
npm install
npm run dev
```

### Docker

```bash
docker-compose up --build
```

启动后访问 / After launch, visit: http://localhost:5173 (前端 / frontend) 或 / or http://localhost:8000/docs (API 文档 / docs).

## API

| 接口 / Endpoint | 方法 / Method | 说明 / Description |
|---|---|---|
| `/api/v1/analyze` | POST | 上传视频并分析 / Upload video and analyze |
| `/api/v1/status/{task_id}` | GET | 查询分析进度 / Check analysis progress |
| `/api/v1/results/{task_id}` | GET | 获取分析结果 / Get analysis results |
| `/api/v1/videos/{task_id}` | GET | 下载标注视频 / Download annotated video |
| `/ws/realtime` | WS | 实时视频分析 / Realtime video analysis |

## 项目结构 / Project Structure

```
basketball-analyzer/
├── basketball_analyzer_app/          # Flutter 移动端 / Flutter mobile app
│   ├── lib/
│   │   ├── models/                   # 数据模型 (ShotEvent, AnalysisResult...)
│   │   ├── services/
│   │   │   ├── color_ball_detector.dart    # HSV 篮球检测器
│   │   │   ├── hoop_detector.dart          # 篮筐检测器
│   │   │   ├── shot_detector.dart          # UP/DOWN 状态机
│   │   │   ├── shot_analyzer.dart          # 分析管线编排
│   │   │   ├── trajectory_analyzer.dart    # 抛物线拟合
│   │   │   └── video_processor.dart        # ffmpeg 视频处理
│   │   └── screens/                  # UI 页面
│   └── test/                         # 37 个测试用例
├── backend/                          # Python 后端 / Python backend
│   ├── app.py                        # FastAPI 主入口
│   ├── models/                       # 检测器 + 状态机
│   ├── services/                     # 分析服务
│   └── tests/                        # pytest 测试
├── frontend/                         # React 前端 / React frontend
└── docs/                             # 架构文档
```

## 检测原理 / Detection Pipeline

1. **检测 / Detection** — HSV 颜色空间检测橙色篮球 (H:5-25, S≥150, V≥150)，连通组件分析过滤噪声
2. **篮筐 / Hoop** — 红色篮筐颜色检测，锁定后持续跟踪
3. **投篮识别 / Shot Recognition** — UP/DOWN 状态机：球在篮筐上方区域 → UP，球下降经过篮筐 → DOWN
4. **命中判定 / Make/Miss** — 三方法投票：抛物线轨迹预测 / 篮筐区域穿越 / 接近度+下降运动
5. **轨迹分析 / Trajectory** — 最小二乘拟合 `y = ax² + bx + c`，计算出手角度、入射角、飞行时间
6. **距离估算 / Distance** — 篮筐真实直径 45.7cm，通过像素/真实比例换算球场距离

## 测试 / Testing

```bash
# Flutter 测试 / Flutter tests (37 用例)
cd basketball_analyzer_app
flutter test

# Python 测试 / Python tests
python -m pytest backend/tests/ -v

# 性能基准 / Performance benchmarks
flutter test test/services/performance_test.dart
```

### 性能指标 / Performance

| 组件 / Component | 速度 / Speed |
|---|---|
| ColorBallDetector (640x480) | ~13 ms/frame (77 FPS) |
| ColorBallDetector (1280x720) | ~9 ms/frame (111 FPS) |
| HoopDetector | ~0.5 ms/frame |
| ShotDetector | ~13 µs/call |
| ShotAnalyzer 完整管线 | ~14 ms/frame (73 FPS) |

## 参考 / References

- [roboflow/supervision](https://github.com/roboflow/supervision)
- [ultralytics/ultralytics](https://github.com/ultralytics/ultralytics)
- [chonyy/basketball-shot-detection](https://github.com/chonyy/basketball-shot-detection)
