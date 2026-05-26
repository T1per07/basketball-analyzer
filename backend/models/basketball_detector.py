"""
篮球专用检测器 - 使用专门训练的 YOLOv8 模型
同时检测 Basketball 和 Basketball Hoop，精度远高于通用模型
"""
import math
from pathlib import Path

import cv2
import numpy as np
import supervision as sv
from ultralytics import YOLO


CLASS_BASKETBALL = 0
CLASS_HOOP = 1
CLASS_NAMES = {0: "Basketball", 1: "Basketball Hoop"}


class BasketballDetector:
    """使用专门训练的 YOLOv8 模型检测篮球和篮筐"""

    def __init__(self, model_path: str = "models/best.pt"):
        self._model = None
        self._model_path = model_path
        self._hoop_history: list[tuple[int, int, int, int]] = []
        self._locked_hoop: tuple[int, int, int, int] | None = None

    @property
    def model(self) -> YOLO:
        if self._model is None:
            path = Path(self._model_path)
            if not path.exists():
                raise FileNotFoundError(f"Basketball model not found: {path}")
            self._model = YOLO(str(path))
        return self._model

    def detect(
        self,
        frame: np.ndarray,
        ball_conf: float = 0.25,
        hoop_conf: float = 0.4,
        scale: float = 1.0,
    ) -> tuple[sv.Detections, sv.Detections, tuple[int, int, int, int] | None]:
        """检测篮球和篮筐

        Returns:
            (ball_detections, hoop_detections, hoop_box)
        """
        results = self.model(frame, conf=ball_conf, verbose=False)[0]
        all_dets = sv.Detections.from_ultralytics(results)

        if all_dets is None or len(all_dets) == 0:
            return sv.Detections.empty(), sv.Detections.empty(), self._locked_hoop

        # 坐标缩放
        if scale != 1.0:
            all_dets.xyxy = all_dets.xyxy / scale

        # 分离篮球和篮筐
        ball_mask = all_dets.class_id == CLASS_BASKETBALL
        hoop_mask = all_dets.class_id == CLASS_HOOP

        ball_dets = all_dets[ball_mask] if np.any(ball_mask) else sv.Detections.empty()
        hoop_dets = all_dets[hoop_mask] if np.any(hoop_mask) else sv.Detections.empty()

        # 过滤低置信度篮筐
        if len(hoop_dets) > 0 and hoop_dets.confidence is not None:
            high_conf = hoop_dets.confidence >= hoop_conf
            if np.any(high_conf):
                hoop_dets = hoop_dets[high_conf]
            else:
                hoop_dets = sv.Detections.empty()

        # 更新篮筐锁定位置
        hoop_box = self._update_hoop_lock(hoop_dets)

        return ball_dets, hoop_dets, hoop_box

    def _update_hoop_lock(
        self, hoop_dets: sv.Detections
    ) -> tuple[int, int, int, int] | None:
        """稳定篮筐位置：高置信度锁定 + 跳变检测"""
        if len(hoop_dets) == 0:
            return self._locked_hoop

        # 取置信度最高的篮筐
        if hoop_dets.confidence is not None:
            best_idx = int(np.argmax(hoop_dets.confidence))
            best_conf = float(hoop_dets.confidence[best_idx])
        else:
            best_idx = 0
            best_conf = 0.0

        x1, y1, x2, y2 = hoop_dets.xyxy[best_idx]
        x, y, w, h = int(x1), int(y1), int(x2 - x1), int(y2 - y1)

        # 忽略太小或太靠边的检测
        if w < 20 or h < 20:
            return self._locked_hoop
        cx, cy = x + w // 2, y + h // 2
        if cx < 40 or cy < 20:
            return self._locked_hoop

        # 第一次锁定
        if self._locked_hoop is None:
            self._locked_hoop = (x, y, w, h)
            self._best_conf = best_conf
            return self._locked_hoop

        lx, ly, lw, lh = self._locked_hoop
        dist = math.sqrt((cx - lx - lw / 2) ** 2 + (cy - ly - lh / 2) ** 2)
        max_dist = max(lw, lh) * 1.5

        # 高置信度 + 距离合理 → 更新锁定
        if dist < max_dist:
            # 平滑更新
            alpha = 0.15
            nx = int(alpha * x + (1 - alpha) * lx)
            ny = int(alpha * y + (1 - alpha) * ly)
            nw = int(alpha * w + (1 - alpha) * lw)
            nh = int(alpha * h + (1 - alpha) * lh)
            self._locked_hoop = (nx, ny, nw, nh)
            self._best_conf = best_conf
        elif best_conf > 0.7 and best_conf > getattr(self, '_best_conf', 0) + 0.1:
            # 更高置信度的检测 → 重置锁定
            self._locked_hoop = (x, y, w, h)
            self._best_conf = best_conf

        return self._locked_hoop

    def reset(self):
        self._hoop_history.clear()
        self._locked_hoop = None
