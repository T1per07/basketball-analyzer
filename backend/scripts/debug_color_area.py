"""Debug color detector to understand why it finds nothing"""
import sys
sys.path.insert(0, '.')

import cv2
import numpy as np
from models.detection import ColorBallDetector

def debug_color(video_path: str, max_frames: int = 20):
    print(f"Color debug: {video_path}")
    detector = ColorBallDetector()

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print("Cannot open video")
        return

    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    print(f"Frame: {w}x{h}")

    # Compute what the detector sees
    target_w = 320
    internal_scale = target_w / w
    sh = int(h * internal_scale)
    sw = target_w
    min_area = max(50, int(sw * sh * 0.0005))
    max_area = int(sw * sh * 0.015)
    print(f"Internal: {sw}x{sh}, min_area={min_area}, max_area={max_area}")

    frame_idx = 0
    while cap.isOpened() and frame_idx < max_frames:
        ret, frame = cap.read()
        if not ret:
            break

        if frame_idx % 2 == 0:
            # Manual color detection with debug
            small = cv2.resize(frame, (sw, sh))
            hsv = cv2.cvtColor(small, cv2.COLOR_BGR2HSV)

            ranges = [
                (np.array([5, 100, 100]), np.array([22, 255, 255])),
                (np.array([0, 120, 120]), np.array([8, 255, 255])),
            ]

            combined_mask = np.zeros(hsv.shape[:2], dtype=np.uint8)
            for lower, upper in ranges:
                mask = cv2.inRange(hsv, lower, upper)
                combined_mask = cv2.bitwise_or(combined_mask, mask)

            # Count orange pixels
            orange_pixels = np.count_nonzero(combined_mask)
            total_pixels = sh * sw

            contours, _ = cv2.findContours(combined_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

            if contours:
                areas = [cv2.contourArea(c) for c in contours]
                max_c = max(areas)
                print(f"  Frame {frame_idx}: {orange_pixels} orange px ({orange_pixels/total_pixels*100:.2f}%), "
                      f"{len(contours)} contours, max_area={max_c:.0f} (need >{min_area})")

                # Show contours that are close to passing
                for i, cnt in enumerate(contours):
                    area = cv2.contourArea(cnt)
                    if area > min_area * 0.3:  # Show anything close
                        x, y, bw, bh = cv2.boundingRect(cnt)
                        aspect = bw / bh if bh > 0 else 0
                        perimeter = cv2.arcLength(cnt, True)
                        circularity = 4 * np.pi * area / (perimeter * perimeter) if perimeter > 0 else 0
                        print(f"    Contour {i}: area={area:.0f} bbox=({x},{y},{bw},{bh}) "
                              f"aspect={aspect:.2f} circ={circularity:.2f} "
                              f"{'PASS' if area >= min_area else 'TOO SMALL'}")
            else:
                print(f"  Frame {frame_idx}: {orange_pixels} orange px, 0 contours")

        frame_idx += 1

    cap.release()

if __name__ == '__main__':
    import glob
    videos = glob.glob('D:/Projects/basketball-analyzer/data/uploads/*shooting*.mp4')[:1]
    if not videos:
        videos = glob.glob('D:/Projects/basketball-analyzer/data/uploads/*.mp4')[:1]
    for v in videos:
        debug_color(v, max_frames=20)
