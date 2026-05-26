"""ShotDetector 单元测试 — pytest 版"""
import math
import numpy as np
import pytest
from models.shot_detector import ShotDetector, ShotResult


class TestShotDetectorBasic:
    """基础功能测试"""

    def test_initial_state(self):
        sd = ShotDetector(fps=30.0)
        assert sd.total_shots == 0
        assert sd.total_made == 0
        assert sd.hoop_detected is False
        assert sd.shot_results == []

    def test_hoop_update(self):
        sd = ShotDetector(fps=30.0)
        sd.update_hoop(100, 50, 60, 30)
        assert sd.hoop_detected is True
        assert sd._locked_hoop is not None
        assert sd._locked_hoop[0] == 130.0  # cx = 100 + 60/2
        assert sd._locked_hoop[1] == 65.0   # cy = 50 + 30/2

    def test_hoop_rejects_tiny_box(self):
        sd = ShotDetector(fps=30.0)
        sd.update_hoop(100, 50, 5, 5)  # 小于 15
        assert sd.hoop_detected is False

    def test_reset(self):
        sd = ShotDetector(fps=30.0)
        sd.update_hoop(100, 50, 60, 30)
        sd.process_frame([(130, 60)], [100.0], [0.8], frame_index=1)
        sd.reset()
        assert sd.total_shots == 0
        assert sd.hoop_detected is False


class TestShotDetectorStateMachine:
    """UP/DOWN 状态机测试"""

    @pytest.fixture
    def sd_with_hoop(self):
        sd = ShotDetector(fps=30.0)
        # 篮筐中心 (300, 200)，宽 60，高 30
        sd.update_hoop(270, 185, 60, 30)
        return sd

    def test_basic_make(self, sd_with_hoop):
        sd = sd_with_hoop
        # 模拟投篮：球从上方经过篮筐到下方
        frames = [
            # 球在 UP zone（篮筐上方）
            (300, 120), (310, 130), (305, 140),
            # 球在篮筐附近
            (300, 190), (298, 200),
            # 球在 DOWN zone（篮筐下方）
            (300, 230), (305, 250),
        ]
        for i, (x, y) in enumerate(frames):
            sd.process_frame([(x, y)], [200.0], [0.8], frame_index=i * 3)

        # 应该检测到至少一次投篮
        assert sd.total_shots >= 1

    def test_cooldown_prevents_double_count(self, sd_with_hoop):
        sd = sd_with_hoop
        # 第一次投篮（frame 0-18）
        for i in range(7):
            y = 120 + i * 20
            sd.process_frame([(300, y)], [200.0], [0.8], frame_index=i * 3)

        shots_after_first = sd.total_shots
        assert shots_after_first >= 1, "第一次投篮应被检测到"

        # 冷却帧 = max(5, int(0.3*30)) = 9 帧
        # 第一次投篮发生在约 frame 18，冷却期到 frame 27
        # 第二次投篮在 frame 21-27 之间（冷却期内），应被忽略
        for i in range(4):
            y = 120 + i * 20
            sd.process_frame([(300, y)], [200.0], [0.8], frame_index=21 + i * 2)

        # 冷却期内第二次投篮不应被计数
        assert sd.total_shots == shots_after_first


class TestShotResult:
    """ShotResult 数据类测试"""

    def test_shot_result_fields(self):
        sr = ShotResult(made=True, frame=100, hoop_x=300, confidence=0.85)
        assert sr.made is True
        assert sr.frame == 100
        assert sr.hoop_x == 300
        assert sr.confidence == 0.85
        assert sr.has_apex is False
        assert sr.rim_overlap is False
