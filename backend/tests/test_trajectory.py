"""TrajectoryAnalyzer 单元测试 — pytest 版"""
import math
import numpy as np
import pytest
from models.tracking import BallTrack, TrackPoint
from models.trajectory import TrajectoryAnalyzer, TrajectoryParams


def make_track(points: list[tuple[int, float, float]], ball_area: float = 200.0) -> BallTrack:
    """辅助函数：创建测试用 BallTrack"""
    bt = BallTrack(track_id=0)
    for frame, x, y in points:
        bt.points.append(TrackPoint(
            frame_index=frame, x=x, y=y, confidence=0.8, ball_area=ball_area,
        ))
    return bt


class TestTrajectoryFitting:
    """抛物线拟合测试"""

    def test_perfect_parabola(self):
        ta = TrajectoryAnalyzer()
        # 构造抛物线 y = 0.5*(x-200)^2 + 50，开口向上，最低点在 (200, 50)
        # 篮球轨迹在屏幕坐标系中 y 轴向下，所以 min(y) 是最高点
        xs = np.linspace(100, 300, 15)
        ys = 0.02 * (xs - 200) ** 2 + 50
        track = make_track([(i, float(x), float(y)) for i, (x, y) in enumerate(zip(xs, ys))])

        result = ta.fit_trajectory(track)
        assert result is not None
        assert result.fit_r_squared > 0.95
        # apex 是 y 最小值处
        assert result.apex_y < 60

    def test_too_few_points_returns_none(self):
        ta = TrajectoryAnalyzer()
        track = make_track([(0, 100, 200), (1, 110, 190)])
        assert ta.fit_trajectory(track) is None

    def test_noisy_trajectory(self):
        ta = TrajectoryAnalyzer()
        np.random.seed(42)
        xs = np.linspace(100, 300, 15)
        ys = -0.01 * (xs - 200) ** 2 + 100 + np.random.normal(0, 3, len(xs))
        track = make_track([(i, float(x), float(y)) for i, (x, y) in enumerate(zip(xs, ys))])

        result = ta.fit_trajectory(track)
        # 即使有噪声，R² 也应足够高
        assert result is not None
        assert result.fit_r_squared > 0.7


class TestShotTypeClassification:
    """投篮类型分类测试"""

    def test_layup(self):
        ta = TrajectoryAnalyzer()
        traj = TrajectoryParams(
            apex_x=200, apex_y=100, release_angle=45,
            entry_angle=50, apex_height=100, fit_r_squared=0.9,
            parabola_coefficients=(-0.01, 2, -100), estimated_distance=1.0,
        )
        assert ta.classify_shot_type(traj) == "layup"

    def test_mid_range(self):
        ta = TrajectoryAnalyzer()
        traj = TrajectoryParams(
            apex_x=200, apex_y=100, release_angle=45,
            entry_angle=50, apex_height=100, fit_r_squared=0.9,
            parabola_coefficients=(-0.01, 2, -100), estimated_distance=3.0,
        )
        assert ta.classify_shot_type(traj) == "mid_range"

    def test_three_point(self):
        ta = TrajectoryAnalyzer()
        traj = TrajectoryParams(
            apex_x=200, apex_y=100, release_angle=45,
            entry_angle=50, apex_height=100, fit_r_squared=0.9,
            parabola_coefficients=(-0.01, 2, -100), estimated_distance=5.5,
        )
        assert ta.classify_shot_type(traj) == "three_point"

    def test_far_three_point(self):
        ta = TrajectoryAnalyzer()
        traj = TrajectoryParams(
            apex_x=200, apex_y=100, release_angle=45,
            entry_angle=50, apex_height=100, fit_r_squared=0.9,
            parabola_coefficients=(-0.01, 2, -100), estimated_distance=7.0,
        )
        assert ta.classify_shot_type(traj) == "three_point"


class TestDistanceEstimation:
    """距离估算测试"""

    def test_ball_pixel_size_method(self):
        ta = TrajectoryAnalyzer()
        # 创建一个有 ball_area 的轨迹
        track = make_track(
            [(0, 200, 300), (1, 210, 280), (2, 220, 260), (3, 230, 250)],
            ball_area=400.0,  # 20px 直径
        )
        distance = ta._estimate_distance(track)
        assert distance > 0.5
        assert distance < 15.0

    def test_empty_track_returns_zero(self):
        ta = TrajectoryAnalyzer()
        track = BallTrack(track_id=0)
        assert ta._estimate_distance(track) == 0.0
