"""优化的检测器 - ONNX Runtime 直接推理（60fps+ 优化版）"""
import numpy as np
import cv2
from pathlib import Path

import supervision as sv

from config.settings import config, DetectionConfig


COCO_SPORTS_BALL_ID = 32
COCO_PERSON_ID = 0


def _try_gpu_providers() -> list[str]:
    """按优先级尝试 GPU 加速：CUDA > DirectML > CPU"""
    try:
        import onnxruntime as ort
        available = ort.get_available_providers()
        for p in ['CUDAExecutionProvider', 'DmlExecutionProvider']:
            if p in available:
                return [p, 'CPUExecutionProvider']
    except Exception:
        pass
    return ['CPUExecutionProvider']


class ONNXDetector:
    """高性能 ONNX 检测器 — GPU 加速 + 预分配缓冲区 + 自动输入尺寸"""

    def __init__(self, model_path: str, input_size: int | None = None):
        import onnxruntime as ort

        providers = _try_gpu_providers()
        opts = ort.SessionOptions()
        opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        opts.intra_op_num_threads = 8
        opts.inter_op_num_threads = 1
        self.session = ort.InferenceSession(
            model_path, sess_options=opts, providers=providers,
        )
        self.input_name = self.session.get_inputs()[0].name
        self.output_names = [o.name for o in self.session.get_outputs()]

        # 自动检测模型期望的输入尺寸
        if input_size is None:
            shape = self.session.get_inputs()[0].shape
            # shape 通常是 [batch, channels, H, W]
            input_size = shape[-1] if isinstance(shape[-1], int) and shape[-1] > 0 else 416
        self.input_size = input_size

        # 预分配输入缓冲区（避免每帧 malloc）
        chw = (1, 3, self.input_size, self.input_size)
        self._blob = np.empty(chw, dtype=np.float32)
        self._resized = np.empty((self.input_size, self.input_size, 3), dtype=np.uint8)

    def preprocess(self, frame: np.ndarray) -> np.ndarray:
        """预分配缓冲区预处理 — resize + BGR→RGB + 归一化"""
        cv2.resize(frame, (self.input_size, self.input_size), dst=self._resized)
        # BGR→RGB + HWC→CHW + /255 一步到位
        blob = self._resized[:, :, ::-1].transpose(2, 0, 1).astype(np.float32) * (1.0 / 255.0)
        self._blob[0] = blob
        return self._blob

    def postprocess(
        self,
        output: np.ndarray,
        conf_threshold: float = 0.25,
        nms_threshold: float = 0.45,
        original_shape: tuple = None,
    ) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        """优化后处理 — 向量化 xywh→xyxy + 快速 NMS"""
        # output shape: [1, 6, N] → [N, 6]
        detections = output[0].T

        # 置信度过滤
        mask = detections[:, 4] >= conf_threshold
        detections = detections[mask]

        if len(detections) == 0:
            return np.array([]), np.array([]), np.array([])

        # 向量化 xywh → xyxy
        xc, yc = detections[:, 0], detections[:, 1]
        hw, hh = detections[:, 2] / 2, detections[:, 3] / 2
        boxes_xyxy = np.empty_like(detections[:, :4])
        boxes_xyxy[:, 0] = xc - hw
        boxes_xyxy[:, 1] = yc - hh
        boxes_xyxy[:, 2] = xc + hw
        boxes_xyxy[:, 3] = yc + hh

        confidences = detections[:, 4]
        class_ids = detections[:, 5].astype(np.int32)

        # NMS（用 cv2.dnn 加速版）
        indices = cv2.dnn.NMSBoxes(
            boxes_xyxy.tolist(), confidences.tolist(),
            conf_threshold, nms_threshold,
        )

        if len(indices) > 0:
            idx = indices.flatten()
            return boxes_xyxy[idx], confidences[idx], class_ids[idx]

        return np.array([]), np.array([]), np.array([])

    def detect(
        self,
        frame: np.ndarray,
        conf_threshold: float = 0.25,
    ) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        """单帧检测（预分配缓冲区版）"""
        blob = self.preprocess(frame)
        outputs = self.session.run(self.output_names, {self.input_name: blob})
        return self.postprocess(outputs[0], conf_threshold)


