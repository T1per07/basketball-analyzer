"""诊断脚本 - 分析投篮检测的各个环节"""
import sys
import os
os.chdir(os.path.dirname(os.path.abspath(__file__)))

import cv2
import numpy as np
from collections import Counter
from services.video_processor import VideoProcessor
from config.settings import config


def run_diagnostic(video_path: str):
    print("=" * 70)
    print("  BASKETBALL SHOT DETECTION DIAGNOSTIC")
    print("=" * 70)

    proc = VideoProcessor()
    cap = cv2.VideoCapture(video_path)

    if not cap.isOpened():
        print(f"ERROR: Cannot open {video_path}")
        return

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    skip = config.detection.skip_frames

    print(f"\nVideo: {width}x{height}, {fps:.1f}fps, {total_frames} frames, {total_frames/fps:.1f}s")
    print(f"Skip frames: {skip}, Process FPS: {fps/skip:.1f}")
    print(f"Ball confidence: {config.detection.ball_confidence_threshold}")
    print()

    # 统计数据
    frames_with_ball = 0
    frames_with_hoop = 0
    total_processed = 0
    ball_count_dist = Counter()  # 每帧检测到几个球
    hoop_positions = []

    frame_index = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        if frame_index % skip == 0:
            detection = proc.analyzer.process_frame(frame, frame_index)
            total_processed += 1

            n_balls = len(detection.ball_detections) if detection.ball_detections is not None else 0
            ball_count_dist[n_balls] += 1

            if n_balls > 0:
                frames_with_ball += 1

            if detection.hoop_position:
                frames_with_hoop += 1
                hoop_positions.append(detection.hoop_position)

        frame_index += 1

    cap.release()

    # 获取最终结果
    shot_results = proc.analyzer.shot_detector.shot_results
    sd = proc.analyzer.shot_detector
    hoop = sd.hoop

    print("-" * 70)
    print("  DETECTION STATS")
    print("-" * 70)
    print(f"Total frames processed: {total_processed}")
    print(f"Frames with ball detected: {frames_with_ball} ({frames_with_ball/total_processed*100:.1f}%)")
    print(f"Frames with hoop detected: {frames_with_hoop} ({frames_with_hoop/total_processed*100:.1f}%)")
    print(f"\nBall count distribution (per frame):")
    for n in sorted(ball_count_dist.keys()):
        pct = ball_count_dist[n] / total_processed * 100
        print(f"  {n} balls: {ball_count_dist[n]} frames ({pct:.1f}%)")

    print(f"\nFinal hoop state: x={hoop.x}, y={hoop.y}, w={hoop.w}, h={hoop.h}, detected={hoop.detected}")

    if hoop_positions:
        xs = [p[0] for p in hoop_positions]
        ys = [p[1] for p in hoop_positions]
        print(f"Hoop position range: x=[{min(xs)}, {max(xs)}], y=[{min(ys)}, {max(ys)}]")
        print(f"Hoop position std: x={np.std(xs):.1f}, y={np.std(ys):.1f}")

    print()
    print("-" * 70)
    print("  SHOT DETECTION RESULTS")
    print("-" * 70)
    print(f"Total shots detected: {len(shot_results)}")
    print(f"Made shots: {sum(1 for s in shot_results if s.made)}")
    print(f"Missed shots: {sum(1 for s in shot_results if not s.made)}")

    if shot_results:
        print(f"\nShot details:")
        print(f"{'#':>3} | {'Frame':>6} | {'BallID':>6} | {'Result':>6} | {'RimOL':>6} | {'Conf':>6} | {'Apex':>5}")
        print("-" * 55)
        for i, s in enumerate(shot_results):
            print(f"{i+1:>3} | {s.frame:>6} | {s.ball_id:>6} | {'MADE' if s.made else 'MISS':>6} | "
                  f"{'Y' if s.rim_overlap else 'N':>6} | {s.confidence:>6.2f} | {'Y' if s.has_apex else 'N':>5}")

    # 统计 rim overlap
    if shot_results:
        overlap_count = sum(1 for s in shot_results if s.rim_overlap)
        print(f"\nRim overlap: {overlap_count}/{len(shot_results)} ({overlap_count/len(shot_results)*100:.1f}%)")
        made_count = sum(1 for s in shot_results if s.made)
        print(f"Made (final): {made_count}/{len(shot_results)} ({made_count/len(shot_results)*100:.1f}%)")

    # 后处理后的结果
    result = proc.analyzer.build_result(total_frames, fps)
    print()
    print("-" * 70)
    print("  FINAL ANALYSIS RESULT (after post-processing)")
    print("-" * 70)
    print(f"Total shots: {result.total_shots}")
    print(f"Made: {result.made_shots}")
    print(f"Percentage: {result.overall_percentage*100:.1f}%")
    print(f"Average distance: {result.average_distance:.1f}m")

    by_type = result.get_stats_by_type()
    if by_type:
        print(f"\nBy type:")
        for t, s in by_type.items():
            print(f"  {t}: {s['made']}/{s['attempts']} ({s['percentage']*100:.1f}%) dist={s['avg_distance']:.1f}m")


if __name__ == "__main__":
    video = sys.argv[1] if len(sys.argv) > 1 else "../data/samples/shooting_analysis.mp4"
    run_diagnostic(video)
