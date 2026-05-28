# Basketball Shot Analyzer / 篮球投篮分析器

> Cross-platform basketball shot analysis powered by computer vision. Upload a video, detect shots, track trajectories, and get detailed stats.
>
> 跨平台篮球投篮分析工具。上传视频，自动检测投篮、追踪轨迹、生成详细统计。

---

## Features / 功能

- **Video Analysis / 视频分析**: Upload basketball footage, auto-detect shot events frame by frame
- **Shot Detection / 投篮检测**: UP-DOWN state machine + 3-method voting (trajectory intersection, rim crossing, proximity detection)
- **Trajectory Tracking / 轨迹追踪**: Savitzky-Golay smoothing, polynomial fitting, R-squared validation
- **Hit/Miss Detection / 命中判定**: Multi-method scoring with confidence levels
- **Shot Classification / 投篮分类**: Auto-classify as three-point, mid-range, layup, free-throw, dunk
- **Kinematics / 运动学参数**: Release angle, entry angle, shot speed, flight time, arc height
- **Court Heatmap / 投篮热力图**: Visual shot distribution on half-court diagram
- **Export / 导出**: Excel (.xlsx) and PDF report generation
- **Cross-platform / 跨平台**: Windows, Android, iOS, macOS, Linux

## Getting Started / 快速开始

### Prerequisites / 前置条件

- [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.44+
- ffmpeg (for video frame extraction / 用于视频帧提取)

### Install / 安装

```bash
# Clone / 克隆
git clone https://github.com/YOUR_USERNAME/basketball-analyzer.git
cd basketball-analyzer/basketball_analyzer_app

# China mirror (if needed / 国内镜像)
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_HOSTED_URL=https://pub.flutter-io.cn

# Dependencies / 安装依赖
flutter pub get

# Run / 运行
flutter run
```

### Build / 构建

```bash
# Windows
flutter build windows --release

# Android (requires Android SDK / 需要 Android SDK)
flutter build apk --release

# iOS (requires Xcode / 需要 Xcode)
flutter build ios --release
```

## Architecture / 架构

```
lib/
├── main.dart              # Entry point / 入口
├── app.dart               # App shell, navigation, theme / 应用壳、导航、主题
├── app_state.dart         # Global state (Provider) / 全局状态管理
├── models/                # Data models / 数据模型
│   ├── config.dart        # All thresholds & constants / 配置常量
│   ├── shot_event.dart    # ShotResult, ShotEvent, AnalysisResult
│   ├── ball_track.dart    # Ball tracking with prediction / 球跟踪+预测
│   ├── track_point.dart   # Single track point / 单个跟踪点
│   ├── trajectory_params.dart
│   └── detection_result.dart
├── services/              # Core algorithms / 核心算法
│   ├── video_processor.dart      # ffmpeg frame extraction / ffmpeg 读帧
│   ├── shot_analyzer.dart        # Orchestrator / 分析编排器
│   ├── shot_detector.dart        # UP-DOWN state machine / 状态机检测
│   ├── trajectory_analyzer.dart  # Polynomial fitting / 多项式拟合
│   ├── hoop_detector.dart        # Hoop detection + tracking / 篮筐检测
│   └── color_ball_detector.dart  # Ball detection by color / 颜色检测球
├── screens/               # UI pages / 页面
│   ├── upload_screen.dart    # Video upload + analysis / 上传+分析
│   ├── analysis_screen.dart  # Stats display + export / 统计+导出
│   └── live_screen.dart      # Real-time mode (WIP) / 实时模式（开发中）
├── widgets/               # Reusable components / 可复用组件
│   ├── stats_panel.dart      # Stats display panel / 统计面板
│   └── shot_chart.dart       # Court heatmap / 投篮热力图
├── painters/              # Custom painters / 自定义绘制
│   ├── court_painter.dart       # Half-court diagram / 半场图
│   └── shot_overlay_painter.dart # Trajectory overlay / 轨迹叠加
└── utils/                 # Utilities / 工具
    ├── export_excel.dart   # Excel export / Excel 导出
    └── export_pdf.dart     # PDF export / PDF 导出
```

## How It Works / 工作原理

1. **Upload** a basketball video (MP4, MOV, AVI, etc.) / 上传篮球视频
2. **ffmpeg** extracts raw BGR frames at configurable FPS / ffmpeg 按配置帧率提取 BGR 原始帧
3. **Color detector** scans each frame for orange ball pixels / 颜色检测器扫描每帧中的橙色篮球像素
4. **Hoop detector** calibrates via multi-frame median, then tracks with EMA / 篮筐检测器通过多帧中位数校准，然后用 EMA 跟踪
5. **Shot detector** runs UP-DOWN state machine + 3-method scoring vote / 投篮检测器运行 UP-DOWN 状态机 + 3 方法投票
6. **Trajectory analyzer** fits parabola, computes kinematics / 轨迹分析器拟合抛物线，计算运动学参数
7. **Results** displayed with stats, heatmap, and export options / 结果展示统计、热力图和导出选项

## Status / 当前状态

| Feature / 功能 | Status / 状态 |
|---|---|
| Video analysis / 视频分析 | Working / 可用 |
| Shot detection / 投篮检测 | Working / 可用 |
| Hit/Miss detection / 命中判定 | Fixed (v1.0.1) / 已修复 |
| Trajectory fitting / 轨迹拟合 | Working / 可用 |
| Stats display / 统计展示 | Working / 可用 |
| Excel/PDF export / 导出 | Working / 可用 |
| Court heatmap / 热力图 | Working / 可用 |
| Real-time camera / 实时摄像头 | WIP / 开发中 |
| ONNX model inference / ONNX 推理 | Planned / 计划中 |
| Android build / Android 构建 | Needs SDK / 需安装 SDK |

## Tech Stack / 技术栈

- **Framework**: Flutter 3.44 + Dart 3.12
- **State Management**: Provider
- **Video Processing**: ffmpeg subprocess
- **Detection**: Custom RGB color thresholding + grid scanning
- **Trajectory**: Savitzky-Golay filter + least-squares polynomial fitting
- **Export**: excel package + pdf package

## License / 许可

MIT
