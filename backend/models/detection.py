"""
目标检测模型 - 专用篮球模型 + YOLO + 颜色检测 + 运动检测 多通道融合
v3: 新增专用篮球检测模型通道（best.pt），同时检测篮球和篮筐
"""
import numpy as np
import cv2
from pathlib import Path
from dataclasses import dataclass

import supervision as sv

from config.settings import config, DetectionConfig, BallProperties
from models.hoop_detector import HoopDetector


COCO_SPORTS_BALL_ID = 32
COCO_PERSON_ID = 0


@dataclass
class DetectionResult:
    """单帧检测结果"""
    ball_detections: sv.Detections
    player_detections: sv.Detections
    hoop_detections: sv.Detections
    hoop_position: tuple[int, int] | None
    hoop_box: tuple[int, int, int, int] | None
    frame_index: int


class ColorBallDetector:
    """基于颜色的篮球检测器"""

    def __init__(self, ball_config: BallProperties | None = None):
        self.ball_config = ball_config or config.ball
        self._kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
        self._ranges = [
            # 橙色篮球主范围（高饱和度）
            (np.array([5, 100, 100]), np.array([22, 255, 255])),
            # 偏红橙（暖光下）
            (np.array([0, 120, 120]), np.array([8, 255, 255])),
        ]

    def detect(self, frame: np.ndarray, scale: float = 1.0) -> sv.Detections:
        """使用多组 HSV 范围检测篮球（内部缩小帧加速）"""
        h, w = frame.shape[:2]

        # 缩小帧加速处理
        target_w = config.detection.color_detect_target_width
        if w > target_w:
            internal_scale = target_w / w
            small = cv2.resize(frame, (target_w, int(h * internal_scale)))
        else:
            internal_scale = 1.0
            small = frame

        hsv = cv2.cvtColor(small, cv2.COLOR_BGR2HSV)
        sh, sw = small.shape[:2]

        min_area = max(50, int(sw * sh * 0.0005))
        max_area = int(sw * sh * 0.015)

        combined_mask = np.zeros(hsv.shape[:2], dtype=np.uint8)
        for lower, upper in self._ranges:
            mask = cv2.inRange(hsv, lower, upper)
            combined_mask = cv2.bitwise_or(combined_mask, mask)

        combined_mask = cv2.morphologyEx(combined_mask, cv2.MORPH_OPEN, self._kernel)
        combined_mask = cv2.morphologyEx(combined_mask, cv2.MORPH_CLOSE, self._kernel)

        contours, _ = cv2.findContours(
            combined_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
        )

        boxes = []
        confidences = []

        for cnt in contours:
            area = cv2.contourArea(cnt)
            if area < min_area or area > max_area:
                continue

            x, y, bw, bh = cv2.boundingRect(cnt)
            aspect = bw / bh if bh > 0 else 0
            if aspect < 0.5 or aspect > 2.0:  # 收紧纵横比
                continue

            perimeter = cv2.arcLength(cnt, True)
            circularity = 4 * np.pi * area / (perimeter * perimeter) if perimeter > 0 else 0
            if circularity < 0.4:  # 提高圆度要求
                continue

            conf = min(0.3 + circularity * 0.5 + (area / max_area) * 0.1, 0.8)

            # 转换回原始坐标
            if internal_scale != 1.0:
                x, y, bw, bh = int(x / internal_scale), int(y / internal_scale), int(bw / internal_scale), int(bh / internal_scale)
            if scale != 1.0:
                x, y, bw, bh = int(x / scale), int(y / scale), int(bw / scale), int(bh / scale)

            boxes.append([x, y, x + bw, y + bh])
            confidences.append(conf)

        if not boxes:
            return sv.Detections.empty()

        return sv.Detections(
            xyxy=np.array(boxes, dtype=np.float32),
            confidence=np.array(confidences, dtype=np.float32),
            class_id=np.full(len(boxes), COCO_SPORTS_BALL_ID, dtype=int),
        )


