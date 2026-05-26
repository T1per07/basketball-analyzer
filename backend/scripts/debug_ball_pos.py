"""Debug ball positions relative to hoop to understand why no shots detected"""
import sys, time
sys.path.insert(0, '.')

import cv2
import numpy as np
from models.detection import CombinedDetector
from models.shot_detector import ShotDetector

def debug_video(video_path: str, max_frames: int = 150):
    print(f"Debugging: {video_path}")

    detector = CombinedDetector()
    shot_detector = ShotDetector(fps=30.0)

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"  ERROR: Cannot open video")
        return

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    shot_detector.set_fps(fps)

    frame_idx = 0
    hoop_set = False

    while cap.isOpened() and frame_idx < max_frames:
        ret, frame = cap.read()
        if not ret:
            break

        if frame_idx % 2 == 0:
            det = detector.detect(frame, frame_idx)

            if det.hoop_box and not hoop_set:
                x, y, w, h = det.hoop_box
                shot_detector.update_hoop(x, y, w, h)
                hoop_set = True

            if det.hoop_box:
                x, y, w, h = det.hoop_box
                shot_detector.update_hoop(x, y, w, h)

            if len(det.ball_detections) > 0 and shot_detector._hoop_pos:
                hcx = shot_detector._hoop_pos[-1][0]
                hcy = shot_detector._hoop_pos[-1][1]
                hw = shot_detector._hoop_pos[-1][3]
                hh = shot_detector._hoop_pos[-1][4]

                up_y1 = hcy - 3 * hh
                up_y2 = hcy - 0.3 * hh
                down_y = hcy + 0.3 * hh

                for i in range(len(det.ball_detections)):
                    bbox = det.ball_detections.xyxy[i]
                    cx = (bbox[0] + bbox[2]) / 2
                    cy = (bbox[1] + bbox[3]) / 2
                    conf = float(det.ball_detections.confidence[i]) if det.ball_detections.confidence is not None else 0.5

                    in_up = (hcx - 8*hw < cx < hcx + 8*hw and up_y1 < cy < up_y2)
                    in_down = cy > down_y
                    in_hoop_region = (hcx - 2*hw < cx < hcx + 2*hw and hcy - 1.5*hh < cy < hcy + 1.0*hh)

                    if in_up or in_down or in_hoop_region or frame_idx < 20:
                        print(f"  Frame {frame_idx}: ball=({cx:.0f}, {cy:.0f}) conf={conf:.2f} "
                              f"{'UP' if in_up else ''} {'DOWN' if in_down else ''} {'HOOP' if in_hoop_region else ''}")

            ball_positions = []
            ball_sizes = []
            ball_confs = []
            if len(det.ball_detections) > 0:
                for i in range(len(det.ball_detections)):
                    bbox = det.ball_detections.xyxy[i]
                    cx = (bbox[0] + bbox[2]) / 2
                    cy = (bbox[1] + bbox[3]) / 2
                    area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
                    conf = float(det.ball_detections.confidence[i]) if det.ball_detections.confidence is not None else 0.5
                    ball_positions.append((cx, cy))
                    ball_sizes.append(float(area))
                    ball_confs.append(conf)

            shot = shot_detector.process_frame(ball_positions, ball_sizes, ball_confs, frame_index=frame_idx)
            if shot:
                tag = "MAKE" if shot.made else "MISS"
                print(f"  >>> SHOT at frame {frame_idx}: {tag}")

        frame_idx += 1

    cap.release()

    if shot_detector._hoop_pos:
        hcx = shot_detector._hoop_pos[-1][0]
        hcy = shot_detector._hoop_pos[-1][1]
        hw = shot_detector._hoop_pos[-1][3]
        hh = shot_detector._hoop_pos[-1][4]
        print(f"\nHoop: center=({hcx:.0f}, {hcy:.0f}), size={hw:.0f}x{hh:.0f}")
        print(f"UP zone: x=[{hcx-8*hw:.0f}, {hcx+8*hw:.0f}], y=[{hcy-3*hh:.0f}, {hcy-0.3*hh:.0f}]")
        print(f"DOWN zone: y > {hcy+0.3*hh:.0f}")
    print(f"Ball positions stored: {len(shot_detector._ball_pos)}")
    print(f"Shots: {shot_detector.total_shots}")

if __name__ == '__main__':
    import glob
    videos = glob.glob('D:/Projects/basketball-analyzer/data/uploads/*shooting*.mp4')[:1]
    if not videos:
        videos = glob.glob('D:/Projects/basketball-analyzer/data/uploads/*.mp4')[:1]
    for v in videos:
        debug_video(v, max_frames=200)
