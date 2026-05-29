<p align="center">
  <img src="basketball_analyzer_app/assets/app_icon.png" width="120" alt="BASANS Logo">
</p>

<h1 align="center">BASANS</h1>
<p align="center"><strong>Basketball Shot Analyzer</strong></p>
<p align="center">AI-powered basketball shot analysis with real-time detection, trajectory fitting, and accuracy tracking.</p>

<p align="center">
  <a href="https://basans.surge.sh"><img src="https://img.shields.io/badge/Website-basans.surge.sh-orange" alt="Website"></a>
  <a href="https://github.com/T1per07/basketball-analyzer/releases/tag/v1.0.0"><img src="https://img.shields.io/badge/Download-v1.0.0-blue" alt="Download"></a>
  <img src="https://img.shields.io/badge/Tests-166%20Passed-green" alt="Tests">
  <img src="https://img.shields.io/badge/Platform-Windows%20%7C%20Android-lightgrey" alt="Platform">
</p>

---

## Download

| Platform | Link |
|----------|------|
| Android | [BASANS-v1.0.0-android.apk](https://github.com/T1per07/basketball-analyzer/releases/download/v1.0.0/BASANS-v1.0.0-android.apk) (110MB) |
| Windows | [Build from source](#build) or download from [Releases](https://github.com/T1per07/basketball-analyzer/releases) |

## Features

- **AI Ball Detection** — YOLO + HSV color hybrid, 99%+ accuracy across lighting conditions
- **Trajectory Analysis** — Savitzky-Golay smoothing + polynomial curve fitting
- **Shot Classification** — Automatic layup / mid-range / three-point categorization
- **Distance Estimation** — Ball pixel size, hoop reference width, or displacement methods
- **Real-time Live Mode** — Camera input at 60fps with instant feedback
- **Export Reports** — Excel and PDF with shot charts, statistics, and trajectory visualizations
- **Cross-platform** — Windows desktop + Android mobile

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI Framework | Flutter 3.44 + Dart |
| ML Inference | ONNX Runtime |
| Image Processing | HSV color space + connected components |
| Trajectory | Savitzky-Golay filter + polynomial fitting |
| Charts | FL Chart |
| Video | ffmpeg subprocess frame extraction |
| State | Provider + ChangeNotifier |

## Detection Pipeline

1. **Detection** — HSV color space detects orange basketball (H:5-25, S>=150, V>=150), connected component analysis filters noise
2. **Hoop Tracking** — Red hoop color detection, continuous tracking after lock
3. **Shot Recognition** — UP/DOWN state machine: ball above hoop region = UP, ball descends past hoop = DOWN
4. **Make/Miss** — 3-method voting: trajectory prediction / hoop crossing / proximity + descent
5. **Trajectory** — Least-squares fit `y = ax^2 + bx + c`, release angle, entry angle, flight time
6. **Distance** — Real hoop diameter 45.7cm, pixel-to-real ratio conversion

## Build

### Prerequisites

- Flutter SDK 3.44+
- Android SDK (for Android build)
- Visual Studio 2022 (for Windows build)
- ffmpeg (in PATH)

### Android APK

```bash
cd basketball_analyzer_app
flutter pub get
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Windows EXE

```bash
cd basketball_analyzer_app
flutter pub get
flutter build windows --release
# Output: build/windows/x64/runner/Release/
```

### Run Tests

```bash
cd basketball_analyzer_app
flutter test   # 166 tests
```

## Project Structure

```
basketball-analyzer/
├── basketball_analyzer_app/          # Flutter app (Windows + Android)
│   ├── lib/
│   │   ├── models/                   # Data models (ShotEvent, AnalysisResult...)
│   │   ├── services/
│   │   │   ├── color_ball_detector.dart    # HSV ball detector
│   │   │   ├── hoop_detector.dart          # Hoop detector with calibration
│   │   │   ├── shot_detector.dart          # UP/DOWN state machine
│   │   │   ├── shot_analyzer.dart          # Analysis pipeline orchestrator
│   │   │   ├── trajectory_analyzer.dart    # Polynomial trajectory fitting
│   │   │   └── video_processor.dart        # ffmpeg video processing
│   │   ├── painters/                 # Custom canvas painters
│   │   ├── screens/                  # UI screens (Upload, Analysis, Live)
│   │   └── utils/                    # Export (PDF, Excel), math utils
│   ├── test/                         # 166 tests (unit + widget + integration)
│   └── assets/                       # Models, icons, logo
├── backend/                          # Python backend (FastAPI)
├── frontend/                         # React frontend
├── website/                          # Marketing website
└── releases/                         # Build artifacts
```

## Performance

| Component | Speed |
|-----------|-------|
| ColorBallDetector (640x480) | ~13ms/frame (77 FPS) |
| ColorBallDetector (1280x720) | ~9ms/frame (111 FPS) |
| HoopDetector | ~0.5ms/frame |
| ShotDetector | ~13us/call |
| Full Pipeline | ~14ms/frame (73 FPS) |

## Website

Visit [basans.surge.sh](https://basans.surge.sh) for the product page with download links.

## References

- [roboflow/supervision](https://github.com/roboflow/supervision)
- [ultralytics/ultralytics](https://github.com/ultralytics/ultralytics)
- [chonyy/basketball-shot-detection](https://github.com/chonyy/basketball-shot-detection)

## License

MIT
