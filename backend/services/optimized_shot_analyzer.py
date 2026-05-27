"""优化的投篮分析服务 - 集成优化检测器"""
import math
from dataclasses import dataclass, field

import numpy as np

from models.optimized_detector import OptimizedCombinedDetector
from models.detection import DetectionResult
from models.tracking import BallTracker, BallTrack, PlayerTracker
from models.trajectory import TrajectoryAnalyzer, TrajectoryParams
from models.shot_detector import ShotDetector
from config.settings import config, ShotType


@dataclass
class ShotEvent:
    """一次投篮事件"""
    shot_id: int
    track_id: int
    frame_start: int
    frame_end: int
    shot_type: str
    made: bool
    distance: float
    release_angle: float
    entry_angle: float
    trajectory_points: list[tuple[float, float]]
    confidence: float
    crossing_x: float = 0.0
    hoop_x: int = 0
    flight_time: float = 0.0
    shot_speed: float = 0.0
    arc_height: float = 0.0


@dataclass
class AnalysisResult:
    """完整分析结果"""
    total_frames: int
    fps: float
    shots: list[ShotEvent] = field(default_factory=list)

    @property
    def total_shots(self) -> int:
        return len(self.shots)

    @property
    def made_shots(self) -> int:
        return sum(1 for s in self.shots if s.made)

    @property
    def overall_percentage(self) -> float:
        return self.made_shots / self.total_shots if self.total_shots > 0 else 0.0

    @property
    def average_distance(self) -> float:
        distances = [s.distance for s in self.shots if s.distance > 0]
        return sum(distances) / len(distances) if distances else 0.0

    @property
    def average_speed(self) -> float:
        speeds = [s.shot_speed for s in self.shots if s.shot_speed > 0]
        return sum(speeds) / len(speeds) if speeds else 0.0

    @property
    def average_flight_time(self) -> float:
        times = [s.flight_time for s in self.shots if s.flight_time > 0]
        return sum(times) / len(times) if times else 0.0

    @property
    def average_arc_height(self) -> float:
        heights = [s.arc_height for s in self.shots if s.arc_height > 0]
        return sum(heights) / len(heights) if heights else 0.0

    def get_stats_by_type(self) -> dict[str, dict]:
        stats = {}
        for shot_type in ShotType:
            type_shots = [s for s in self.shots if s.shot_type == shot_type.value]
            if type_shots:
                made = sum(1 for s in type_shots if s.made)
                stats[shot_type.value] = {
                    "attempts": len(type_shots),
                    "made": made,
                    "percentage": made / len(type_shots),
                    "avg_distance": float(np.mean([s.distance for s in type_shots])),
                }
        return stats


