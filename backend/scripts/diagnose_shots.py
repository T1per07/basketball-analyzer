"""Diagnostic script: analyze why shot detection count is low"""
import sys
import time
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).parent))

from models.detection import CombinedDetector
from models.shot_detector import ShotDetector
from config.settings import config


def diagnose_video(video_path: str):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"Cannot open: {video_path}")
        return

    fps = cap.get(cv2.CAP_PROP_FPS)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    print(f"\n{'='*60}")
    print(f"视频: {Path(video_path).name}")
    print(f"分辨率: {w}x{h} @ {fps:.1f}fps, {total} 帧, {total/fps:.1f}s")
    print(f"{'='*60}")

    detector = CombinedDetector()
    shot_detector = ShotDetector(fps=fps)

    # 统计
    frames_with_ball = 0
    frames_with_hoop = 0
    frames_in_up = 0
    frames_in_down = 0
    ball_detection_counts = []
    up_zone_entries = 0
    down_zone_entries = 0
    cooldown_blocks = 0
    speed_blocks = 0
    time_blocks = 0
    rim_overlaps = 0

    skip = max(1, int(fps / 15))  # ~15fps processing
    frame_idx = 0

    prev_in_up_tracks = set()
    prev_in_down_tracks = set()

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        if frame_idx % skip == 0:
            det = detector.detect(frame, frame_idx)

            # 篮筐
            if det.hoop_position:
                frames_with_hoop += 1
                x, y, bw, bh = det.hoop_box
                shot_detector.update_hoop(x, y, bw, bh)

            # 球
            n_balls = len(det.ball_detections) if det.ball_detections is not None else 0
            if n_balls > 0:
                frames_with_ball += 1
            ball_detection_counts.append(n_balls)

            # 提取球位置
            ball_positions = []
            ball_sizes = []
            if n_balls > 0:
                for i in range(n_balls):
                    bbox = det.ball_detections.xyxy[i]
                    cx = (bbox[0] + bbox[2]) / 2
                    cy = (bbox[1] + bbox[3]) / 2
                    area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
                    ball_positions.append((cx, cy))
                    ball_sizes.append(float(area))

            # 处理
            prev_shots = shot_detector.total_shots
            shot_detector.process_frame(ball_positions, ball_sizes, frame_index=frame_idx)

            if shot_detector.total_shots > prev_shots:
                rim_overlaps += 1

        frame_idx += 1

    cap.release()

    processed = frame_idx // skip
    print(f"\n--- 检测统计 ({processed} 帧) ---")
    print(f"检测到球的帧: {frames_with_ball}/{processed} ({frames_with_ball/max(1,processed)*100:.1f}%)")
    print(f"检测到篮筐的帧: {frames_with_hoop}/{processed} ({frames_with_hoop/max(1,processed)*100:.1f}%)")
    print(f"球在 UP zone 的帧: {frames_in_up}")
    print(f"球在 DOWN zone 的帧: {frames_in_down}")

    if ball_detection_counts:
        print(f"每帧球数: min={min(ball_detection_counts)}, max={max(ball_detection_counts)}, avg={np.mean(ball_detection_counts):.1f}")

    print(f"\n--- 投篮检测结果 ---")
    print(f"总投篮: {shot_detector.total_shots}")
    print(f"命中: {shot_detector.total_made}")

    if shot_detector.shot_results:
        print(f"\n--- 投篮详情 ---")
        for i, s in enumerate(shot_detector.shot_results):
            print(f"  #{i+1}: frame={s.frame}, made={s.made}, conf={s.confidence:.2f}, has_apex={s.has_apex}")

    # 分析篮筐信息（使用当前 ShotDetector API）
    if shot_detector.hoop_detected and shot_detector._locked_hoop:
        lx, ly, lw, lh = shot_detector._locked_hoop
        print(f"\n--- 篮筐信息 ---")
        print(f"中心: ({lx:.0f}, {ly:.0f}), 大小: {lw:.0f}x{lh:.0f}")

        # UP zone（参考 shot_detector._detect_up 的范围）
        up_left = int(lx - 8 * lw)
        up_right = int(lx + 8 * lw)
        up_top = int(ly - 3 * lh)
        up_bottom = int(ly - 0.3 * lh)
        print(f"\nUP zone: x=[{up_left}, {up_right}], y=[{up_top}, {up_bottom}]")
        print(f"  width: {up_right - up_left}px, height: {up_bottom - up_top}px")

        # DOWN zone
        down_threshold = ly + 0.3 * lh
        print(f"DOWN threshold: y > {down_threshold:.0f}")

    return shot_detector


if __name__ == "__main__":
    video_dir = Path(__file__).parent.parent / "data" / "samples"
    videos = list(video_dir.glob("*.mp4"))
    if not videos:
        print("No videos found!")
    else:
        for v in videos:
            diagnose_video(str(v))
