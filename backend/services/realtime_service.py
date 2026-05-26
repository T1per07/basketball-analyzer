"""实时分析服务 - WebSocket 视频流处理"""
import asyncio
import json
import base64
import time
from dataclasses import dataclass

import cv2
import numpy as np

from services.shot_analyzer import ShotAnalyzer
from config.settings import config


class RealtimeAnalyzer:
    """实时视频流分析器"""

    def __init__(self):
        self.analyzer = ShotAnalyzer()
        self.config = config.realtime
        self._frame_count = 0
        self._last_stats_time = 0
        self._fps_counter = 0
        self._current_fps = 0

    def process_frame(self, frame: np.ndarray) -> dict:
        """
        处理单帧，返回检测结果和标注后的帧
        """
        self._frame_count += 1
        skip = config.detection.skip_frames

        # 跳帧处理
        if self._frame_count % skip == 0:
            detection = self.analyzer.process_frame(frame, self._frame_count)
            self._fps_counter += 1

            # 计算 FPS
            now = time.time()
            if now - self._last_stats_time >= 1.0:
                self._current_fps = self._fps_counter
                self._fps_counter = 0
                self._last_stats_time = now

            # 标注帧
            annotated = self._annotate_frame(frame, detection)

            # 获取统计
            stats = self.analyzer.get_current_stats()
            stats["fps"] = self._current_fps
            stats["frame"] = self._frame_count

            return {
                "frame": annotated,
                "stats": stats,
                "detections": {
                    "balls": len(detection.ball_detections),
                    "players": len(detection.player_detections),
                },
            }

        return {
            "frame": frame,
            "stats": {"fps": self._current_fps, "frame": self._frame_count},
            "detections": {"balls": 0, "players": 0},
        }

    def _annotate_frame(self, frame: np.ndarray, detection) -> np.ndarray:
        """标注帧"""
        annotated = frame.copy()

        # 绘制篮球检测框
        if len(detection.ball_detections) > 0:
            for bbox in detection.ball_detections.xyxy:
                x1, y1, x2, y2 = map(int, bbox)
                cv2.rectangle(annotated, (x1, y1), (x2, y2), (0, 165, 255), 2)
                cv2.putText(annotated, "Ball", (x1, y1 - 5),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 165, 255), 2)

        # 绘制球员检测框
        if len(detection.player_detections) > 0:
            for bbox in detection.player_detections.xyxy:
                x1, y1, x2, y2 = map(int, bbox)
                cv2.rectangle(annotated, (x1, y1), (x2, y2), (255, 0, 0), 1)

        # 绘制轨迹
        active_tracks = self.analyzer.ball_tracker.get_active_tracks()
        for track in active_tracks:
            points = track.positions
            if len(points) > 1:
                for i in range(1, len(points)):
                    pt1 = (int(points[i-1][0]), int(points[i-1][1]))
                    pt2 = (int(points[i][0]), int(points[i][1]))
                    cv2.line(annotated, pt1, pt2, (0, 255, 0), 2)

        return annotated

    def encode_frame(self, frame: np.ndarray) -> str:
        """编码帧为 base64 JPEG"""
        # 缩放以减少传输大小
        h, w = frame.shape[:2]
        if w > self.config.max_width:
            scale = self.config.max_width / w
            frame = cv2.resize(frame, (self.config.max_width, int(h * scale)))

        _, buffer = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, self.config.jpeg_quality])
        return base64.b64encode(buffer).decode('utf-8')

    def reset(self):
        """重置分析器"""
        self.analyzer = ShotAnalyzer()
        self._frame_count = 0
        self._fps_counter = 0
        self._current_fps = 0
