"""批量测试脚本 - 对所有样本视频运行分析并汇总结果"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import cv2
from services.shot_analyzer import ShotAnalyzer
from services.video_processor import VideoProcessor, VideoInfo


def get_video_info(path: str) -> VideoInfo:
    cap = cv2.VideoCapture(path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    cap.release()
    return VideoInfo(path=path, width=w, height=h, fps=fps, total_frames=total,
                     duration=total / fps if fps > 0 else 0)


def analyze_video(video_path: str) -> dict:
    """分析单个视频，返回指标字典"""
    info = get_video_info(video_path)
    processor = VideoProcessor(fps=info.fps)

    start = time.time()
    result = processor.analyze_video(video_path)
    elapsed = time.time() - start

    # 汇总
    type_stats = result.get_stats_by_type()
    angles = [s.release_angle for s in result.shots if s.release_angle > 0]
    distances = [s.distance for s in result.shots if s.distance > 0]
    zero_dist = sum(1 for s in result.shots if s.distance == 0)
    bad_angle = sum(1 for s in result.shots if s.release_angle != 0 and (s.release_angle > 75 or s.release_angle < 15))

    return {
        "video": Path(video_path).name,
        "resolution": f"{info.width}x{info.height}",
        "src_fps": info.fps,
        "duration": f"{info.duration:.1f}s",
        "total_frames": info.total_frames,
        "process_time": f"{elapsed:.1f}s",
        "process_fps": f"{result.total_frames / elapsed:.1f}" if elapsed > 0 else "N/A",
        "total_shots": result.total_shots,
        "made_shots": result.made_shots,
        "percentage": f"{result.overall_percentage * 100:.1f}%",
        "avg_distance": f"{result.average_distance:.2f}m",
        "distance_range": f"{min(distances):.1f}-{max(distances):.1f}m" if distances else "N/A",
        "zero_dist_count": zero_dist,
        "bad_angle_count": bad_angle,
        "avg_angle": f"{sum(angles)/len(angles):.1f}°" if angles else "N/A",
        "type_breakdown": type_stats,
    }


def main():
    samples_dir = Path(__file__).resolve().parent.parent.parent / "data" / "samples"
    videos = sorted(samples_dir.glob("*.mp4"))

    if not videos:
        print("未找到样本视频")
        return

    print(f"找到 {len(videos)} 个样本视频\n")
    print("=" * 80)

    all_results = []
    for vpath in videos:
        print(f"\n正在分析: {vpath.name}")
        print("-" * 60)
        try:
            result = analyze_video(str(vpath))
            all_results.append(result)

            print(f"  分辨率: {result['resolution']}, 源帧率: {result['src_fps']}fps")
            print(f"  时长: {result['duration']}, 总帧数: {result['total_frames']}")
            print(f"  处理耗时: {result['process_time']}, 处理帧率: {result['process_fps']}fps")
            print(f"  总投篮: {result['total_shots']}, 命中: {result['made_shots']}, "
                  f"命中率: {result['percentage']}")
            print(f"  平均距离: {result['avg_distance']}, 范围: {result['distance_range']}")
            print(f"  零距离投篮: {result['zero_dist_count']}, 异常角度: {result['bad_angle_count']}")
            print(f"  平均出手角度: {result['avg_angle']}")

            if result['type_breakdown']:
                print("  按类型:")
                for t, s in result['type_breakdown'].items():
                    print(f"    {t}: {s['attempts']}投 {s['made']}中 "
                          f"({s['percentage']*100:.0f}%) 均距{s['avg_distance']:.1f}m")
        except Exception as e:
            print(f"  ERROR: {e}")
            import traceback
            traceback.print_exc()

    # 汇总表
    print("\n" + "=" * 80)
    print("汇总对比")
    print("=" * 80)
    header = f"{'视频':<30} {'投篮':>5} {'命中':>5} {'命中率':>7} {'均距':>8} {'零距':>5} {'坏角':>5} {'处理':>8}"
    print(header)
    print("-" * len(header))
    for r in all_results:
        print(f"{r['video']:<30} {r['total_shots']:>5} {r['made_shots']:>5} "
              f"{r['percentage']:>7} {r['avg_distance']:>8} "
              f"{r['zero_dist_count']:>5} {r['bad_angle_count']:>5} {r['process_time']:>8}")


if __name__ == "__main__":
    main()
