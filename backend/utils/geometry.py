"""几何计算工具"""
import math
import numpy as np


def euclidean_distance(p1: tuple[float, float], p2: tuple[float, float]) -> float:
    """计算两点欧氏距离"""
    return math.sqrt((p1[0] - p2[0]) ** 2 + (p1[1] - p2[1]) ** 2)


def angle_between_points(
    p1: tuple[float, float],
    p2: tuple[float, float],
    p3: tuple[float, float],
) -> float:
    """计算 p1-p2-p3 的角度（度）"""
    v1 = (p1[0] - p2[0], p1[1] - p2[1])
    v2 = (p3[0] - p2[0], p3[1] - p2[1])

    dot = v1[0] * v2[0] + v1[1] * v2[1]
    mag1 = math.sqrt(v1[0] ** 2 + v1[1] ** 2)
    mag2 = math.sqrt(v2[0] ** 2 + v2[1] ** 2)

    if mag1 == 0 or mag2 == 0:
        return 0.0

    cos_angle = dot / (mag1 * mag2)
    cos_angle = max(-1, min(1, cos_angle))  # clamp

    return math.degrees(math.acos(cos_angle))


def line_angle(p1: tuple[float, float], p2: tuple[float, float]) -> float:
    """计算两点连线与水平线的角度（度）"""
    dx = p2[0] - p1[0]
    dy = p2[1] - p1[1]
    return math.degrees(math.atan2(-dy, dx))  # 取负因为图像坐标 y 向下


def point_in_rect(
    point: tuple[float, float],
    rect: tuple[float, float, float, float],
) -> bool:
    """检查点是否在矩形内 (x1, y1, x2, y2)"""
    x, y = point
    x1, y1, x2, y2 = rect
    return x1 <= x <= x2 and y1 <= y <= y2


def bbox_center(bbox: tuple[float, float, float, float]) -> tuple[float, float]:
    """计算边界框中心"""
    x1, y1, x2, y2 = bbox
    return ((x1 + x2) / 2, (y1 + y2) / 2)


def bbox_area(bbox: tuple[float, float, float, float]) -> float:
    """计算边界框面积"""
    x1, y1, x2, y2 = bbox
    return abs(x2 - x1) * abs(y2 - y1)


def iou(bbox1: tuple[float, float, float, float], bbox2: tuple[float, float, float, float]) -> float:
    """计算两个边界框的 IoU"""
    x1 = max(bbox1[0], bbox2[0])
    y1 = max(bbox1[1], bbox2[1])
    x2 = min(bbox1[2], bbox2[2])
    y2 = min(bbox1[3], bbox2[3])

    intersection = max(0, x2 - x1) * max(0, y2 - y1)
    area1 = bbox_area(bbox1)
    area2 = bbox_area(bbox2)
    union = area1 + area2 - intersection

    return intersection / union if union > 0 else 0.0


def estimate_real_distance(
    pixel_diameter: float,
    real_diameter: float = 0.241,
    image_width: int = 1920,
    fov_degrees: float = 60,
) -> float:
    """
    基于物体像素尺寸估算真实距离
    Args:
        pixel_diameter: 物体在图像中的像素直径
        real_diameter: 物体真实直径（米），默认篮球 24.1cm
        image_width: 图像宽度
        fov_degrees: 相机视场角
    Returns:
        估算距离（米）
    """
    focal_length = (image_width / 2) / math.tan(math.radians(fov_degrees / 2))
    distance = (real_diameter * focal_length) / pixel_diameter
    return distance


def smooth_trajectory(
    points: list[tuple[float, float]],
    window_size: int = 5,
) -> list[tuple[float, float]]:
    """平滑轨迹点"""
    if len(points) < window_size:
        return points

    xs = [p[0] for p in points]
    ys = [p[1] for p in points]

    smoothed = []
    for i in range(len(points)):
        start = max(0, i - window_size // 2)
        end = min(len(points), i + window_size // 2 + 1)
        avg_x = sum(xs[start:end]) / (end - start)
        avg_y = sum(ys[start:end]) / (end - start)
        smoothed.append((avg_x, avg_y))

    return smoothed
