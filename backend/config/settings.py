"""项目配置 — 所有魔法数字、阈值、倍率集中管理"""
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path


class ShotType(Enum):
    THREE_POINT = "three_point"
    MID_RANGE = "mid_range"
    LAYUP = "layup"
    DUNK = "dunk"
    FREE_THROW = "free_throw"


@dataclass(frozen=True)
class CourtDimensions:
    """FIBA 标准球场尺寸（米）"""
    length: float = 28.0
    width: float = 15.0
    three_point_line: float = 6.75
    free_throw_line: float = 5.8
    rim_height: float = 3.05
    rim_diameter: float = 0.45
    backboard_width: float = 1.8
    restricted_area: float = 1.25


@dataclass(frozen=True)
class BallProperties:
    """篮球物理属性"""
    real_diameter: float = 0.241
    real_circumference: float = 0.756
    color_hsv_lower: tuple = (3, 80, 80)
    color_hsv_upper: tuple = (25, 255, 255)


@dataclass(frozen=True)
class DetectionConfig:
    """检测配置"""
    ball_confidence_threshold: float = 0.1
    hoop_confidence_threshold: float = 0.2
    player_confidence_threshold: float = 0.3
    ball_model_name: str = "yolo11n.onnx"
    custom_ball_model_path: str | None = None
    basketball_model_path: str = "models/best.pt"
    use_basketball_model: bool = True
    input_width: int = 416
    skip_frames: int = 2
    yolo_interval: int = 10
    use_half: bool = False
    enable_color_detection: bool = True
    enable_motion_detection: bool = True
    motion_threshold: float = 20.0
    # 以下为新增的检测参数（原为魔法数字）
    color_detect_target_width: int = 320      # 颜色检测内部缩放宽度
    max_balls_per_frame: int = 3               # 每帧最大球数
    nms_threshold: float = 0.3                 # NMS 去重阈值
    hoop_calib_frames: int = 12                # 篮筐校准所需帧数
    hoop_calib_filter_dist: int = 100          # 篮筐校准过滤距离
    hoop_tracking_max_dist_ratio: float = 0.6  # 篮筐跟踪最大距离比例


@dataclass(frozen=True)
class TrackingConfig:
    """跟踪配置"""
    track_thresh: float = 0.15
    track_buffer: int = 60
    match_thresh: float = 0.7
    min_hits: int = 2
    kalman_max_lost_frames: int = 10           # Kalman 预测最大丢失帧数


@dataclass(frozen=True)
class ShotDetectionConfig:
    """投篮检测配置"""
    min_shot_frames: int = 2
    max_shot_frames: int = 120
    shot_cooldown_frames: int = 10
    trajectory_r_squared_threshold: float = 0.20
    # 以下为新增的投篮检测参数
    cooldown_fps_ratio: float = 0.3            # 冷却帧 = max(5, ratio * fps)
    cooldown_min_frames: int = 5               # 最小冷却帧数
    confidence_high: float = 0.45              # 高置信度阈值
    confidence_low: float = 0.25               # 低置信度阈值（需配合 apex）


@dataclass(frozen=True)
class VideoProcessingConfig:
    """视频处理配置（原为散落的魔法数字）"""
    target_process_fps: int = 30               # 分析时的目标帧率（优化后提升至 30）
    output_fps: float = 60.0                   # 标注视频输出帧率
    flash_frames: int = 25                     # 投篮命中/失误特效帧数
    # UP zone 倍率（相对于篮筐宽高）
    up_zone_width_mult: float = 3.5
    up_zone_height_mult: float = 2.5
    up_zone_y_offset: float = 0.3
    # DOWN zone 倍率
    down_zone_width_mult: float = 2.5
    down_zone_height_mult: float = 3.0
    down_zone_y_offset: float = 0.2


@dataclass(frozen=True)
class TrajectoryConfig:
    """轨迹分析配置（原为硬编码值）"""
    default_frame_width: int = 852             # 默认帧宽度（会动态更新）
    camera_fov_degrees: float = 30.0           # 假设摄像头视场角
    savgol_window: int = 9                     # Savitzky-Golay 平滑窗口
    savgol_polyorder: int = 2                  # Savitzky-Golay 多项式阶数
    pixel_to_meter_fallback: float = 0.01      # 像素到米的粗略换算因子
    ball_diameter_real: float = 0.241          # 篮球真实直径（米）
    # 投篮类型分类距离阈值（米）
    layup_max_distance: float = 1.5
    mid_range_max_distance: float = 4.5
    three_point_min_distance: float = 4.5
    three_point_max_distance: float = 6.5


@dataclass(frozen=True)
class SecurityConfig:
    """安全配置"""
    max_upload_size_mb: int = 500
    allowed_video_extensions: tuple = (".mp4", ".mov", ".avi", ".webm", ".mkv")
    allowed_origins: tuple = (
        "http://localhost:3000",
        "http://localhost:8000",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:8000",
    )
    camera_source_max: int = 10                # 摄像头索引上限
    poll_max_retries: int = 150                # 前端轮询最大重试次数


@dataclass(frozen=True)
class RealtimeConfig:
    """实时分析配置"""
    target_fps: int = 15
    jpeg_quality: int = 70
    max_width: int = 640


@dataclass
class AppConfig:
    """应用配置"""
    court: CourtDimensions = field(default_factory=CourtDimensions)
    ball: BallProperties = field(default_factory=BallProperties)
    detection: DetectionConfig = field(default_factory=DetectionConfig)
    tracking: TrackingConfig = field(default_factory=TrackingConfig)
    shot: ShotDetectionConfig = field(default_factory=ShotDetectionConfig)
    video: VideoProcessingConfig = field(default_factory=VideoProcessingConfig)
    trajectory: TrajectoryConfig = field(default_factory=TrajectoryConfig)
    security: SecurityConfig = field(default_factory=SecurityConfig)
    realtime: RealtimeConfig = field(default_factory=RealtimeConfig)
    project_root: Path = Path(__file__).parent.parent.parent
    data_dir: Path = field(default=None)
    output_dir: Path = field(default=None)
    video_upload_dir: Path = field(default=None)

    def __post_init__(self):
        if self.data_dir is None:
            object.__setattr__(self, 'data_dir', self.project_root / 'data')
        if self.output_dir is None:
            object.__setattr__(self, 'output_dir', self.data_dir / 'output')
        if self.video_upload_dir is None:
            object.__setattr__(self, 'video_upload_dir', self.data_dir / 'uploads')
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.video_upload_dir.mkdir(parents=True, exist_ok=True)


config = AppConfig()