class OptimizedShotAnalyzer:
    """优化的投篮分析器 - 使用优化检测器"""

    def __init__(self, fps: float = 30.0):
        self.detector = OptimizedCombinedDetector()
        self.ball_tracker = BallTracker()
        self.player_tracker = PlayerTracker()
        self.trajectory_analyzer = TrajectoryAnalyzer()
        self.trajectory_analyzer.set_fps(fps)
        self.shot_detector = ShotDetector(fps=fps)

        self._shot_counter = 0
        self._hoop_position: tuple[int, int] | None = None
        self._hoop_box: tuple[int, int, int, int] | None = None

    def reset(self):
        self.ball_tracker.reset()
        self.detector.reset()
        self.shot_detector.reset()
        self._shot_counter = 0

    def process_frame(self, frame: np.ndarray, frame_index: int) -> DetectionResult:
        detection = self.detector.detect(frame, frame_index)

        # 更新篮筐位置到 ShotDetector 和 TrajectoryAnalyzer
        if detection.hoop_position and detection.hoop_box:
            x, y, w, h = detection.hoop_box
            self.shot_detector.update_hoop(x, y, w, h)
            self._hoop_position = detection.hoop_position
            self._hoop_box = detection.hoop_box

            # 更新轨迹分析器的篮筐参考
            self.trajectory_analyzer.update_hoop_reference(
                detection.hoop_position, float(w)
            )

        # 更新球跟踪
        if len(detection.ball_detections) > 0:
            self.ball_tracker.update(detection.ball_detections, frame_index)

        # 获取当前帧所有球的位置、大小和置信度
        ball_positions, ball_sizes, ball_confs = self._get_ball_data(detection)

        # ShotDetector 处理（UP→DOWN→SCORE 状态机）
        self.shot_detector.process_frame(
            ball_positions, ball_sizes, ball_confs,
            frame_index=frame_index,
        )

        return detection

    def _get_ball_data(
        self, detection: DetectionResult
    ) -> tuple[list[tuple[float, float]], list[float], list[float]]:
        """从当前帧检测结果提取球位置、大小和置信度"""
        positions = []
        sizes = []
        confidences = []

        if len(detection.ball_detections) > 0:
            for i in range(len(detection.ball_detections)):
                bbox = detection.ball_detections.xyxy[i]
                cx = (bbox[0] + bbox[2]) / 2
                cy = (bbox[1] + bbox[3]) / 2
                area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
                conf = float(detection.ball_detections.confidence[i]) if detection.ball_detections.confidence is not None else 0.5
                positions.append((cx, cy))
                sizes.append(float(area))
                confidences.append(conf)

        return positions, sizes, confidences

    def build_result(self, total_frames: int, fps: float) -> AnalysisResult:
        result = AnalysisResult(total_frames=total_frames, fps=fps)

        shot_results = self.shot_detector.shot_results

        # 从 ShotDetector 获取每个投篮的独立轨迹
        sd_tracks = self._convert_sd_tracks()
        # 也保留 ByteTracker 的轨迹作为备选
        active_tracks = self.ball_tracker.get_active_tracks()
        if sd_tracks:
            active_tracks = sd_tracks + active_tracks

        for shot_result in shot_results:
            track = self._find_track_for_shot(shot_result, active_tracks)

            if track:
                trajectory = self.trajectory_analyzer.fit_trajectory(track)
                if trajectory:
                    distance = trajectory.estimated_distance
                    release_angle = trajectory.release_angle
                    entry_angle = trajectory.entry_angle
                    traj_confidence = trajectory.fit_r_squared
                    flight_time = trajectory.flight_time
                    shot_speed = trajectory.shot_speed
                    arc_height = trajectory.arc_height
                else:
                    distance = self._fallback_distance(track)
                    release_angle = 0.0
                    entry_angle = 0.0
                    traj_confidence = 0.0
                    flight_time = 0.0
                    shot_speed = 0.0
                    arc_height = 0.0

                shot_type = self.trajectory_analyzer.classify_shot_type(
                    trajectory) if trajectory else self._classify_by_distance(distance)
                trajectory_points = [(p.x, p.y) for p in track.points]

                if release_angle > 75 or release_angle < 15:
                    release_angle = 0.0
                if entry_angle > 80 or entry_angle < 10:
                    entry_angle = 0.0
            else:
                shot_type = "mid_range"
                distance = 0.0
                release_angle = 0.0
                entry_angle = 0.0
                traj_confidence = 0.0
                trajectory_points = []
                flight_time = 0.0
                shot_speed = 0.0
                arc_height = 0.0

            self._shot_counter += 1
            result.shots.append(ShotEvent(
                shot_id=self._shot_counter,
                track_id=0,
                frame_start=max(0, shot_result.frame - int(1.5 * fps)),
                frame_end=shot_result.frame,
                shot_type=shot_type,
                made=shot_result.made,
                distance=distance,
                release_angle=release_angle,
                entry_angle=entry_angle,
                trajectory_points=trajectory_points,
                confidence=max(traj_confidence, shot_result.confidence),
                crossing_x=0.0,
                hoop_x=shot_result.hoop_x,
                flight_time=flight_time,
                shot_speed=shot_speed,
                arc_height=arc_height,
            ))

        return result

    def _convert_sd_tracks(self) -> list:
        """将 ShotDetector 的投篮轨迹转换为 BallTrack 格式"""
        from models.tracking import BallTrack as TrackerBallTrack, TrackPoint
        converted = []

        shot_positions = self.shot_detector._shot_ball_positions
        if not shot_positions:
            return converted

        for shot_idx, shot_result in enumerate(self.shot_detector.shot_results):
            positions = shot_positions.get(shot_idx, [])
            if not positions:
                continue

            shot_frame = shot_result.frame
            lookback = int(2.0 * self.shot_detector._fps)
            start_frame = max(0, shot_frame - lookback)

            segment = [
                p for p in positions
                if start_frame <= p[2] <= shot_frame
            ]

            if len(segment) < 2:
                segment = positions[-30:] if len(positions) >= 2 else []

            if len(segment) < 2:
                continue

            bt = TrackerBallTrack(track_id=shot_idx)
            for cx, cy, frame, w, h, conf in segment:
                area = w * h
                bt.points.append(TrackPoint(
                    frame_index=frame, x=cx, y=cy,
                    confidence=conf, ball_area=area,
                ))
            converted.append(bt)

        return converted

    def _find_track_for_shot(
        self, shot_result, active_tracks: list[BallTrack]
    ) -> BallTrack | None:
        """找到与投篮结果对应的轨迹"""
        shot_frame = shot_result.frame
        hoop_x = shot_result.hoop_x

        # 方法 1: 精确匹配 SD 轨迹
        shot_idx = None
        for i, sr in enumerate(self.shot_detector.shot_results):
            if sr is shot_result:
                shot_idx = i
                break

        if shot_idx is not None:
            for track in active_tracks:
                if track.track_id == shot_idx and len(track.points) >= 2:
                    return track

        # 方法 2: 时空距离匹配
        best_track = None
        best_score = float('inf')

        for track in active_tracks:
            if not track.points:
                continue
            closest_point = min(track.points, key=lambda p: abs(p.frame_index - shot_frame))
            time_diff = abs(closest_point.frame_index - shot_frame)
            if time_diff > int(3.0 * self.shot_detector._fps):
                continue
            spatial_dist = abs(closest_point.x - hoop_x)
            score = time_diff * 2 + spatial_dist
            if score < best_score:
                best_score = score
                best_track = track

        if best_track and best_score < 500:
            return best_track

        # 方法 3: 最后回退
        if active_tracks:
            with_points = [t for t in active_tracks if t.points]
            if with_points:
                with_area = [t for t in with_points
                             if any(p.ball_area > 0 for p in t.points)]
                candidates = with_area if with_area else with_points
                return min(candidates, key=lambda t: min(
                    abs(p.frame_index - shot_frame) for p in t.points
                ))

        return None

    def _fallback_distance(self, track) -> float:
        """轨迹拟合失败时的距离回退估算"""
        distance = self.trajectory_analyzer._estimate_distance(track)
        if distance > 0:
            return distance

        if not track.points:
            return 0.0

        hoop_w = self.trajectory_analyzer._hoop_pixel_width
        hoop_pos = self.trajectory_analyzer._hoop_position or self._hoop_position

        if hoop_w > 0 and hoop_pos is not None:
            hoop_x, hoop_y = hoop_pos
            mpp = config.court.rim_diameter / hoop_w
            start_point = track.points[0]
            pixel_dist = math.sqrt(
                (start_point.x - hoop_x) ** 2 + (start_point.y - hoop_y) ** 2
            )
            return max(0.5, min(pixel_dist * mpp, 10.0))

        xs = [p.x for p in track.points]
        span = max(xs) - min(xs)
        if span > 0:
            return max(0.5, min(span * 0.025, 8.0))

        return 0.0

    def _classify_by_distance(self, distance: float) -> str:
        """根据距离分类投篮类型"""
        tc = config.trajectory
        if distance < tc.layup_max_distance:
            return "layup"
        elif distance < tc.mid_range_max_distance:
            return "mid_range"
        else:
            return "three_point"

    def get_current_stats(self) -> dict:
        total = self.shot_detector.total_shots
        made = self.shot_detector.total_made
        return {
            "投篮": total,
            "命中": made,
            "命中率": f"{made/total*100:.0f}%" if total > 0 else "0%",
            "篮筐": "已锁定" if self.shot_detector.hoop_detected else "搜索中",
        }