class MotionBallDetector:
    """基于帧差法的运动物体检测器"""

    def __init__(self):
        self._prev_gray = None
        self._kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))

    def detect(self, frame: np.ndarray, scale: float = 1.0) -> sv.Detections:
        """通过帧差法检测运动物体（内部缩小帧加速）"""
        h, w = frame.shape[:2]

        # 缩小帧加速
        target_w = config.detection.color_detect_target_width
        if w > target_w:
            internal_scale = target_w / w
            small = cv2.resize(frame, (target_w, int(h * internal_scale)))
        else:
            internal_scale = 1.0
            small = frame

        gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
        gray = cv2.GaussianBlur(gray, (9, 9), 0)

        if self._prev_gray is None:
            self._prev_gray = gray
            return sv.Detections.empty()

        frame_delta = cv2.absdiff(self._prev_gray, gray)
        thresh = cv2.threshold(
            frame_delta, config.detection.motion_threshold, 255, cv2.THRESH_BINARY
        )[1]
        thresh = cv2.morphologyEx(thresh, cv2.MORPH_OPEN, self._kernel)
        thresh = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, self._kernel)

        self._prev_gray = gray

        contours, _ = cv2.findContours(
            thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
        )

        sh, sw = small.shape[:2]
        min_area = max(30, int(sw * sh * 0.0002))
        max_area = int(sw * sh * 0.015)

        boxes = []
        confidences = []

        for cnt in contours:
            area = cv2.contourArea(cnt)
            if area < min_area or area > max_area:
                continue

            x, y, bw, bh = cv2.boundingRect(cnt)
            aspect = bw / bh if bh > 0 else 0
            if aspect < 0.4 or aspect > 2.5:  # 收紧纵横比
                continue

            conf = 0.25  # 降低运动检测置信度

            # 转换回原始坐标
            if internal_scale != 1.0:
                x, y, bw, bh = int(x / internal_scale), int(y / internal_scale), int(bw / internal_scale), int(bh / internal_scale)
            if scale != 1.0:
                x, y, bw, bh = int(x / scale), int(y / scale), int(bw / scale), int(bh / scale)

            boxes.append([x, y, x + bw, y + bh])
            confidences.append(conf)

        if not boxes:
            return sv.Detections.empty()

        return sv.Detections(
            xyxy=np.array(boxes, dtype=np.float32),
            confidence=np.array(confidences, dtype=np.float32),
            class_id=np.full(len(boxes), COCO_SPORTS_BALL_ID, dtype=int),
        )

    def reset(self):
        self._prev_gray = None


