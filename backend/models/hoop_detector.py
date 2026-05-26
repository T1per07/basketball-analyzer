"""
篮筐检测器 - 快速校准 + 稳定跟踪
改进：校准从25帧降到12帧，跟踪更稳定，支持场景切换重校准
"""
import cv2
import numpy as np


class HoopDetector:
    """篮筐检测器 - 快速校准 + 稳定跟踪"""

    HOOP_RANGES = [
        (np.array([160, 40, 80]), np.array([179, 255, 255])),  # 红色
        (np.array([0, 40, 80]), np.array([12, 255, 255])),     # 暗红
        (np.array([12, 40, 80]), np.array([25, 255, 255])),    # 橙红
    ]

    def __init__(self):
        self._kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
        self._calibration_buffer: list[tuple[int, int, int, int]] = []
        self._calibrated = False
        self._hoop_box: tuple[int, int, int, int] | None = None
        self._locked_box: tuple[int, int, int, int] | None = None
        self._frame_count = 0
        self._lost_count = 0
        self._max_lost = 30

    @property
    def is_calibrated(self) -> bool:
        return self._calibrated

    @property
    def hoop_position(self) -> tuple[int, int] | None:
        if self._hoop_box is None:
            return None
        x, y, w, h = self._hoop_box
        return (x + w // 2, y + h // 2)

    @property
    def hoop_box(self) -> tuple[int, int, int, int] | None:
        return self._hoop_box

    def detect(self, frame: np.ndarray) -> tuple[int, int] | None:
        self._frame_count += 1

        if not self._calibrated:
            return self._calibrate(frame)
        return self._track(frame)

    def _calibrate(self, frame: np.ndarray) -> tuple[int, int] | None:
        """快速校准：12帧完成"""
        candidates = self._find_color_candidates(frame)

        if candidates:
            # Prefer circular, compact candidates (rim) over large rectangles (backboard)
            def score(c):
                x, y, w, h, area = c[:5]
                aspect = w / h if h > 0 else 10
                # Penalize wide rectangles (backboard), reward near-square (rim)
                aspect_score = 1.0 / (1.0 + abs(aspect - 1.0) * 2)
                # Prefer smaller, more compact regions (rim ~50x50 vs backboard ~188x56)
                size_score = 1.0 / (1.0 + area / 2000)
                return aspect_score * size_score

            best = max(candidates, key=score)
            self._calibration_buffer.append((best[0], best[1], best[2], best[3]))

        # 12帧即可完成校准（原来25帧）
        if len(self._calibration_buffer) >= 12:
            self._finish_calibration()

        return self.hoop_position

    def _finish_calibration(self):
        if not self._calibration_buffer:
            return

        xs = [b[0] for b in self._calibration_buffer]
        ys = [b[1] for b in self._calibration_buffer]
        med_x, med_y = int(np.median(xs)), int(np.median(ys))

        filtered = [
            (x, y, w, h) for x, y, w, h in self._calibration_buffer
            if abs(x - med_x) < 100 and abs(y - med_y) < 80
        ]
        if not filtered:
            filtered = self._calibration_buffer

        avg_x = int(np.median([b[0] for b in filtered]))
        avg_y = int(np.median([b[1] for b in filtered]))
        avg_w = int(np.median([b[2] for b in filtered]))
        avg_h = int(np.median([b[3] for b in filtered]))

        # Reject too-small detections (likely false positives)
        if avg_w < 15 or avg_h < 8:
            return

        self._hoop_box = (avg_x, avg_y, avg_w, avg_h)
        self._locked_box = (avg_x, avg_y, avg_w, avg_h)
        self._calibrated = True

    def _track(self, frame: np.ndarray) -> tuple[int, int] | None:
        """校准后跟踪：锁定位置附近微调"""
        if self._locked_box is None:
            return self.hoop_position

        lx, ly, lw, lh = self._locked_box
        h, w = frame.shape[:2]

        # 搜索区域：锁定位置周围
        margin_x = int(lw * 1.0)
        margin_y = int(lh * 1.0)
        x1 = max(0, lx - margin_x)
        y1 = max(0, ly - margin_y)
        x2 = min(w, lx + lw + margin_x)
        y2 = min(h, ly + lh + margin_y)

        roi = frame[y1:y2, x1:x2]
        if roi.size == 0:
            return self.hoop_position

        candidates = self._find_color_candidates(roi, x1, y1)

        if candidates:
            def dist_to_locked(c):
                cx = c[0] + c[2] // 2
                cy = c[1] + c[3] // 2
                lc_x = lx + lw // 2
                lc_y = ly + lh // 2
                return (cx - lc_x) ** 2 + (cy - lc_y) ** 2

            # Prefer candidates close to locked position AND with good circularity
            def track_score(c):
                d = dist_to_locked(c)
                circ = c[5] if len(c) > 5 else 0.5
                aspect = c[2] / c[3] if c[3] > 0 else 10
                aspect_penalty = abs(aspect - 1.0)
                return d * (1 + aspect_penalty) / (0.1 + circ)

            best = min(candidates, key=track_score)
            bx, by, bw, bh = best[:4]
            dist = dist_to_locked(best)
            max_dist = (lw * 0.6) ** 2

            if dist < max_dist:
                # Skip tiny detections that would shrink the tracked hoop
                if bw < 12 or bh < 6:
                    self._lost_count += 1
                    return self.hoop_position
                alpha = 0.08
                new_x = int(alpha * bx + (1 - alpha) * lx)
                new_y = int(alpha * by + (1 - alpha) * ly)
                new_w = int(alpha * bw + (1 - alpha) * lw)
                new_h = int(alpha * bh + (1 - alpha) * lh)
                self._hoop_box = (new_x, new_y, new_w, new_h)
                self._locked_box = (new_x, new_y, new_w, new_h)
                self._lost_count = 0
            else:
                self._lost_count += 1
        else:
            self._lost_count += 1

        return self.hoop_position

    def _find_color_candidates(
        self, roi: np.ndarray, offset_x: int = 0, offset_y: int = 0
    ) -> list[tuple[int, int, int, int, float, float]]:
        """颜色检测找篮筐候选，返回 (x, y, w, h, area, circularity)"""
        hsv = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV)
        rh, rw = roi.shape[:2]

        combined_mask = np.zeros(hsv.shape[:2], dtype=np.uint8)
        for lower, upper in self.HOOP_RANGES:
            mask = cv2.inRange(hsv, lower, upper)
            combined_mask = cv2.bitwise_or(combined_mask, mask)

        combined_mask = cv2.morphologyEx(combined_mask, cv2.MORPH_OPEN, self._kernel)
        combined_mask = cv2.morphologyEx(combined_mask, cv2.MORPH_CLOSE, self._kernel)

        contours, _ = cv2.findContours(
            combined_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
        )

        min_area = rh * rw * 0.001
        max_area = rh * rw * 0.06

        candidates = []
        for cnt in contours:
            area = cv2.contourArea(cnt)
            if area < min_area or area > max_area:
                continue

            x, y, bw, bh = cv2.boundingRect(cnt)
            if bh == 0:
                continue

            aspect = bw / bh
            if aspect < 0.5 or aspect > 3.0:
                continue

            # 篮筐通常在画面上半部分
            if y + offset_y > rh * 0.75:
                continue

            # Compute circularity
            perimeter = cv2.arcLength(cnt, True)
            circularity = (4 * np.pi * area / (perimeter * perimeter)) if perimeter > 0 else 0

            candidates.append((x + offset_x, y + offset_y, bw, bh, area, circularity))

        return candidates

    def reset(self):
        self._calibration_buffer.clear()
        self._calibrated = False
        self._hoop_box = None
        self._locked_box = None
        self._frame_count = 0
        self._lost_count = 0
