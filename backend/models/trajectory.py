"""轨迹分析 - 抛物线拟合、出手角度、距离估算
改进：使用篮筐作为参考进行距离估算，更准确的投篮类型分类
"""
import math
from dataclasses import dataclass

import numpy as np
from scipy.optimize import curve_fit
from scipy.signal import savgol_filter

from models.tracking import BallTrack
from config.settings import config


@dataclass
class TrajectoryParams:
    """轨迹参数"""
    apex_x: float
    apex_y: float
    release_angle: float
    entry_angle: float
    apex_height: float
    fit_r_squared: float
    parabola_coefficients: tuple
    estimated_distance: float
    flight_time: float = 0.0      # 飞行时间（秒）
    shot_speed: float = 0.0       # 出手速度（m/s）
    arc_height: float = 0.0       # 弧线高度（米）


def parabola(x: np.ndarray, a: float, b: float, c: float) -> np.ndarray:
    return a * x**2 + b * x + c


class TrajectoryAnalyzer:
    """轨迹分析器 — 含运动学参数计算"""

    def __init__(self):
        self.ball_properties = config.ball
        self.court = config.court
        self._hoop_pixel_width: float = 0.0
        self._hoop_position: tuple[float, float] | None = None
        self._hoop_width_history: list[float] = []
        self._frame_width: int = config.trajectory.default_frame_width
        self._fps: float = 30.0

    def update_hoop_reference(self, hoop_position: tuple[float, float] | None, hoop_pixel_width: float):
        """更新篮筐参考信息（用于距离估算）"""
        self._hoop_position = hoop_position
        if hoop_pixel_width > 10:  # 忽略异常小的值
            self._hoop_pixel_width = hoop_pixel_width
            self._hoop_width_history.append(hoop_pixel_width)
            if len(self._hoop_width_history) > 60:
                self._hoop_width_history.pop(0)

    def set_frame_width(self, width: int):
        """设置视频帧宽度（用于焦距估算）"""
        self._frame_width = width

    def set_fps(self, fps: float):
        self._fps = fps

    def fit_trajectory(self, track: BallTrack) -> TrajectoryParams | None:
        """拟合篮球抛物线轨迹"""
        positions = track.positions
        if len(positions) < 3:
            return None

        x = positions[:, 0].astype(float)
        y = positions[:, 1].astype(float)

        # 平滑处理 - 使用更大的窗口
        window = min(len(y), 9)
        if window % 2 == 0:
            window -= 1
        if window >= 5:
            y_smooth = savgol_filter(y, window_length=window, polyorder=2)
        else:
            y_smooth = y

        apex_idx = np.argmin(y_smooth)
        apex_x = x[apex_idx]
        apex_y = y_smooth[apex_idx]

        try:
            popt, pcov = curve_fit(parabola, x, y_smooth, maxfev=5000)
            a, b, c = popt

            y_pred = parabola(x, a, b, c)
            ss_res = np.sum((y_smooth - y_pred) ** 2)
            ss_tot = np.sum((y_smooth - np.mean(y_smooth)) ** 2)
            r_squared = 1 - (ss_res / ss_tot) if ss_tot > 0 else 0

            # 使用配置的 R² 阈值
            if r_squared < config.shot.trajectory_r_squared_threshold:
                return None

            x_start = x[0]
            slope_start = 2 * a * x_start + b
            release_angle = math.degrees(math.atan(-slope_start))

            entry_angle = 0.0
            if apex_idx < len(x) - 1:
                x_end = x[-1]
                slope_end = 2 * a * x_end + b
                entry_angle = math.degrees(math.atan(-slope_end))

            estimated_distance = self._estimate_distance(track)

            # 运动学参数
            n_points = len(track.points)
            flight_time = n_points / self._fps if self._fps > 0 else 0.0

            # 出手速度：从抛物线初速度估算
            # v₀ = √(v₀ₓ² + v₀ᵧ²)
            # v₀ₓ 水平速度 ≈ 水平距离 / 飞行时间
            # v₀ᵧ 垂直速度 从出手角度推算
            shot_speed = 0.0
            if flight_time > 0 and estimated_distance > 0:
                v_horizontal = estimated_distance / flight_time
                release_rad = math.radians(abs(release_angle))
                if math.tan(release_rad) > 0:
                    v_vertical = v_horizontal * math.tan(release_rad)
                    shot_speed = math.sqrt(v_horizontal**2 + v_vertical**2)
                else:
                    shot_speed = v_horizontal

            # 弧线高度（像素→米）
            release_y = y_smooth[0]
            arc_height_px = abs(release_y - apex_y)
            # 用球像素大小做尺度转换
            ball_px = self._estimate_ball_pixel_size(track)
            if ball_px > 5:
                meters_per_px = self.ball_properties.real_diameter / ball_px
                arc_height = arc_height_px * meters_per_px
            else:
                arc_height = arc_height_px * config.trajectory.pixel_to_meter_fallback

            return TrajectoryParams(
                apex_x=apex_x,
                apex_y=apex_y,
                release_angle=release_angle,
                entry_angle=entry_angle,
                apex_height=apex_y,
                fit_r_squared=r_squared,
                parabola_coefficients=(a, b, c),
                estimated_distance=estimated_distance,
                flight_time=round(flight_time, 3),
                shot_speed=round(shot_speed, 2),
                arc_height=round(arc_height, 2),
            )

        except (RuntimeError, ValueError):
            return None

    def _estimate_distance(self, track: BallTrack) -> float:
        """估算投篮距离（米）

        优先使用球的像素大小（最可靠的参考）。
        其次使用水平像素距离 + 篮筐参考。
        """
        positions = track.positions
        if len(positions) < 2:
            return 0.0

        # 方法 1: 使用球的像素大小作为参考（最可靠）
        avg_ball_size = self._estimate_ball_pixel_size(track)
        if avg_ball_size > 5:
            focal_length = self._frame_width / (2 * math.tan(math.radians(config.trajectory.camera_fov_degrees)))
            distance_m = config.trajectory.ball_diameter_real * focal_length / avg_ball_size
            return max(0.5, min(distance_m, 15.0))

        # 方法 2: 水平像素距离 + 篮筐宽度参考
        if self._hoop_pixel_width > 0 and self._hoop_position is not None:
            dist = self._estimate_distance_from_hoop(track)
            if dist > 0:
                return dist

        # 方法 3: 使用水平像素位移 + 篮筐参考换算（比纯 fallback 更准）
        x_positions = positions[:, 0]
        pixel_displacement = abs(x_positions[-1] - x_positions[0])
        if self._hoop_pixel_width > 0:
            # 用篮筐宽度做尺度参考
            real_hoop_diameter = config.court.rim_diameter
            meters_per_pixel = real_hoop_diameter / self._hoop_pixel_width
            return max(0.5, min(pixel_displacement * meters_per_pixel, 10.0))
        return pixel_displacement * config.trajectory.pixel_to_meter_fallback

    def _estimate_distance_from_hoop(self, track: BallTrack) -> float:
        """估算投篮者到篮筐的距离（米）

        使用轨迹最高点（apex）的水平位置来估算射手的水平距离。
        球在飞行中垂直分量会误导距离计算，所以只用水平距离。
        """
        if len(self._hoop_width_history) < 3:
            return 0.0
        ref_width = float(np.median(self._hoop_width_history))
        if ref_width < 5 or self._hoop_position is None:
            return 0.0

        real_hoop_diameter = self.court.rim_diameter  # 0.45m
        meters_per_pixel = real_hoop_diameter / ref_width

        positions = track.positions
        xs = positions[:, 0].astype(float)
        ys = positions[:, 1].astype(float)

        # 用轨迹最高点（apex）的水平位置作为射手位置的估算
        # apex 是球在空中的最高点，水平位置最接近射手
        apex_idx = int(np.argmin(ys))
        shooter_x = float(xs[apex_idx])

        # 也参考轨迹起点（出手点），取两者中离篮筐更远的
        start_x = float(np.mean(xs[:max(1, len(xs) // 3)]))

        hoop_x = self._hoop_position[0]

        # 水平像素距离（取较大值，更接近射手真实位置）
        dx_apex = abs(shooter_x - hoop_x)
        dx_start = abs(start_x - hoop_x)
        pixel_dist = max(dx_apex, dx_start)

        # 转换为真实距离
        distance_m = pixel_dist * meters_per_pixel

        # 用篮筐宽度做尺度校正：篮筐在画面中越大，说明越近
        # 标准篮筐宽度 0.45m，如果在画面中占 ref_width 像素
        # 则焦距 = ref_width * 真实距离 / 0.45
        # 但这里我们已经有了 meters_per_pixel，直接用即可
        return max(0.5, min(distance_m, 10.0))

    def _estimate_ball_pixel_size(self, track: BallTrack) -> float:
        """估算篮球在画面中的像素直径

        优先使用检测框面积（ball_area），否则从轨迹点间距估算。
        返回球的估算像素直径。
        """
        if not track.points:
            return 0.0

        # 方法 1: 使用真实的检测框面积（取中位数，抗异常值）
        areas = [p.ball_area for p in track.points if p.ball_area > 0]
        if areas:
            avg_area = float(np.median(areas))
            diameter = math.sqrt(avg_area)
            return max(5.0, min(diameter, 100.0))

        # 方法 2: 从轨迹点间距估算（不准确，作为后备）
        positions = track.positions
        if len(positions) < 2:
            return 0.0

        distances = []
        for i in range(1, len(positions)):
            dx = positions[i][0] - positions[i-1][0]
            dy = positions[i][1] - positions[i-1][1]
            dist = math.sqrt(dx*dx + dy*dy)
            if dist > 0:
                distances.append(dist)

        if not distances:
            return 0.0

        # 使用中位数而非均值，更稳健
        avg_distance = float(np.median(distances))
        ball_size = avg_distance / 3.0
        return max(10.0, min(ball_size, 50.0))

    def classify_shot_type(
        self,
        trajectory: TrajectoryParams,
        player_positions: np.ndarray | None = None,
    ) -> str:
        """分类投篮类型 - 基于投篮者到篮筐的距离"""
        distance = trajectory.estimated_distance
        release_angle = trajectory.release_angle

        tc = config.trajectory
        if distance < tc.layup_max_distance:
            return "layup"
        elif distance < tc.mid_range_max_distance:
            if abs(release_angle) < 30:
                return "layup"
            return "mid_range"
        elif distance < tc.three_point_max_distance:
            return "three_point"
        else:
            return "three_point"