class OptimizedCombinedDetector:
    """高性能组合检测器 — 320 输入 + 降频球员/篮筐检测"""

    def __init__(self, detection_config: DetectionConfig | None = None):
        self.config = detection_config or config.detection
        self._ball_detector = None
        self._player_detector = None
        self._hoop_detector = None
        self._init_detectors()

    def _init_detectors(self):
        """初始化检测器 — 自动检测模型输入尺寸"""
        ball_model_path = Path(__file__).parent / "best.onnx"
        if ball_model_path.exists():
            self._ball_detector = ONNXDetector(str(ball_model_path))
            print(f"[OK] 篮球模型已加载 ({self._ball_detector.input_size}): {ball_model_path}")
        else:
            print(f"[!!] 篮球模型不存在: {ball_model_path}")

        project_root = Path(__file__).parent.parent.parent
        yolo_path = project_root / "yolo11n.onnx"
        if not yolo_path.exists():
            yolo_path = Path(__file__).parent / "yolo11n.onnx"
        if yolo_path.exists():
            self._player_detector = ONNXDetector(str(yolo_path))
            print(f"[OK] YOLO 模型已加载 ({self._player_detector.input_size}): {yolo_path}")
        else:
            print(f"[!!] YOLO 模型不存在: {yolo_path}")

        from models.hoop_detector import HoopDetector
        self._hoop_detector = HoopDetector()

    def detect(self, frame: np.ndarray, frame_index: int = 0) -> 'DetectionResult':
        """优化检测流程 — 球每帧，球员/篮筐降频"""
        from models.detection import DetectionResult

        ball_detections = sv.Detections.empty()
        player_detections = sv.Detections.empty()
        hoop_box = None
        hoop_position = None

        # 篮球模型（每帧）
        if self._ball_detector and self.config.use_basketball_model:
            try:
                boxes, confs, class_ids = self._ball_detector.detect(
                    frame, conf_threshold=self.config.ball_confidence_threshold,
                )
                if len(boxes) > 0:
                    ball_detections = sv.Detections(
                        xyxy=boxes.astype(np.float32),
                        confidence=confs,
                        class_id=np.full(len(boxes), COCO_SPORTS_BALL_ID, dtype=int),
                    )
                    hoop_mask = class_ids == 1
                    if np.any(hoop_mask):
                        hoop_boxes = boxes[hoop_mask]
                        if len(hoop_boxes) > 0:
                            best_idx = np.argmax(confs[hoop_mask])
                            hb = hoop_boxes[best_idx]
                            hoop_box = (int(hb[0]), int(hb[1]), int(hb[2]-hb[0]), int(hb[3]-hb[1]))
                            hoop_position = (int((hb[0]+hb[2])/2), int((hb[1]+hb[3])/2))
            except Exception as e:
                import logging
                logging.warning(f"篮球模型检测异常: {e}")

        # 球员检测（每 5 帧，非关键路径）
        if self._player_detector and frame_index % 5 == 0:
            try:
                boxes, confs, class_ids = self._player_detector.detect(
                    frame, conf_threshold=self.config.player_confidence_threshold,
                )
                if len(boxes) > 0:
                    person_mask = class_ids == COCO_PERSON_ID
                    if np.any(person_mask):
                        player_detections = sv.Detections(
                            xyxy=boxes[person_mask].astype(np.float32),
                            confidence=confs[person_mask],
                            class_id=np.full(np.sum(person_mask), COCO_PERSON_ID, dtype=int),
                        )
            except Exception as e:
                import logging
                logging.warning(f"YOLO 检测异常: {e}")

        # 篮筐降级检测 — 校准前每帧，校准后每 10 帧
        if hoop_box is None:
            run_hoop = (not self._hoop_detector.is_calibrated) or (frame_index % 10 == 0)
            if run_hoop:
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

    def reset(self):
        if self._hoop_detector:
            self._hoop_detector.reset()
