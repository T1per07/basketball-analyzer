# 系统架构设计

## 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                        用户界面层                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  视频上传    │  │  实时预览    │  │  统计结果展示        │  │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘  │
└─────────┼───────────────┼────────────────────┼──────────────┘
          │               │                    │
          ▼               ▼                    ▼
┌─────────────────────────────────────────────────────────────┐
│                       API 网关层                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ POST /upload │  │ WS /stream  │  │ GET /stats/{id}     │  │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘  │
└─────────┼───────────────┼────────────────────┼──────────────┘
          │               │                    │
          ▼               ▼                    ▼
┌─────────────────────────────────────────────────────────────┐
│                      业务逻辑层                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              VideoProcessorService                    │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌─────────┐ │   │
│  │  │ 检测引擎  │ │ 跟踪引擎  │ │ 轨迹分析  │ │ 统计引擎│ │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └─────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
          │               │                    │
          ▼               ▼                    ▼
┌─────────────────────────────────────────────────────────────┐
│                       模型层                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ YOLO 检测    │  │ ByteTrack   │  │ TrajectoryAnalyzer  │  │
│  │ (篮球/篮筐)  │  │ (多目标跟踪) │  │ (抛物线拟合)        │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## 数据流

```
视频输入
    │
    ▼
┌──────────────┐
│ 帧提取 (30fps) │
└──────┬───────┘
       │
       ▼
┌──────────────┐     ┌──────────────┐
│ YOLO 检测     │────▶│ Detections   │
│ (每帧)        │     │ (bbox+class) │
└──────┬───────┘     └──────┬───────┘
       │                    │
       ▼                    ▼
┌──────────────┐     ┌──────────────┐
│ ByteTrack    │────▶│ Tracks       │
│ (跨帧跟踪)   │     │ (ID+轨迹)    │
└──────┬───────┘     └──────┬───────┘
       │                    │
       ▼                    ▼
┌──────────────┐     ┌──────────────┐
│ 事件检测      │────▶│ ShotEvent    │
│ (出手/入筐)   │     │ (类型+结果)  │
└──────┬───────┘     └──────┬───────┘
       │                    │
       ▼                    ▼
┌──────────────┐     ┌──────────────┐
│ 轨迹分析      │────▶│ Trajectory   │
│ (抛物线拟合)  │     │ (角度+距离)  │
└──────┬───────┘     └──────┬───────┘
       │                    │
       ▼                    ▼
┌──────────────────────────────┐
│ StatisticsAggregator         │
│ (汇总所有统计数据)            │
└──────────────────────────────┘
```

## 关键算法

### 1. 投篮出手检测
```python
def detect_shot_release(ball_track):
    """
    检测投篮出手时刻
    条件：
    1. 篮球在球员手中（y坐标稳定）
    2. 篮球开始快速上升（y坐标急剧减小）
    3. 篮球速度突然增大
    """
    pass
```

### 2. 命中判定
```python
def detect_shot_made(ball_track, hoop_position):
    """
    判定投篮是否命中
    条件：
    1. 篮球轨迹向下阶段
    2. 篮球位置接近篮筐
    3. 篮球穿过篮筐平面
    """
    pass
```

### 3. 投篮类型分类
```python
def classify_shot_type(player_position, shot_distance, player_speed):
    """
    分类投篮类型
    - 三分球：距离 > 6.75m（FIBA）或 7.24m（NBA）
    - 中距离：2m < 距离 < 6.75m
    - 上篮：距离 < 2m + 高速移动
    - 扣篮：距离 < 1m + 跳跃高度接近篮筐
    - 罚球：在罚球线位置 + 静止
    """
    pass
```

### 4. 距离估算
```python
def estimate_distance(ball_pixel_diameter, image_width, fov_angle=60):
    """
    基于篮球尺寸估算距离
    篮球真实直径：24.1cm
    距离 = (真实直径 × 焦距) / 像素直径
    """
    real_diameter = 0.241  # meters
    focal_length = (image_width / 2) / math.tan(math.radians(fov_angle / 2))
    distance = (real_diameter * focal_length) / ball_pixel_diameter
    return distance
```

## API 设计

### POST /api/v1/analyze
上传视频并开始分析

**Request:**
```
Content-Type: multipart/form-data
Body: video file
```

**Response:**
```json
{
  "task_id": "abc123",
  "status": "processing",
  "message": "Video uploaded, analysis started"
}
```

### GET /api/v1/status/{task_id}
获取分析进度

**Response:**
```json
{
  "task_id": "abc123",
  "status": "processing",
  "progress": 0.45,
  "current_frame": 450,
  "total_frames": 1000
}
```

### GET /api/v1/results/{task_id}
获取分析结果

**Response:**
```json
{
  "task_id": "abc123",
  "status": "completed",
  "summary": {
    "total_shots": 25,
    "made_shots": 18,
    "overall_percentage": 0.72,
    "by_type": {
      "three_point": {"attempts": 8, "made": 5, "percentage": 0.625},
      "mid_range": {"attempts": 7, "made": 6, "percentage": 0.857},
      "layup": {"attempts": 6, "made": 5, "percentage": 0.833},
      "dunk": {"attempts": 2, "made": 2, "percentage": 1.0},
      "free_throw": {"attempts": 2, "made": 0, "percentage": 0.0}
    },
    "average_distance": 4.2,
    "max_made_distance": 7.1,
    "shot_locations": [
      {"x": 0.3, "y": 0.4, "made": true, "type": "three_point"},
      {"x": 0.6, "y": 0.2, "made": false, "type": "mid_range"}
    ]
  },
  "shots": [
    {
      "shot_id": 1,
      "frame_start": 120,
      "frame_end": 180,
      "type": "three_point",
      "made": true,
      "distance": 6.8,
      "release_angle": 52.3,
      "entry_angle": 45.1,
      "trajectory": [[x1,y1], [x2,y2], ...]
    }
  ],
  "annotated_video_url": "/api/v1/videos/abc123_annotated.mp4"
}
```

### WebSocket /api/v1/stream
实时视频流分析

**Client sends:** video frames
**Server sends:** real-time detections and stats
