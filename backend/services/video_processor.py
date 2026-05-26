"""视频处理服务 - 使用 Supervision Annotator 标注"""
import time
from pathlib import Path
from dataclasses import dataclass

import cv2
import numpy as np
import supervision as sv

from services.shot_analyzer import ShotAnalyzer, AnalysisResult
from config.settings import config


@dataclass
class VideoInfo:
    path: str
    width: int
    height: int
    fps: float
    total_frames: int
    duration: float


# Supervision 颜色
CYAN = sv.Color(0, 240, 255)
ORANGE = sv.Color(255, 107, 43)
GREEN = sv.Color(57, 255, 20)
PINK = sv.Color(255, 45, 123)
WHITE = sv.Color(255, 255, 255)
GOLD = sv.Color(255, 215, 0)
RED = sv.Color(255, 60, 60)


class VideoProcessor:
    """视频处理器 - Supervision 标注版"""

    def __init__(self, fps: float = 30.0):
        self.analyzer = ShotAnalyzer(fps=fps)

        # Annotators
        self._trace_annotator = sv.TraceAnnotator(
            color=ORANGE, trace_length=40, thickness=3, smooth=True
        )
        self._circle_annotator = sv.CircleAnnotator(
            color=CYAN, thickness=3
        )
        self._box_annotator = sv.BoxAnnotator(
            color=GREEN, thickness=2
        )
        self._label_annotator = sv.LabelAnnotator(
            color=CYAN, text_color=sv.Color.BLACK, text_scale=0.5, text_thickness=1
        )
        self._round_box_annotator = sv.RoundBoxAnnotator(
            color=GREEN, thickness=2, roundness=0.3
        )

        self._shot_flash_frames = 0
        self._shot_flash_made = False
        self._shot_counter_snapshot = 0

    def get_video_info(self, video_path: str) -> VideoInfo:
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            raise ValueError(f"Cannot open video: {video_path}")

        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fps = cap.get(cv2.CAP_PROP_FPS)
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        duration = total_frames / fps if fps > 0 else 0
        cap.release()

        return VideoInfo(
            path=video_path, width=width, height=height,
            fps=fps, total_frames=total_frames, duration=duration,
        )

    def analyze_video(
        self,
        video_path: str,
        progress_callback=None,
    ) -> AnalysisResult:
        video_info = self.get_video_info(video_path)
        self.analyzer.trajectory_analyzer.set_frame_width(video_info.width)
        self.analyzer.shot_detector.set_fps(video_info.fps)

        target_process_fps = config.video.target_process_fps
        skip = max(1, int(video_info.fps / target_process_fps))

        cap = cv2.VideoCapture(video_path)
        frame_index = 0
        processed = 0
        start_time = time.time()

        while True:
            ret, frame = cap.read()
            if not ret:
                break

            if frame_index % skip == 0:
                self.analyzer.process_frame(frame, frame_index)
                processed += 1

            frame_index += 1

            if progress_callback and frame_index % 100 == 0:
                progress_callback(frame_index, video_info.total_frames)

        cap.release()

        elapsed = time.time() - start_time
        fps_actual = processed / elapsed if elapsed > 0 else 0
        print(f"处理完成: {processed} 帧 / {frame_index} 总帧, 耗时 {elapsed:.1f}s, {fps_actual:.1f} FPS")

        return self.analyzer.build_result(frame_index, video_info.fps)

    def create_annotated_video(
        self,
        video_path: str,
        output_path: str,
        analysis_result: AnalysisResult | None = None,
        progress_callback=None,
        output_fps: float | None = None,
    ) -> str:
        if output_fps is None:
            output_fps = config.video.output_fps
        """创建标注视频 - Supervision Annotator 版"""
        cap = cv2.VideoCapture(video_path)
        src_fps = cap.get(cv2.CAP_PROP_FPS)
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        self.analyzer.shot_detector.set_fps(src_fps)

        analysis_skip = max(1, int(src_fps / 15))
        fps_ratio = output_fps / src_fps if src_fps > 0 else 2.0

        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        writer = cv2.VideoWriter(output_path, fourcc, output_fps, (width, height))

        frame_index = 0
        last_detection = None
        output_frames = 0
        tracker = sv.ByteTrack()

        # Per-frame state
        shot_flash = 0
        shot_flash_made = False

        while True:
            ret, frame = cap.read()
            if not ret:
                break

            if frame_index % analysis_skip == 0:
                prev_shots = self.analyzer.shot_detector.total_shots
                last_detection = self.analyzer.process_frame(frame, frame_index)
                new_shots = self.analyzer.shot_detector.total_shots
                if new_shots > prev_shots:
                    shot_flash = config.video.flash_frames
                    results = self.analyzer.shot_detector.shot_results
                    shot_flash_made = results[-1].made if results else False

            annotated = frame.copy()

            if last_detection is not None and len(last_detection.ball_detections) > 0:
                dets = last_detection.ball_detections

                # Filter high-confidence balls
                if dets.confidence is not None:
                    high_conf_mask = dets.confidence >= 0.25
                    if np.any(high_conf_mask):
                        filtered_dets = dets[high_conf_mask]
                    else:
                        filtered_dets = sv.Detections.empty()
                else:
                    filtered_dets = dets

                if len(filtered_dets) > 0:
                    # Update tracker for trace drawing
                    tracked = tracker.update_with_detections(filtered_dets)

                    # Draw traces (ball trajectory)
                    if len(tracked) > 0:
                        annotated = self._trace_annotator.annotate(annotated, tracked)

                    # Draw circles on balls
                    annotated = self._circle_annotator.annotate(annotated, filtered_dets)

                    # Confidence labels
                    if filtered_dets.confidence is not None and len(filtered_dets.confidence) > 0:
                        labels = [f"{c:.2f}" for c in filtered_dets.confidence]
                        annotated = self._label_annotator.annotate(annotated, filtered_dets, labels)

            # Draw hoop zone
            if last_detection:
                self._draw_hoop_sv(annotated, last_detection)

            # HUD overlay
            self._draw_hud(annotated, width, height)

            # Shot flash effect
            if shot_flash > 0:
                shot_flash -= 1
                self._draw_shot_flash(annotated, width, height, shot_flash_made, shot_flash)

            # Interpolate for 60fps
            repeat = max(1, round(fps_ratio))
            for _ in range(repeat):
                writer.write(annotated)
                output_frames += 1

            frame_index += 1

            if progress_callback and frame_index % 100 == 0:
                progress_callback(frame_index, total_frames)

        cap.release()
        writer.release()

        print(f"输出视频: {output_frames} 帧 @ {output_fps}fps = {output_frames/output_fps:.1f}s")
        return output_path

    def _draw_hoop_sv(self, frame: np.ndarray, detection):
        """用 Supervision 画篮筐和区域"""
        hoop_pos = detection.hoop_position
        hoop_box = detection.hoop_box

        if hoop_pos is None or hoop_box is None:
            return

        cx, cy = int(hoop_pos[0]), int(hoop_pos[1])
        x, y, w, h = int(hoop_box[0]), int(hoop_box[1]), int(hoop_box[2]), int(hoop_box[3])

        # 篮筐用 RoundBox
        hoop_det = sv.Detections(
            xyxy=np.array([[x, y, x + w, y + h]], dtype=np.float32),
            confidence=np.array([0.9]),
            class_id=np.array([0]),
        )
        annotated = self._round_box_annotator.annotate(frame, hoop_det)

        # Rim opening line
        rim_left = int(cx - w * 0.425)
        rim_right = int(cx + w * 0.425)
        cv2.line(frame, (rim_left, cy), (rim_right, cy), (0, 255, 255), 2, cv2.LINE_AA)

        # UP zone (semi-transparent)
        vc = config.video
        up_top = int(y - h * vc.up_zone_height_mult)
        up_left = int(cx - w * vc.up_zone_width_mult)
        up_right = int(cx + w * vc.up_zone_width_mult)
        up_bottom = int(cy + h * vc.up_zone_y_offset)
        overlay = frame.copy()
        cv2.rectangle(overlay, (up_left, up_top), (up_right, up_bottom), (255, 200, 0), -1)
        cv2.addWeighted(overlay, 0.08, frame, 0.92, 0, frame)
        cv2.rectangle(frame, (up_left, up_top), (up_right, up_bottom), (255, 200, 0), 1)

        # DOWN zone (semi-transparent)
        down_top = int(cy - h * vc.down_zone_y_offset)
        down_bottom = int(cy + h * vc.down_zone_height_mult)
        down_left = int(cx - w * vc.down_zone_width_mult)
        down_right = int(cx + w * vc.down_zone_width_mult)
        overlay2 = frame.copy()
        cv2.rectangle(overlay2, (down_left, down_top), (down_right, down_bottom), (0, 0, 255), -1)
        cv2.addWeighted(overlay2, 0.06, frame, 0.94, 0, frame)
        cv2.rectangle(frame, (down_left, down_top), (down_right, down_bottom), (0, 0, 255), 1)

    def _draw_hud(self, frame: np.ndarray, width: int, height: int):
        """HUD 统计叠加"""
        stats = self.analyzer.get_current_stats()

        # Background
        overlay = frame.copy()
        cv2.rectangle(overlay, (10, 10), (240, 130), (0, 0, 0), -1)
        cv2.addWeighted(overlay, 0.65, frame, 0.35, 0, frame)
        cv2.rectangle(frame, (10, 10), (240, 130), (0, 200, 255), 1)

        # Title
        cv2.putText(frame, "SHOT ANALYZER", (20, 35),
                   cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 200, 255), 2, cv2.LINE_AA)

        # Stats
        y = 58
        for key, val in stats.items():
            color = (0, 255, 0) if key == "命中" else (0, 200, 255) if key == "投篮" else (255, 255, 255)
            cv2.putText(frame, f"{key}: {val}", (20, y),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 1, cv2.LINE_AA)
            y += 20

    def _draw_shot_flash(self, frame: np.ndarray, width: int, height: int, made: bool, flash_frame: int):
        """投篮特效"""
        alpha = flash_frame / config.video.flash_frames

        if made:
            # Green flash
            overlay = frame.copy()
            cv2.rectangle(overlay, (0, 0), (width, height), (0, 255, 0), -1)
            cv2.addWeighted(overlay, alpha * 0.2, frame, 1 - alpha * 0.2, 0, frame)

            # SCORE text with glow
            text = "SCORE!"
            font = cv2.FONT_HERSHEY_SIMPLEX
            scale = 3.0
            thickness = 5
            text_size = cv2.getTextSize(text, font, scale, thickness)[0]
            tx = (width - text_size[0]) // 2
            ty = height // 2 + text_size[1] // 2

            # Glow layer
            glow = frame.copy()
            cv2.putText(glow, text, (tx, ty), font, scale, (0, 255, 0), thickness + 6, cv2.LINE_AA)
            cv2.addWeighted(glow, 0.3, frame, 0.7, 0, frame)

            # Sharp text
            cv2.putText(frame, text, (tx, ty), font, scale, (0, 255, 0), thickness, cv2.LINE_AA)
        else:
            # Red tint for miss
            overlay = frame.copy()
            cv2.rectangle(overlay, (0, 0), (width, height), (0, 0, 255), -1)
            cv2.addWeighted(overlay, alpha * 0.1, frame, 1 - alpha * 0.1, 0, frame)

    def debug_detection(
        self,
        video_path: str,
        output_path: str,
        max_frames: int = 300,
        output_fps: float = 60.0,
    ) -> str:
        """调试模式"""
        cap = cv2.VideoCapture(video_path)
        src_fps = cap.get(cv2.CAP_PROP_FPS)
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        self.analyzer.shot_detector.set_fps(src_fps)
        fps_ratio = output_fps / src_fps if src_fps > 0 else 2.0

        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        writer = cv2.VideoWriter(output_path, fourcc, output_fps, (width, height))

        frame_index = 0
        skip = max(1, int(src_fps / 15))
        tracker = sv.ByteTrack(track_thresh=0.15, track_buffer=60)

        while frame_index < max_frames:
            ret, frame = cap.read()
            if not ret:
                break

            if frame_index % skip == 0:
                detection = self.analyzer.process_frame(frame, frame_index)
                annotated = frame.copy()

                if len(detection.ball_detections) > 0:
                    dets = detection.ball_detections
                    if dets.confidence is not None:
                        mask = dets.confidence >= 0.2
                        if np.any(mask):
                            dets = dets[mask]

                    if len(dets) > 0:
                        tracked = tracker.update_with_detections(dets)
                        if len(tracked) > 0:
                            annotated = self._trace_annotator.annotate(annotated, tracked)
                        annotated = self._circle_annotator.annotate(annotated, dets)

                self._draw_hoop_sv(annotated, detection)
                self._draw_hud(annotated, width, height)
            else:
                annotated = frame

            repeat = max(1, round(fps_ratio))
            for _ in range(repeat):
                writer.write(annotated)

            frame_index += 1

        cap.release()
        writer.release()
        return output_path
