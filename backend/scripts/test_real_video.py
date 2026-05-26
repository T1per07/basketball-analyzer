"""用真实视频测试投篮检测"""
import sys, time
sys.path.insert(0, '.')

import cv2
from models.detection import CombinedDetector
from models.shot_detector import ShotDetector

def test_video(video_path: str, max_frames: int = 300):
    print(f"Testing: {video_path}")

    detector = CombinedDetector()
    shot_detector = ShotDetector(fps=30.0)

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"  ERROR: Cannot open video")
        return

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    shot_detector.set_fps(fps)

    print(f"  Frames: {total_frames}, FPS: {fps:.1f}")

    frame_idx = 0
    hoop_found_frames = 0
    ball_found_frames = 0
    start = time.time()

    while cap.isOpened() and frame_idx < max_frames:
        ret, frame = cap.read()
        if not ret:
            break

        # 每 2 帧检测一次
        if frame_idx % 2 == 0:
            det = detector.detect(frame, frame_idx)

            # 更新篮筐
            if det.hoop_box:
                x, y, w, h = det.hoop_box
                shot_detector.update_hoop(x, y, w, h)
                hoop_found_frames += 1

            # 更新球
            ball_positions = []
            ball_sizes = []
            ball_confs = []
            if len(det.ball_detections) > 0:
                ball_found_frames += 1
                for i in range(len(det.ball_detections)):
                    bbox = det.ball_detections.xyxy[i]
                    cx = (bbox[0] + bbox[2]) / 2
                    cy = (bbox[1] + bbox[3]) / 2
                    area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
                    conf = float(det.ball_detections.confidence[i]) if det.ball_detections.confidence is not None else 0.5
                    ball_positions.append((cx, cy))
                    ball_sizes.append(float(area))
                    ball_confs.append(conf)

            # 投篮检测
            shot = shot_detector.process_frame(
                ball_positions, ball_sizes, ball_confs,
                frame_index=frame_idx,
            )
            if shot:
                tag = "MAKE" if shot.made else "MISS"
                print(f"  Frame {frame_idx}: SHOT {tag} (conf={shot.confidence:.2f})")

        frame_idx += 1

    elapsed = time.time() - start
    cap.release()

    print(f"\n  Results:")
    print(f"    Processed: {frame_idx} frames in {elapsed:.1f}s ({frame_idx/elapsed:.1f} fps)")
    print(f"    Hoop found: {hoop_found_frames}/{frame_idx//2} frames")
    print(f"    Ball found: {ball_found_frames}/{frame_idx//2} frames")
    print(f"    Shots: {shot_detector.total_shots} ({shot_detector.total_made} made)")
    print(f"    Hoop pos: {shot_detector._hoop_pos[-1] if shot_detector._hoop_pos else 'None'}")
    print()

if __name__ == '__main__':
    import glob

    videos = glob.glob('D:/Projects/basketball-analyzer/data/uploads/*shooting*.mp4')[:3]
    if not videos:
        videos = glob.glob('D:/Projects/basketball-analyzer/data/uploads/*.mp4')[:3]

    for v in videos:
        test_video(v, max_frames=300)
