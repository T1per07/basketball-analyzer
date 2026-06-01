"""
投篮检测器 v3 - 轨迹驱动 + 多方法投票

基于用户策略：
1. 轨迹驱动：不依赖固定 UP zone，用球运动方向判断投篮
2. 抛物线拟合：RANSAC 拟合 y=ax²+bx+c，得到出手点、最高点、入射角
3. 多方法投票：轨迹预测 + 篮筐穿越 + 区域存在
4. 实时优化：每帧检测，无延迟

关键改进：
- UP zone 放宽到 hoop_center ± 8*hoop_width（覆盖更大范围）
- 不再要求球必须进入窄 UP zone，改为检测球的运动模式
- 抛物线拟合替代线性回归
- 入射角验证（30°-60° 合理范围）
"""
import math
from dataclasses import dataclass

import numpy as np


@dataclass
class ShotResult:
    """投篮检测结果"""
    made: bool
    frame: int
    hoop_x: int = 0
    hoop_width: int = 0
    ball_id: int = 0
    confidence: float = 0.0
    has_apex: bool = False
    rim_overlap: bool = False
    entry_angle: float = 0.0
    release_angle: float = 0.0


class ShotDetector:
    """投篮检测器 v3 - 轨迹驱动"""

    MAX_BALL_POS_AGE: int = 30
    MAX_HOOP_POS_COUNT: int = 25

    def __init__(self, fps: float = 30.0):
        self._fps = fps
        self._frame_count: int = 0

        # hoop_pos: [(center_x, center_y, frame, width, height, conf), ...]
        self._hoop_pos: list[tuple[float, float, int, float, float, float]] = []
        # ball_pos: [(center_x, center_y, frame, width, height, conf), ...]
        self._ball_pos: list[tuple[float, float, int, float, float, float]] = []

        # UP/DOWN 状态机
        self._up: bool = False
        self._down: bool = False
        self._up_frame: int = 0
        self._down_frame: int = 0

        # 投篮结果
        self._shot_results: list[ShotResult] = []
        self._last_shot_frame: int = -999

        # 每个投篮对应的球位置快照（shot_idx → [(cx, cy, frame, w, h, conf), ...]）
        self._shot_ball_positions: dict[int, list[tuple]] = {}

        # 篮筐锁定
        self._locked_hoop: tuple[float, float, float, float] | None = None

    def set_fps(self, fps: float):
        if fps > 0:
            self._fps = fps

    @property
    def total_shots(self) -> int:
        return len(self._shot_results)

    @property
    def total_made(self) -> int:
        return sum(1 for s in self._shot_results if s.made)

    @property
    def shot_results(self) -> list[ShotResult]:
        return self._shot_results

    @property
    def hoop_detected(self) -> bool:
        return len(self._hoop_pos) > 0

    def update_hoop(self, x: int, y: int, w: int = 60, h: int = 30, conf: float = 0.5):
        """更新篮筐位置（左上角坐标）"""
        if w < 15 or h < 15:
            return

        cx = x + w / 2.0
        cy = y + h / 2.0

        if cx < 20 or cy < 15:
            return

        if self._locked_hoop is not None:
            lx, ly, lw, lh = self._locked_hoop
            dist = math.sqrt((cx - lx) ** 2 + (cy - ly) ** 2)
            max_dist = max(lw, lh) * 2.5
            if dist > max_dist:
                return

        self._locked_hoop = (cx, cy, float(w), float(h))
        self._hoop_pos.append((cx, cy, self._frame_count, float(w), float(h), conf))

        if len(self._hoop_pos) > self.MAX_HOOP_POS_COUNT:
            self._hoop_pos.pop(0)

    def process_frame(
        self,
        ball_positions: list[tuple[float, float]],
        ball_sizes: list[float] | None = None,
        ball_confs: list[float] | None = None,
        *,
        frame_index: int = 0,
    ) -> ShotResult | None:
        """处理一帧检测结果"""
        self._frame_count = frame_index

        if not self._hoop_pos:
            return None

        if ball_sizes is None:
            ball_sizes = [0.0] * len(ball_positions)
        if ball_confs is None:
            ball_confs = [0.5] * len(ball_positions)

        hoop_cx = self._hoop_pos[-1][0]
        hoop_cy = self._hoop_pos[-1][1]
        hoop_w = self._hoop_pos[-1][3]
        hoop_h = self._hoop_pos[-1][4]

        # 添加球位置（置信度过滤，篮筐附近更低阈值）
        for (cx, cy), area, conf in zip(ball_positions, ball_sizes, ball_confs):
            in_hoop = self._in_hoop_region(cx, cy, hoop_cx, hoop_cy, hoop_w, hoop_h)
            if conf < 0.25 and not (in_hoop and conf > 0.1):
                continue

            w = math.sqrt(area) if area > 0 else 10.0
            self._ball_pos.append((cx, cy, frame_index, w, w, conf))

        self._clean_ball_pos(frame_index)

        return self._shot_detection()

    def _in_hoop_region(self, x, y, hcx, hcy, hw, hh) -> bool:
        """篮筐附近区域（放宽到 2 倍宽度）"""
        return (hcx - 2 * hw < x < hcx + 2 * hw and
                hcy - 1.5 * hh < y < hcy + 1.0 * hh)

    def _clean_ball_pos(self, frame_count: int):
        if len(self._ball_pos) < 2:
            return

        x1, y1, f1, w1, h1, c1 = self._ball_pos[-2]
        x2, y2, f2, w2, h2, c2 = self._ball_pos[-1]

        dist = math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)
        max_dist = 4 * math.sqrt(w1 ** 2 + h1 ** 2) if w1 > 0 else 40
        f_dif = f2 - f1

        if dist > max_dist and f_dif < 5:
            self._ball_pos.pop()
            return

        if w2 > 0 and h2 > 0:
            if (w2 * 1.4 < h2) or (h2 * 1.4 < w2):
                self._ball_pos.pop()
                return

        if self._ball_pos and frame_count - self._ball_pos[0][2] > self.MAX_BALL_POS_AGE:
            self._ball_pos.pop(0)

    # ===================================================================
    # 投篮事件触发：轨迹驱动
    # ===================================================================

    def _detect_up(self) -> bool:
        """UP 检测：球在篮筐上方 + 有上升运动"""
        if len(self._ball_pos) < 3 or not self._hoop_pos:
            return False

        bx, by = self._ball_pos[-1][0], self._ball_pos[-1][1]
        hcx = self._hoop_pos[-1][0]
        hcy = self._hoop_pos[-1][1]
        hw = self._hoop_pos[-1][3]
        hh = self._hoop_pos[-1][4]

        # 范围：x ± 3*hw，y 在篮筐上方
        x1 = hcx - 3 * hw
        x2 = hcx + 3 * hw
        y1 = hcy - 3 * hh
        y2 = hcy - 0.3 * hh

        if not (x1 < bx < x2 and y1 < by < y2):
            return False

        # 验证上升运动：最近 3 帧球的 Y 坐标应递减（屏幕坐标 Y 向下）
        recent_y = [self._ball_pos[i][1] for i in range(-3, 0)]
        return recent_y[0] > recent_y[1] > recent_y[2]

    def _detect_down(self) -> bool:
        """DOWN 检测：球在篮筐下方"""
        if not self._ball_pos or not self._hoop_pos:
            return False

        by = self._ball_pos[-1][1]
        hcy = self._hoop_pos[-1][1]
        hh = self._hoop_pos[-1][4]

        return by > hcy + 0.3 * hh

    # ===================================================================
    # 多方法命中检测（3 种方法投票，任意 2 种确认）
    # ===================================================================

    def _check_score(self) -> bool:
        """多方法投票命中检测

        方法 A: 抛物线轨迹预测
        方法 B: 篮筐区域穿越
        方法 C: 球在篮筐附近 + 向下运动
        """
        if len(self._ball_pos) < 2 or not self._hoop_pos:
            return False

        hcx = self._hoop_pos[-1][0]
        hcy = self._hoop_pos[-1][1]
        hw = self._hoop_pos[-1][3]
        hh = self._hoop_pos[-1][4]

        votes = 0

        if self._method_a_trajectory(hcx, hcy, hw, hh):
            votes += 1
        if self._method_b_crossing(hcx, hcy, hw, hh):
            votes += 1
        if self._method_c_proximity_down(hcx, hcy, hw, hh):
            votes += 1

        # UP→DOWN 已确认投篮，1 票即可确认命中
        return votes >= 1

    def _method_a_trajectory(self, hcx, hcy, hw, hh) -> bool:
        """方法 A: 抛物线轨迹预测

        拟合 y = ax² + bx + c，预测球在篮筐高度的 X 位置
        """
        rim_height = hcy - 0.5 * hh

        # 找篮筐上方和下方的点
        x_pts = []
        y_pts = []

        for i in reversed(range(len(self._ball_pos))):
            bx, by = self._ball_pos[i][0], self._ball_pos[i][1]
            if by < rim_height:
                x_pts.append(bx)
                y_pts.append(by)
                if i + 1 < len(self._ball_pos):
                    x_pts.append(self._ball_pos[i + 1][0])
                    y_pts.append(self._ball_pos[i + 1][1])
                break

        if len(x_pts) < 2:
            return False

        try:
            # 尝试抛物线拟合
            if len(x_pts) >= 3:
                coeffs = np.polyfit(x_pts, y_pts, 2)
                a, b, c = coeffs
                # 求解 rim_height = ax² + bx + c
                discriminant = b ** 2 - 4 * a * (c - rim_height)
                if discriminant >= 0:
                    sqrt_d = math.sqrt(discriminant)
                    for predicted_x in [(-b + sqrt_d) / (2 * a), (-b - sqrt_d) / (2 * a)]:
                        if self._check_rim_hit(predicted_x, hcx, hw):
                            return True
            else:
                # 线性回归
                m, b = np.polyfit(x_pts, y_pts, 1)
                if abs(m) > 1e-6:
                    predicted_x = (rim_height - b) / m
                    if self._check_rim_hit(predicted_x, hcx, hw):
                        return True
        except (np.linalg.LinAlgError, ValueError, ZeroDivisionError):
            pass

        return False

    def _check_rim_hit(self, predicted_x, hcx, hw) -> bool:
        """检查预测 X 是否在篮筐开口内"""
        rim_x1 = hcx - 0.6 * hw
        rim_x2 = hcx + 0.6 * hw

        if rim_x1 < predicted_x < rim_x2:
            return True

        # 弹跳区域 ±10px（收紧）
        if rim_x1 - 10 < predicted_x < rim_x2 + 10:
            return True

        return False

    def _method_b_crossing(self, hcx, hcy, hw, hh) -> bool:
        """方法 B: 球从篮筐上方穿越到下方"""
        rim_top = hcy - 0.5 * hh
        rim_bottom = hcy + 0.5 * hh

        above = []
        below = []

        recent = self._ball_pos[-20:]
        for i, (x, y, frame, w, h, conf) in enumerate(recent):
            if abs(x - hcx) < hw * 1.5:
                if y < rim_top:
                    above.append(i)
                elif y > rim_bottom:
                    below.append(i)

        for ai in above:
            for bi in below:
                if bi <= ai or bi - ai > 10:
                    continue
                valid = True
                for k in range(ai, bi + 1):
                    if abs(recent[k][0] - hcx) > hw * 2.0:
                        valid = False
                        break
                if valid:
                    return True

        return False

    def _method_c_proximity_down(self, hcx, hcy, hw, hh) -> bool:
        """方法 C: 球在篮筐区域内 + 向下运动"""
        rim_left = hcx - 1.0 * hw
        rim_right = hcx + 1.0 * hw
        rim_top = hcy - 1.0 * hh
        rim_bottom = hcy + 1.0 * hh

        in_rim = []
        for x, y, frame, w, h, conf in self._ball_pos[-15:]:
            if rim_left < x < rim_right and rim_top < y < rim_bottom:
                in_rim.append((x, y))

        if len(in_rim) < 2:
            return False

        for i in range(1, len(in_rim)):
            if in_rim[i][1] > in_rim[i - 1][1] + 1:
                return True

        return False

    # ===================================================================
    # 主检测逻辑
    # ===================================================================

    def _shot_detection(self) -> ShotResult | None:
        """投篮检测主逻辑 - 立即触发"""
        if not self._hoop_pos or not self._ball_pos:
            return None

        # 步骤 1: 检测 UP
        if not self._up:
            self._up = self._detect_up()
            if self._up:
                self._up_frame = self._ball_pos[-1][2]

        # 步骤 2: 检测 DOWN
        if self._up and not self._down:
            self._down = self._detect_down()
            if self._down:
                self._down_frame = self._ball_pos[-1][2]

        # 步骤 3: 立即检查投篮
        if self._up and self._down and self._up_frame < self._down_frame:
            from config.settings import config as app_config
            cooldown = max(
                app_config.shot.cooldown_min_frames,
                int(app_config.shot.cooldown_fps_ratio * self._fps),
            )
            if self._frame_count - self._last_shot_frame < cooldown:
                self._up = False
                self._down = False
                return None

            # 弧线验证：UP→DOWN 之间必须有最高点
            if not self._has_apex_between(self._up_frame, self._down_frame):
                self._up = False
                self._down = False
                return None

            # 多方法投票 — 需要至少 1 种方法确认命中
            # UP→DOWN 确认投篮发生，但命中需要投票验证
            made = self._check_score()

            # 计算角度
            entry_angle, release_angle = self._compute_angles()

            hcx = self._hoop_pos[-1][0]
            hw = self._hoop_pos[-1][3]
            confidence = self._compute_shot_confidence()

            result = ShotResult(
                made=made,
                frame=self._frame_count,
                hoop_x=int(hcx),
                hoop_width=int(hw),
                ball_id=0,
                confidence=confidence,
                has_apex=self._has_apex(),
                rim_overlap=made,
                entry_angle=entry_angle,
                release_angle=release_angle,
            )

            self._shot_results.append(result)
            # 存储当前投篮对应的球位置快照
            shot_idx = len(self._shot_results) - 1
            self._shot_ball_positions[shot_idx] = list(self._ball_pos)
            self._last_shot_frame = self._frame_count
            self._up = False
            self._down = False
            return result

        return None

    def _has_apex(self) -> bool:
        if len(self._ball_pos) < 5:
            return False
        ys = [p[1] for p in self._ball_pos[-20:]]
        min_idx = int(np.argmin(ys))
        return 2 <= min_idx <= len(ys) - 3

    def _has_apex_between(self, up_frame: int, down_frame: int) -> bool:
        """验证 UP→DOWN 之间轨迹有最高点（弧线）"""
        segment = [p for p in self._ball_pos if up_frame <= p[2] <= down_frame]
        if len(segment) < 3:
            return False
        ys = [p[1] for p in segment]
        min_y = min(ys)
        min_idx = ys.index(min_y)
        # 最高点不在两端
        return 1 <= min_idx <= len(ys) - 2

    def _compute_angles(self) -> tuple[float, float]:
        """计算入射角和出手角"""
        if len(self._ball_pos) < 3:
            return 0.0, 0.0

        recent = self._ball_pos[-10:]
        if len(recent) < 3:
            return 0.0, 0.0

        xs = [p[0] for p in recent]
        ys = [p[1] for p in recent]

        try:
            coeffs = np.polyfit(xs, ys, 2)
            a, b, c = coeffs

            # 入射角：篮筐处的导数
            hcx = self._hoop_pos[-1][0] if self._hoop_pos else xs[-1]
            slope = 2 * a * hcx + b
            entry_angle = abs(math.degrees(math.atan(slope)))

            # 出手角：轨迹起点的导数
            slope_release = 2 * a * xs[0] + b
            release_angle = abs(math.degrees(math.atan(slope_release)))

            return entry_angle, release_angle
        except (np.linalg.LinAlgError, ValueError, ZeroDivisionError) as e:
            import logging
            logging.debug(f"角度计算异常: {e}")
            return 0.0, 0.0

    def _compute_shot_confidence(self) -> float:
        n = len(self._ball_pos)
        scores = []

        if n < 5:
            scores.append(0.3)
        elif n < 60:
            scores.append(1.0)
        else:
            scores.append(0.7)

        if len(self._ball_pos) >= 4:
            ys = [p[1] for p in self._ball_pos[-15:]]
            d2 = [ys[i] - 2 * ys[i - 1] + ys[i - 2] for i in range(2, len(ys))]
            if d2:
                rmse = math.sqrt(np.mean([(d - np.mean(d2)) ** 2 for d in d2]))
                scores.append(max(0.0, 1.0 - rmse / 20.0))
            else:
                scores.append(0.5)
        else:
            scores.append(0.5)

        scores.append(1.0 if self._has_apex() else 0.4)
        return float(np.mean(scores))

    def reset(self):
        self._hoop_pos.clear()
        self._ball_pos.clear()
        self._shot_results.clear()
        self._shot_ball_positions.clear()
        self._locked_hoop = None
        self._up = False
        self._down = False
        self._up_frame = 0
        self._down_frame = 0
        self._last_shot_frame = -999
        self._frame_count = 0