class CombinedDetector:
    """多通道组合检测器 - 专用篮球模型 + YOLO + 颜色 + 运动"""

    def __init__(self, detection_config: DetectionConfig | None = None):
        self.config = detection_config or config.detection
        self._model = None
        self._color_detector = ColorBallDetector()
        self._motion_detector = MotionBallDetector()
        self._hoop_detector = HoopDetector()
        self._basketball_detector = None

    @property
    def model(self):
        if self._model is None:
            from ultralytics import YOLO
            model_path = self.config.custom_ball_model_path
            if model_path and Path(model_path).exists():
                self._model = YOLO(model_path)
            else:
                base_name = self.config.ball_model_name.replace('.pt', '')
                onnx_path = Path(f"{base_name}.onnx")
                if onnx_path.exists():
                    self._model = YOLO(str(onnx_path))
                else:
                    self._model = YOLO(self.config.ball_model_name)
        return self._model

    @property
    def basketball_detector(self):
        if self._basketball_detector is None:
            from models.basketball_detector import BasketballDetector
            self._basketball_detector = BasketballDetector(
                model_path=self.config.basketball_model_path
            )
        return self._basketball_detector

    def _resize_frame(self, frame: np.ndarray) -> tuple[np.ndarray, float]:
        h, w = frame.shape[:2]
        target_w = self.config.input_width
        if w <= target_w:
            return frame, 1.0
        scale = target_w / w
        new_h = int(h * scale)
        resized = cv2.resize(frame, (target_w, new_h))
        return resized, scale

    @property
    def hoop_position(self) -> tuple[int, int] | None:
        return self._hoop_detector.hoop_position

    @property
    def hoop_box(self) -> tuple[int, int, int, int] | None:
        return self._hoop_detector.hoop_box

    def detect(self, frame: np.ndarray, frame_index: int = 0) -> DetectionResult:
        """检测：专用篮球模型（球+篮筐）+ 通用 YOLO（仅球员）"""
        small_frame, scale = self._resize_frame(frame)

        player_detections = sv.Detections.empty()
        ball_detections = sv.Detections.empty()
        hoop_box = None
        hoop_position = None

        # === 专用篮球模型：检测球 + 篮筐（主力） ===
        if self.config.use_basketball_model:
            try:
                bb_balls, bb_hoops, bb_hoop_box = self.basketball_detector.detect(
                    frame,
                    ball_conf=self.config.ball_confidence_threshold,
                    hoop_conf=self.config.hoop_confidence_threshold,
                )
                if len(bb_balls) > 0:
                    ball_detections = bb_balls
                if bb_hoop_box is not None:
                    hoop_box = bb_hoop_box
                    hoop_position = (bb_hoop_box[0] + bb_hoop_box[2] // 2,
                                     bb_hoop_box[1] + bb_hoop_box[3] // 2)
            except Exception as e:
                import logging
                logging.warning(f"篮球模型检测异常: {e}")

        # === 通用 YOLO：仅用于球员检测 ===
        yolo_interval = getattr(self.config, 'yolo_interval', 3)
        run_yolo = (frame_index % yolo_interval == 0) and not getattr(self.config, 'disable_yolo', False)

        if run_yolo:
            results = self.model(
                small_frame,
                conf=self.config.player_confidence_threshold,
                verbose=False,
                half=self.config.use_half,
            )[0]

            all_detections = sv.Detections.from_ultralytics(results)
            if all_detections is None:
                all_detections = sv.Detections.empty()

            if scale != 1.0 and len(all_detections) > 0:
                all_detections.xyxy = all_detections.xyxy / scale

            if len(all_detections) > 0 and all_detections.class_id is not None:
                person_mask = all_detections.class_id == COCO_PERSON_ID
                if np.any(person_mask):
                    player_detections = all_detections[person_mask]

            self._last_player_detections = player_detections
        else:
            player_detections = getattr(self, '_last_player_detections', sv.Detections.empty())

        # NMS 去重
        if len(ball_detections) > 1:
            ball_detections = ball_detections.with_nms(threshold=config.detection.nms_threshold)

        # 限制每帧最大球数
        max_balls = config.detection.max_balls_per_frame
        if len(ball_detections) > max_balls and ball_detections.confidence is not None:
            top_indices = np.argsort(ball_detections.confidence)[-max_balls:]
            ball_detections = ball_detections[top_indices]

        # 篮筐降级：仅当专用模型从未检测到篮筐时才用颜色检测
        if hoop_box is None and not self.basketball_detector._locked_hoop:
            if frame_index % 3 == 0:
                self._hoop_detector.detect(frame)
            hoop_position = self._hoop_detector.hoop_position
            hoop_box = self._hoop_detector.hoop_box

        return DetectionResult(
            ball_detections=ball_detections,
            player_detections=player_detections,
            hoop_detections=sv.Detections.empty(),
            hoop_position=hoop_position,
            hoop_box=hoop_box,
            frame_index=frame_index,
        )

    def _filter_balls_near_players(
        self,
        balls: sv.Detections,
        players: sv.Detections,
        frame_shape: tuple,
    ) -> sv.Detections:
        """过滤球检测：保留球员附近、篮筐附近、或高置信度的球"""
        if len(balls) == 0:
            return balls

        fh, fw = frame_shape
        hoop_pos = self._hoop_detector.hoop_position

        keep_indices = []

        for i in range(len(balls)):
            bx = (balls.xyxy[i][0] + balls.xyxy[i][2]) / 2
            by = (balls.xyxy[i][1] + balls.xyxy[i][3]) / 2
            conf = balls.confidence[i] if balls.confidence is not None else 0.5

            # 条件 1：高置信度 YOLO 检测直接保留
            if conf >= 0.35:
                keep_indices.append(i)
                continue

            # 条件 2：在球员附近
            near_player = False
            for j in range(len(players)):
                px1, py1, px2, py2 = players.xyxy[j]
                ph = py2 - py1
                margin = ph * 0.5
                if (px1 - margin < bx < px2 + margin and
                    py1 - margin < by < py2 + margin):
                    near_player = True
                    break

            if near_player:
                keep_indices.append(i)
                continue

            # 条件 3：在篮筐附近（投篮时球在篮筐上方）
            if hoop_pos:
                hx, hy = hoop_pos
                hoop_w = self._hoop_detector.hoop_box[2] if self._hoop_detector.hoop_box else 100
                hoop_dist = ((bx - hx) ** 2 + (by - hy) ** 2) ** 0.5
                if hoop_dist < hoop_w * 4:
                    keep_indices.append(i)
                    continue

            # 条件 4：在画面大部分区域且有一定置信度
            if by < fh * 0.75 and conf >= 0.15:
                keep_indices.append(i)

        if keep_indices:
            return balls[keep_indices]
        return sv.Detections.empty()

    def reset(self):
        self._motion_detector.reset()
        self._hoop_detector.reset()
        if self._basketball_detector is not None:
            self._basketball_detector.reset()
