"""快速诊断 - 只分析视频后半段（投篮集中区域）"""
import sys
import os
os.chdir(os.path.dirname(os.path.abspath(__file__)))

import cv2
import numpy as np
from collections import Counter
from services.video_processor import VideoProcessor
from config.settings import config


def run_diagnostic(video_path: str, start_sec: float = 60, duration_sec: float = 120):
    print("=" * 70)
    print("  BASKETBALL SHOT DETECTION DIAGNOSTIC (FAST)")
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

    start_frame = int(start_sec * fps)
    end_frame = min(int((start_sec + duration_sec) * fps), total_frames)

    print(f"\nVideo: {width}x{height}, {fps:.1f}fps, {total_frames} frames, {total_frames/fps:.1f}s")
    print(f"Analyzing: {start_sec}s - {start_sec + duration_sec}s (frames {start_frame}-{end_frame})")
    print(f"Skip frames: {skip}")
    print()

    # 跳到起始帧
    cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)

    frames_with_ball = 0
    frames_with_hoop = 0
    total_processed = 0
    ball_count_dist = Counter()
    hoop_positions = []

    frame_index = start_frame

    while frame_index < end_frame:
        ret, frame = cap.read()
        if not ret:
            break

        if frame_index % skip == 0:
            try:
                detection = proc.analyzer.process_frame(frame, frame_index)
            except Exception as e:
                print(f"ERROR frame {frame_index}: {e}")
                frame_index += 1
                continue

            total_processed += 1
            n_balls = len(detection.ball_detections) if detection.ball_detections is not None else 0
            ball_count_dist[n_balls] += 1

            if n_balls > 0:
                frames_with_ball += 1

            if detection.hoop_position:
                frames_with_hoop += 1
                hoop_positions.append(detection.hoop_position)

            if total_processed % 100 == 0:
                sd = proc.analyzer.shot_detector
                print(f"  [{frame_index}/{end_frame}] balls={n_balls}, shots={sd.total_shots}, made={sd.total_made}")

        frame_index += 1

    cap.release()

    shot_results = proc.analyzer.shot_detector.shot_results
    sd = proc.analyzer.shot_detector

    print()
    print("-" * 70)
    print("  DETECTION STATS")
    print("-" * 70)
    print(f"Frames processed: {total_processed}")
    print(f"Frames with ball: {frames_with_ball} ({frames_with_ball/total_processed*100:.1f}%)")
    print(f"Frames with hoop: {frames_with_hoop} ({frames_with_hoop/total_processed*100:.1f}%)")
    print(f"\nBall count per frame:")
    for n in sorted(ball_count_dist.keys()):
        print(f"  {n} balls: {ball_count_dist[n]} frames ({ball_count_dist[n]/total_processed*100:.1f}%)")

    if sd._locked_hoop:
        lx, ly, lw, lh = sd._locked_hoop
        print(f"\nHoop: center=({lx:.0f},{ly:.0f}), size=({lw:.0f}x{lh:.0f}), detected={sd.hoop_detected}")
    else:
        print(f"\nHoop: NOT DETECTED")

    if hoop_positions:
        xs = [p[0] for p in hoop_positions]
        ys = [p[1] for p in hoop_positions]
        print(f"Hoop pos range: x=[{min(xs)},{max(xs)}], y=[{min(ys)},{max(ys)}], std_x={np.std(xs):.1f}, std_y={np.std(ys):.1f}")

    print()
    print("-" * 70)
    print("  SHOT DETECTION RESULTS")
    print("-" * 70)
    print(f"Total shots: {len(shot_results)}")
    print(f"Made: {sum(1 for s in shot_results if s.made)}")
    print(f"Missed: {sum(1 for s in shot_results if not s.made)}")

    if shot_results:
        print(f"\n{'#':>3} | {'Frame':>6} | {'BallID':>6} | {'Result':>6} | {'RimOL':>6} | {'Conf':>6}")
        print("-" * 50)
        for i, s in enumerate(shot_results):
            print(f"{i+1:>3} | {s.frame:>6} | {s.ball_id:>6} | {'MADE' if s.made else 'MISS':>6} | "
                  f"{'Y' if s.rim_overlap else 'N':>6} | {s.confidence:>6.2f}")

    # 篮筐重叠统计
    if shot_results:
        overlap_count = sum(1 for s in shot_results if s.rim_overlap)
        made_count = sum(1 for s in shot_results if s.made)
        print(f"\nRim overlap: {overlap_count}/{len(shot_results)} ({overlap_count/len(shot_results)*100:.1f}%)")
        print(f"Made (final): {made_count}/{len(shot_results)} ({made_count/len(shot_results)*100:.1f}%)")

        # 置信度分布
        confs = [s.confidence for s in shot_results]
        print(f"Confidence: mean={np.mean(confs):.2f}, min={min(confs):.2f}, max={max(confs):.2f}")

    # 最终结果
    result = proc.analyzer.build_result(total_frames, fps)
    print()
    print("-" * 70)
    print("  FINAL RESULT")
    print("-" * 70)
    print(f"Total: {result.total_shots}, Made: {result.made_shots}, Pct: {result.overall_percentage*100:.1f}%")

    by_type = result.get_stats_by_type()
    if by_type:
        for t, s in by_type.items():
            print(f"  {t}: {s['made']}/{s['attempts']} ({s['percentage']*100:.1f}%)")


if __name__ == "__main__":
    video = sys.argv[1] if len(sys.argv) > 1 else "../data/samples/shooting_analysis.mp4"
    run_diagnostic(video, start_sec=60, duration_sec=120)
