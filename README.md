# Basketball Shot Analyzer

基于计算机视觉的篮球投篮分析系统。上传手机拍摄的投篮视频，自动检测投篮、分析轨迹、统计命中率。

## 功能

- **投篮检测** — YOLO + 颜色检测 + 运动检测，UP/DOWN 状态机 + 三方法投票判定命中
- **轨迹分析** — Savitzky-Golay 平滑 + 抛物线拟合，出手角度、入筐角度、R² 置信度
- **投篮分类** — 三分球 / 中距离 / 上篮 / 罚球，基于篮筐像素宽度的距离估算
- **统计面板** — 命中率、eFG%、区域热力图、距离分布、连中/连失、角度仪表盘
- **实时检测** — WebSocket 支持摄像头和视频文件实时分析
- **标注视频** — 带轨迹尾迹、命中特效、HUD 统计叠加的输出视频

## 技术栈

| 层 | 技术 |
|---|---|
| 检测 | YOLO (Ultralytics) + Supervision + ByteTrack |
| 轨迹 | SciPy curve_fit + Savitzky-Golay + Kalman Filter |
| 后端 | Python 3.10+ / FastAPI / WebSocket |
| 前端 | React 19 / TypeScript / Vite / Tailwind CSS 4 / Recharts |
| 部署 | Docker / docker-compose |

## 快速开始

### 一键启动

```bash
# Windows
start.bat

# Unix
chmod +x start.sh && ./start.sh
```

### 手动启动

```bash
# 后端
cd backend
pip install -r requirements.txt
python app.py

# 前端
cd frontend
npm install
npm run dev
```

### Docker

```bash
docker-compose up --build
```

启动后访问 http://localhost:5173 (前端) 或 http://localhost:8000/docs (API 文档)。

## API

| 接口 | 方法 | 说明 |
|---|---|---|
| `/api/v1/analyze` | POST | 上传视频并分析 |
| `/api/v1/status/{task_id}` | GET | 查询分析进度 |
| `/api/v1/results/{task_id}` | GET | 获取分析结果 JSON |
| `/api/v1/videos/{task_id}` | GET | 下载标注视频 |
| `/api/v1/health` | GET | 健康检查 |
| `/ws/realtime` | WS | 视频文件实时分析 |
| `/ws/camera` | WS | 摄像头实时分析 |

## 项目结构

```
basketball-analyzer/
├── backend/
│   ├── app.py                      # FastAPI 主入口
│   ├── config/settings.py          # 配置（6 个 dataclass）
│   ├── models/
│   │   ├── detection.py            # CombinedDetector（YOLO + 颜色 + 运动）
│   │   ├── basketball_detector.py  # YOLO 自定义模型
│   │   ├── hoop_detector.py        # 颜色检测篮筐
│   │   ├── shot_detector.py        # UP/DOWN 状态机 + 投票
│   │   ├── tracking.py             # ByteTrack + Kalman
│   │   └── trajectory.py           # 抛物线拟合 + 距离估算
│   ├── services/
│   │   ├── shot_analyzer.py        # 分析管线编排
│   │   ├── video_processor.py      # 视频 I/O + 标注
│   │   ├── stats_calculator.py     # 统计计算
│   │   └── realtime_service.py     # WebSocket 实时分析
│   ├── tests/                      # pytest 测试（16 用例）
│   └── utils/geometry.py           # 几何工具
├── frontend/
│   └── src/
│       ├── App.tsx                 # 三视图（上传/统计/实时）
│       ├── components/             # 8 个组件
│       └── hooks/                  # useAnalysis + useWebSocket
├── docs/                           # 架构文档 + 优化技术文档
├── tests/benchmark/                # 基准测试集
├── Dockerfile
└── docker-compose.yml
```

## 检测原理

1. **检测** — 自定义 YOLO 模型检测篮球（class 0）和篮筐（class 1），颜色检测作为篮筐回退
2. **跟踪** — ByteTrack 多目标跟踪 + Kalman 滤波遮挡预测
3. **投篮识别** — UP/DOWN 状态机：球在篮筐上方区域 → UP，球低于篮筐 → DOWN
4. **命中判定** — 三方法投票：抛物线预测 / 篮筐穿越 / 接近度 + 下降运动
5. **轨迹分析** — 上升段点拟合抛物线 `y = ax² + bx + c`，计算出手角度和距离
6. **距离估算** — 篮球真实直径 24.1cm，通过像素尺寸与真实尺寸的比例估算

## 测试

```bash
# 运行测试
python -m pytest backend/tests/ -v

# 运行基准测试
run_full_test.bat  # Windows
./run_full_test.sh # Unix
```

## 参考

- [roboflow/supervision](https://github.com/roboflow/supervision)
- [ultralytics/ultralytics](https://github.com/ultralytics/ultralytics)
- [chonyy/basketball-shot-detection](https://github.com/chonyy/basketball-shot-detection)
