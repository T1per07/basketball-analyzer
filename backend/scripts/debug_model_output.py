"""Debug what the basketball model actually detects per frame"""
import sys
sys.path.insert(0, '.')

import cv2
import numpy as np
from models.basketball_detector import BasketballDetector

def debug_model(video_path: str, max_frames: int = 60):
    print(f"Model debug: {video_path}")
    detector = BasketballDetector(model_path="models/best.pt")

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print("Cannot open video")
        return

    fps = cap.get(cv2.CAP_PROP_FPS)
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    print(f"Video: {w}x{h} @ {fps:.1f}fps")

    frame_idx = 0
    ball_count = 0
    hoop_count = 0

    while cap.isOpened() and frame_idx < max_frames:
        ret, frame = cap.read()
        if not ret:
            break

        if frame_idx % 2 == 0:
            # Run with very low conf to see everything
            results = detector.model(frame, conf=0.05, verbose=False)[0]

            n_dets = len(results.boxes) if results.boxes is not None else 0
            if n_dets > 0:
                for box in results.boxes:
                    cls_id = int(box.cls[0])
                    conf = float(box.conf[0])
                    x1, y1, x2, y2 = box.xyxy[0].tolist()
                    cx = (x1 + x2) / 2
                    cy = (y1 + y2) / 2
                    bw = x2 - x1
                    bh = y2 - y1
                    name = "Ball" if cls_id == 0 else "Hoop" if cls_id == 1 else f"cls{cls_id}"

                    if cls_id == 0:
                        ball_count += 1
                    elif cls_id == 1:
                        hoop_count += 1

                    if conf > 0.1:  # Only show reasonable detections
                        print(f"  Frame {frame_idx}: {name} conf={conf:.2f} pos=({cx:.0f},{cy:.0f}) size={bw:.0f}x{bh:.0f}")

        frame_idx += 1

    cap.release()
    processed = frame_idx // 2
    print(f"\nTotal: {processed} frames, {ball_count} ball detections, {hoop_count} hoop detections")
    print(f"Ball detection rate: {ball_count/max(1,processed)*100:.1f}%")

if __name__ == '__main__':
    import glob
    videos = glob.glob('D:/Projects/basketball-analyzer/data/uploads/*shooting*.mp4')[:1]
    if not videos:
        videos = glob.glob('D:/Projects/basketball-analyzer/data/uploads/*.mp4')[:1]
    for v in videos:
        debug_model(v, max_frames=60)
