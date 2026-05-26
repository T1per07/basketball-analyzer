"""统计计算服务"""
from dataclasses import dataclass

import numpy as np

from services.shot_analyzer import ShotEvent, AnalysisResult
from config.settings import ShotType


@dataclass
class ShotLocation:
    """投篮位置（归一化坐标）"""
    x: float  # 0-1
    y: float  # 0-1
    made: bool
    shot_type: str
    distance: float


@dataclass
class ZoneStats:
    """区域统计"""
    zone_name: str
    attempts: int
    made: int
    percentage: float
    avg_distance: float


class StatsCalculator:
    """统计计算器"""

    # 球场区域定义（归一化坐标）
    ZONES = {
        "paint": {"x_range": (0.35, 0.65), "y_range": (0.5, 0.85)},
        "mid_range_left": {"x_range": (0.15, 0.35), "y_range": (0.3, 0.7)},
        "mid_range_right": {"x_range": (0.65, 0.85), "y_range": (0.3, 0.7)},
        "three_point_left": {"x_range": (0.0, 0.2), "y_range": (0.0, 0.5)},
        "three_point_right": {"x_range": (0.8, 1.0), "y_range": (0.0, 0.5)},
        "three_point_top": {"x_range": (0.25, 0.75), "y_range": (0.0, 0.25)},
        "corner_three_left": {"x_range": (0.0, 0.15), "y_range": (0.3, 0.7)},
        "corner_three_right": {"x_range": (0.85, 1.0), "y_range": (0.3, 0.7)},
    }

    def calculate_shot_locations(
        self,
        shots: list[ShotEvent],
        image_width: int,
        image_height: int,
    ) -> list[ShotLocation]:
        """计算投篮位置（归一化坐标）"""
        locations = []
        for shot in shots:
            if shot.trajectory_points:
                # 使用出手点位置
                start_point = shot.trajectory_points[0]
                x = start_point[0] / image_width
                y = start_point[1] / image_height
                locations.append(ShotLocation(
                    x=x,
                    y=y,
                    made=shot.made,
                    shot_type=shot.shot_type,
                    distance=shot.distance,
                ))
        return locations

    def calculate_zone_stats(self, locations: list[ShotLocation]) -> dict[str, ZoneStats]:
        """计算各区域统计"""
        zone_stats = {}

        for zone_name, zone_def in self.ZONES.items():
            x_min, x_max = zone_def["x_range"]
            y_min, y_max = zone_def["y_range"]

            zone_shots = [
                loc for loc in locations
                if x_min <= loc.x <= x_max and y_min <= loc.y <= y_max
            ]

            if zone_shots:
                made = sum(1 for s in zone_shots if s.made)
                zone_stats[zone_name] = ZoneStats(
                    zone_name=zone_name,
                    attempts=len(zone_shots),
                    made=made,
                    percentage=made / len(zone_shots),
                    avg_distance=np.mean([s.distance for s in zone_shots]),
                )

        return zone_stats

    def calculate_distance_distribution(self, shots: list[ShotEvent]) -> dict[str, int]:
        """计算距离分布"""
        bins = {
            "0-1m": 0,
            "1-2m": 0,
            "2-3m": 0,
            "3-4m": 0,
            "4-5m": 0,
            "5-6m": 0,
            "6-7m": 0,
            "7m+": 0,
        }

        for shot in shots:
            d = shot.distance
            if d < 1:
                bins["0-1m"] += 1
            elif d < 2:
                bins["1-2m"] += 1
            elif d < 3:
                bins["2-3m"] += 1
            elif d < 4:
                bins["3-4m"] += 1
            elif d < 5:
                bins["4-5m"] += 1
            elif d < 6:
                bins["5-6m"] += 1
            elif d < 7:
                bins["6-7m"] += 1
            else:
                bins["7m+"] += 1

        return bins

    def calculate_streak_stats(self, shots: list[ShotEvent]) -> dict:
        """计算连中/连失统计"""
        if not shots:
            return {"max_made_streak": 0, "max_missed_streak": 0}

        max_made = 0
        max_missed = 0
        current_made = 0
        current_missed = 0

        for shot in shots:
            if shot.made:
                current_made += 1
                current_missed = 0
                max_made = max(max_made, current_made)
            else:
                current_missed += 1
                current_made = 0
                max_missed = max(max_missed, current_missed)

        return {
            "max_made_streak": max_made,
            "max_missed_streak": max_missed,
        }

    def calculate_angle_stats(self, shots: list[ShotEvent]) -> dict:
        """计算出手角度统计"""
        angles = [s.release_angle for s in shots if s.release_angle > 0]
        if not angles:
            return {}

        return {
            "avg_release_angle": float(np.mean(angles)),
            "std_release_angle": float(np.std(angles)),
            "min_release_angle": float(np.min(angles)),
            "max_release_angle": float(np.max(angles)),
        }

    def generate_full_stats(self, result: AnalysisResult, image_width: int = 1920, image_height: int = 1080) -> dict:
        """生成完整统计报告（所有值转为原生 Python 类型）"""
        locations = self.calculate_shot_locations(result.shots, image_width, image_height)
        zone_stats = self.calculate_zone_stats(locations)
        distance_dist = self.calculate_distance_distribution(result.shots)
        streak_stats = self.calculate_streak_stats(result.shots)
        angle_stats = self.calculate_angle_stats(result.shots)
        type_stats = result.get_stats_by_type()

        return {
            "summary": {
                "total_shots": int(result.total_shots),
                "made_shots": int(result.made_shots),
                "overall_percentage": float(result.overall_percentage),
                "average_distance": float(result.average_distance),
                "video_duration": float(result.total_frames / result.fps) if result.fps > 0 else 0.0,
            },
            "by_type": {
                name: {k: float(v) if isinstance(v, (np.floating, np.integer)) else v for k, v in stats.items()}
                for name, stats in type_stats.items()
            },
            "by_zone": {
                name: {
                    "attempts": int(z.attempts),
                    "made": int(z.made),
                    "percentage": float(z.percentage),
                }
                for name, z in zone_stats.items()
            },
            "distance_distribution": distance_dist,
            "streaks": streak_stats,
            "angles": {k: float(v) for k, v in angle_stats.items()} if angle_stats else {},
            "shot_locations": [
                {"x": float(loc.x), "y": float(loc.y), "made": bool(loc.made), "type": str(loc.shot_type), "distance": float(loc.distance)}
                for loc in locations
            ],
        }
