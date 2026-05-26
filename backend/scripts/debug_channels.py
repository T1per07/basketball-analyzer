"""Debug each detection channel separately"""
import sys
sys.path.insert(0, '.')

import cv2
import numpy as np
from models.detection import CombinedDetector, ColorBallDetector, MotionBallDetector
from models.basketball_detector import BasketballDetector
from models.hoop_detector import HoopDetector

def debug_channels(video_path: str, max_frames: int = 40):
    print(f"Channel debug: {video_path}")

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print("Cannot open video")
        return

    bb_detector = BasketballDetector(model_path="models/best.pt")
    color_detector = ColorBallDetector()
    motion_detector = MotionBallDetector()
    hoop_detector = HoopDetector()

    frame_idx = 0
    bb_ball_count = 0
    color_ball_count = 0
    motion_ball_count = 0
    hoop_count = 0

    while cap.isOpened() and frame_idx < max_frames:
        ret, frame = cap.read()
        if not ret:
            break

        if frame_idx % 2 == 0:
            # Basketball model
            bb_balls, bb_hoops, bb_hoop_box = bb_detector.detect(frame, ball_conf=0.05, hoop_conf=0.1)

            # Color detector
            color_balls = color_detector.detect(frame)

            # Motion detector
            motion_balls = motion_detector.detect(frame)

            # Hoop detector
            hoop_detector.detect(frame)

            bb_n = len(bb_balls) if bb_balls is not None else 0
            color_n = len(color_balls) if color_balls is not None else 0
            motion_n = len(motion_balls) if motion_balls is not None else 0

            bb_ball_count += bb_n
            color_ball_count += color_n
            motion_ball_count += motion_n

            if hoop_detector.hoop_position:
                hoop_count += 1

            if bb_n > 0 or color_n > 0 or motion_n > 0:
                print(f"  Frame {frame_idx}: BB={bb_n} Color={color_n} Motion={motion_n} Hoop={'Y' if hoop_detector.hoop_position else 'N'}")

                if color_n > 0 and color_balls.confidence is not None:
                    for i in range(min(color_n, 3)):
                        cx = (color_balls.xyxy[i][0] + color_balls.xyxy[i][2]) / 2
                        cy = (color_balls.xyxy[i][1] + color_balls.xyxy[i][3]) / 2
                        print(f"    Color ball {i}: ({cx:.0f},{cy:.0f}) conf={color_balls.confidence[i]:.2f}")

                if motion_n > 0 and motion_balls.confidence is not None:
                    for i in range(min(motion_n, 3)):
                        cx = (motion_balls.xyxy[i][0] + motion_balls.xyxy[i][2]) / 2
                        cy = (motion_balls.xyxy[i][1] + motion_balls.xyxy[i][3]) / 2
                        print(f"    Motion ball {i}: ({cx:.0f},{cy:.0f}) conf={motion_balls.confidence[i]:.2f}")

        frame_idx += 1

    cap.release()
    processed = frame_idx // 2
    print(f"\nDetection rates ({processed} frames):")
    print(f"  Basketball model: {bb_ball_count} ({bb_ball_count/max(1,processed)*100:.1f}%)")
    print(f"  Color detector: {color_ball_count} ({color_ball_count/max(1,processed)*100:.1f}%)")
    print(f"  Motion detector: {motion_ball_count} ({motion_ball_count/max(1,processed)*100:.1f}%)")
    print(f"  Hoop detected: {hoop_count}/{processed}")

if __name__ == '__main__':
    import glob
    videos = glob.glob('D:/Projects/basketball-analyzer/data/uploads/*shooting*.mp4')[:1]
    if not videos:
        videos = glob.glob('D:/Projects/basketball-analyzer/data/uploads/*.mp4')[:1]
    for v in videos:
        debug_channels(v, max_frames=40)
