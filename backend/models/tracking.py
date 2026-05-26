"""目标跟踪 - 基于 Supervision ByteTrack + Kalman 预测"""
from dataclasses import dataclass, field

import numpy as np
import cv2
import supervision as sv

from config.settings import config, TrackingConfig


@dataclass
class TrackPoint:
    """轨迹点"""
    frame_index: int
    x: float
    y: float
    confidence: float = 1.0
    predicted: bool = False  # 是否为预测点（遮挡期间）
    ball_area: float = 0.0  # 球的检测框面积（像素²）


@dataclass
class BallTrack:
    """篮球轨迹（带 Kalman 预测）"""
    track_id: int
    points: list[TrackPoint] = field(default_factory=list)
    _kalman: cv2.KalmanFilter | None = field(default=None, repr=False)
    _kf_initialized: bool = field(default=False, repr=False)
    _last_real_frame: int = field(default=-1, repr=False)

    def _init_kalman(self):
        """初始化 Kalman 滤波器：状态=[x, y, vx, vy]，观测=[x, y]"""
        kf = cv2.KalmanFilter(4, 2)
        kf.measurementMatrix = np.array([[1, 0, 0, 0],
                                          [0, 1, 0, 0]], dtype=np.float32)
        kf.transitionMatrix = np.array([[1, 0, 1, 0],
                                         [0, 1, 0, 1],
                                         [0, 0, 1, 0],
                                         [0, 0, 0, 1]], dtype=np.float32)
        kf.processNoiseCov = np.eye(4, dtype=np.float32) * 0.03
        kf.measurementNoiseCov = np.eye(2, dtype=np.float32) * 1.0
        self._kalman = kf

    def add_point(self, frame_index: int, x: float, y: float, confidence: float = 1.0, ball_area: float = 0.0):
        if self._kalman is None:
            self._init_kalman()

        measurement = np.array([[x], [y]], dtype=np.float32)
        if not self._kf_initialized:
            self._kalman.statePre = np.array([[x], [y], [0], [0]], dtype=np.float32)
            self._kalman.statePost = np.array([[x], [y], [0], [0]], dtype=np.float32)
            self._kf_initialized = True
        else:
            self._kalman.predict()
            self._kalman.correct(measurement)

        self.points.append(TrackPoint(frame_index, x, y, confidence, predicted=False, ball_area=ball_area))
        self._last_real_frame = frame_index

    def predict_position(self, frame_index: int) -> tuple[float, float] | None:
        """在遮挡期间预测球的位置（最多预测 10 帧）"""
        if self._kalman is None or not self._kf_initialized:
            return None
        if self._last_real_frame < 0:
            return None
        frames_lost = frame_index - self._last_real_frame
        if frames_lost <= 0 or frames_lost > 10:
            return None

        # 多步预测
        state = self._kalman.statePost.copy()
        for _ in range(frames_lost):
            state = self._kalman.transitionMatrix @ state

        px, py = float(state[0, 0]), float(state[1, 0])
        return (px, py)

    def add_predicted_point(self, frame_index: int, x: float, y: float):
        """添加预测点（不更新 Kalman 状态）"""
        self.points.append(TrackPoint(frame_index, x, y, confidence=0.3, predicted=True))

    @property
    def positions(self) -> np.ndarray:
        if not self.points:
            return np.array([])
        return np.array([(p.x, p.y) for p in self.points])

    @property
    def frame_indices(self) -> np.ndarray:
        return np.array([p.frame_index for p in self.points])

    @property
    def length(self) -> int:
        return len(self.points)

    def get_center_at(self, frame_index: int) -> tuple[float, float] | None:
        for p in self.points:
            if p.frame_index == frame_index:
                return (p.x, p.y)
        return None


def _create_tracker(cfg: TrackingConfig) -> sv.ByteTrack:
    """创建 ByteTrack 实例，兼容不同版本的 supervision"""
    try:
        return sv.ByteTrack(
            track_activation_threshold=cfg.track_thresh,
            lost_track_buffer=cfg.track_buffer,
            minimum_matching_threshold=cfg.match_thresh,
            minimum_consecutive_frames=cfg.min_hits,
        )
    except TypeError:
        try:
            return sv.ByteTrack(
                track_thresh=cfg.track_thresh,
                track_buffer=cfg.track_buffer,
                match_thresh=cfg.match_thresh,
                min_hits=cfg.min_hits,
            )
        except TypeError:
            return sv.ByteTrack()


class BallTracker:
    """篮球多目标跟踪器"""

    def __init__(self, tracking_config: TrackingConfig | None = None):
        self.config = tracking_config or config.tracking
        self._tracker = _create_tracker(self.config)
        self.tracks: dict[int, BallTrack] = {}

    def update(self, detections: sv.Detections, frame_index: int) -> sv.Detections:
        tracked = self._tracker.update_with_detections(detections)

        # 记录本帧有更新的 track_id
        active_ids = set()

        for i in range(len(tracked)):
            if tracked.tracker_id is not None:
                track_id = tracked.tracker_id[i]
                bbox = tracked.xyxy[i]
                cx = (bbox[0] + bbox[2]) / 2
                cy = (bbox[1] + bbox[3]) / 2
                conf = tracked.confidence[i] if tracked.confidence is not None else 1.0
                ball_area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
                active_ids.add(track_id)

                if track_id not in self.tracks:
                    self.tracks[track_id] = BallTrack(track_id=track_id)
                self.tracks[track_id].add_point(frame_index, cx, cy, conf, ball_area)

        # 对丢失的轨迹做 Kalman 预测（遮挡补偿）
        for track_id, track in self.tracks.items():
            if track_id not in active_ids and track.length >= 3:
                pred = track.predict_position(frame_index)
                if pred:
                    track.add_predicted_point(frame_index, pred[0], pred[1])

        return tracked

    def get_active_tracks(self) -> list[BallTrack]:
        return [t for t in self.tracks.values() if t.length >= self.config.min_hits]

    def reset(self):
        self._tracker = _create_tracker(self.config)
        self.tracks.clear()


class PlayerTracker:
    """球员跟踪器"""

    def __init__(self, tracking_config: TrackingConfig | None = None):
        self.config = tracking_config or config.tracking
        self._tracker = _create_tracker(self.config)

    def update(self, detections: sv.Detections, frame_index: int) -> sv.Detections:
        return self._tracker.update_with_detections(detections)
