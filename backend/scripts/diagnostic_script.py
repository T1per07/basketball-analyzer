"""Diagnostic script for basketball shot detection analysis."""
import sys
import os
import traceback

# Ensure we're in the right directory
os.chdir(os.path.dirname(os.path.abspath(__file__)))

try:
    import cv2
    import numpy as np
    from services.video_processor import VideoProcessor
    from config.settings import config

    print("=== Basketball Shot Detection Diagnostic ===")
    print(f"OpenCV version: {cv2.__version__}")
    print(f"NumPy version: {np.__version__}")
    print(f"Skip frames: {config.detection.skip_frames}")
    print(f"Ball confidence threshold: {config.detection.ball_confidence_threshold}")
    print(f"Ball model: {config.detection.ball_model_name}")
    print(f"Input width: {config.detection.input_width}")
    print(f"Color detection enabled: {config.detection.enable_color_detection}")
    print(f"Motion detection enabled: {config.detection.enable_motion_detection}")
    print()

    proc = VideoProcessor()

    video_path = '../data/samples/shooting_analysis.mp4'
    print(f"Opening video: {video_path}")
    cap = cv2.VideoCapture(video_path)

    if not cap.isOpened():
        print(f"ERROR: Cannot open video at {video_path}")
        sys.exit(1)

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    print(f"Video: {width}x{height}, {fps:.1f}fps, {total_frames} frames, {total_frames/fps:.1f}s")
    print()

    frame_index = 0
    skip = config.detection.skip_frames

    # Save diagnostic frames
    os.makedirs('../data/output/diagnostic', exist_ok=True)

    # Use only even key_frames (skip=2)
    key_frames = [500, 1000, 1500, 1800, 1850, 1900, 2000, 2500, 3000, 3500, 4000, 5000, 6000, 7000, 8000, 9000]
    # Filter to only even frames (matching skip=2)
    key_frames = [f for f in key_frames if f % skip == 0]
    max_key = max(key_frames)
    print(f"Key frames to capture (after filtering for skip={skip}): {key_frames}")
    print(f"Will process up to frame {max_key}")
    print()

    saved_frames = []
    detection_log = []

    while frame_index <= max_key:
        ret, frame = cap.read()
        if not ret:
            print(f"WARNING: Video ended at frame {frame_index} (expected to reach {max_key})")
            break

        if frame_index % skip == 0:
            try:
                detection = proc.analyzer.process_frame(frame, frame_index)
            except Exception as e:
                print(f"ERROR processing frame {frame_index}: {e}")
                traceback.print_exc()
                frame_index += 1
                continue

            if frame_index in key_frames:
                # Save annotated frame
                annotated = frame.copy()

                # Draw ball detections
                ball_count = 0
                if detection.ball_detections is not None and len(detection.ball_detections) > 0:
                    ball_count = len(detection.ball_detections)
                    for i in range(ball_count):
                        bbox = detection.ball_detections.xyxy[i].astype(int)
                        conf = detection.ball_detections.confidence[i] if detection.ball_detections.confidence is not None else 0
                        cv2.rectangle(annotated, (bbox[0], bbox[1]), (bbox[2], bbox[3]), (0, 165, 255), 2)
                        cv2.putText(annotated, f"ball {conf:.2f}", (bbox[0], bbox[1]-5), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 165, 255), 1)

                # Draw hoop（使用当前 ShotDetector API）
                sd = proc.analyzer.shot_detector
                hoop_detected = sd.hoop_detected
                if hoop_detected and sd._locked_hoop:
                    lx, ly, lw, lh = sd._locked_hoop
                    hoop_pos = f"({lx:.0f},{ly:.0f})"
                    hoop_x, hoop_y, hoop_w, hoop_h = int(lx - lw/2), int(ly - lh/2), int(lw), int(lh)
                    cv2.rectangle(annotated, (hoop_x, hoop_y), (hoop_x + hoop_w, hoop_y + hoop_h), (0, 255, 0), 2)
                    # Draw rim line
                    rim_left = int(lx - lw * 0.425)
                    rim_right = int(lx + lw * 0.425)
                    cv2.line(annotated, (rim_left, int(ly)), (rim_right, int(ly)), (0, 255, 255), 2)
                else:
                    hoop_pos = "NOT DETECTED"

                # Draw stats
                stats = proc.analyzer.get_current_stats()
                y = 30
                for key, val in stats.items():
                    cv2.putText(annotated, f"{key}: {val}", (10, y), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
                    y += 25

                # Add frame info
                cv2.putText(annotated, f"Frame: {frame_index}", (10, height - 20),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)

                output_path = f'../data/output/diagnostic/frame_{frame_index:05d}.png'
                cv2.imwrite(output_path, annotated)
                saved_frames.append(output_path)

                # Log details
                sd = proc.analyzer.shot_detector
                shot_count = sd.total_shots
                made_count = sd.total_made
                hoop_size = f"({sd._locked_hoop[2]:.0f}x{sd._locked_hoop[3]:.0f})" if sd._locked_hoop else "N/A"

                info = {
                    'frame': frame_index,
                    'balls': ball_count,
                    'hoop_detected': hoop_detected,
                    'hoop_pos': hoop_pos,
                    'hoop_size': hoop_size,
                    'total_shots': shot_count,
                    'made_shots': made_count,
                }
                detection_log.append(info)

                print(f"Frame {frame_index:5d}: balls={ball_count}, hoop={hoop_pos}, "
                      f"size={hoop_size}, "
                      f"shots={shot_count}, made={made_count}")

        frame_index += 1

    cap.release()

    print()
    print("=" * 60)
    print("DIAGNOSTIC SUMMARY")
    print("=" * 60)
    print(f"Frames saved: {len(saved_frames)}")
    for path in saved_frames:
        print(f"  - {path}")
    print()

    print("DETECTION LOG:")
    print(f"{'Frame':>6} | {'Balls':>5} | {'Hoop':>12} | {'Size':>8} | {'Shots':>5} | {'Made':>4}")
    print("-" * 55)
    for info in detection_log:
        print(f"{info['frame']:>6} | {info['balls']:>5} | {info['hoop_pos']:>12} | "
              f"{info['hoop_size']:>8} | "
              f"{info['total_shots']:>5} | {info['made_shots']:>4}")

    print()
    print("Done!")

except Exception as e:
    print(f"FATAL ERROR: {e}")
    traceback.print_exc()
    sys.exit(1)
