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
        # 模拟投篮：球从下方上升到篮筐上方，再下降穿过篮筐
        # 篮筐中心 (300, 200)，UP zone: y 在 110~191
        frames = [
            # 球上升阶段（Y 递减 = 向上）
            (300, 280), (300, 260), (300, 240),
            (300, 220), (300, 200),
            # 球在 UP zone（篮筐上方，Y 继续递减）
            (300, 170), (300, 150), (300, 130),
            # 球到达最高点后下降
            (300, 120), (300, 125),
            # 球下降穿过篮筐区域
            (300, 160), (300, 190),
            # 球在 DOWN zone（篮筐下方）
            (300, 220), (300, 240),
        ]
        for i, (x, y) in enumerate(frames):
            sd.process_frame([(x, y)], [200.0], [0.8], frame_index=i * 3)

        # 应该检测到至少一次投篮
        assert sd.total_shots >= 1

    def test_cooldown_prevents_double_count(self, sd_with_hoop):
        sd = sd_with_hoop
        # 第一次投篮
        shot_frames = [
            (300, 280), (300, 260), (300, 240),
            (300, 220), (300, 200),
            (300, 170), (300, 150), (300, 130),
            (300, 120), (300, 125),
            (300, 160), (300, 190),
            (300, 220), (300, 240),
        ]
        for i, (x, y) in enumerate(shot_frames):
            sd.process_frame([(x, y)], [200.0], [0.8], frame_index=i * 3)

        assert sd.total_shots >= 1, "第一次投篮应被检测到"
        first_shot_frame = sd._last_shot_frame

        # 模拟冷却期内的投篮尝试：手动设置 UP+DOWN 状态
        # 冷却帧 = max(8, int(0.3*30)) = 9
        cooldown_end = first_shot_frame + 9
        # 在冷却期内喂几帧球位置使状态机进入 UP→DOWN
        for i in range(5):
            sd.process_frame([(300, 150)], [200.0], [0.8],
                             frame_index=first_shot_frame + 2 + i)
        sd._up = True
        sd._up_frame = first_shot_frame + 3
        sd._down = True
        sd._down_frame = first_shot_frame + 5
        # 触发检测 — 应被冷却期拦截
        sd.process_frame([(300, 250)], [200.0], [0.8],
                         frame_index=first_shot_frame + 6)

        assert sd.total_shots == 1, "冷却期内不应检测到第二次投篮"


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
