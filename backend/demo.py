"""
Demo 脚本 - 测试投篮分析引擎
用法:
  python demo.py <video_path>           # 分析单个视频
  python demo.py --all                  # 分析所有样本视频
  python demo.py --debug <video_path>   # 调试模式，输出检测框视频
"""
import sys
import time
from pathlib import Path

import cv2

from services.video_processor import VideoProcessor
from services.stats_calculator import StatsCalculator
from config.settings import config


SAMPLES_DIR = Path(__file__).parent.parent / "data" / "samples"
OUTPUT_DIR = Path(__file__).parent.parent / "data" / "output"


def analyze_single(video_path: str, debug: bool = False):
    """分析单个视频"""
    if not Path(video_path).exists():
        print(f"视频文件不存在: {video_path}")
        return None

    print(f"\n{'='*60}")
    print(f"正在分析: {video_path}")
    print(f"配置: 模型={config.detection.ball_model_name}, "
          f"跳帧={config.detection.skip_frames}, "
          f"输入宽度={config.detection.input_width}px")
    print(f"{'='*60}")

    processor = VideoProcessor()
    stats_calc = StatsCalculator()

    info = processor.get_video_info(video_path)
    print(f"视频信息:")
    print(f"  分辨率: {info.width}x{info.height}")
    print(f"  帧率: {info.fps:.1f} fps")
    print(f"  总帧数: {info.total_frames}")
    print(f"  时长: {info.duration:.1f} 秒")
    print()

    start_time = time.time()

    def progress(current, total):
        pct = current / total * 100
        print(f"\r分析进度: {pct:.1f}% ({current}/{total})", end="", flush=True)

    result = processor.analyze_video(video_path, progress)
    elapsed = time.time() - start_time
    print(f"\n分析完成! 耗时: {elapsed:.1f} 秒")
    print()

    # 生成统计
    stats = stats_calc.generate_full_stats(result, info.width, info.height)

    # 输出结果
    print(f"{'='*60}")
    print("投篮统计结果")
    print(f"{'='*60}")

    summary = stats["summary"]
    print(f"总投篮数: {summary['total_shots']}")
    print(f"命中数: {summary['made_shots']}")
    print(f"命中率: {summary['overall_percentage']:.1%}")
    print(f"平均距离: {summary['average_distance']:.1f} 米")
    print()

    if stats["by_type"]:
        print("按投篮类型:")
        for shot_type, type_stats in stats["by_type"].items():
            print(f"  {shot_type}:")
            print(f"    投篮: {type_stats['attempts']}, 命中: {type_stats['made']}")
            print(f"    命中率: {type_stats['percentage']:.1%}")
        print()

    if stats["angles"]:
        angles = stats["angles"]
        print("出手角度:")
        print(f"  平均: {angles['avg_release_angle']:.1f}°")
        print(f"  范围: {angles['min_release_angle']:.1f}° - {angles['max_release_angle']:.1f}°")
        print()

    # 打印每次投篮详情
    print("投篮详情:")
    for shot in result.shots:
        status = "✓ 命中" if shot.made else "✗ 未中"
        print(f"  #{shot.shot_id}: {status}, 类型={shot.shot_type}, "
              f"帧={shot.frame_end}, 置信度={shot.confidence:.2f}")

    # 调试模式：输出检测框视频
    if debug:
        output_path = str(OUTPUT_DIR / f"debug_{Path(video_path).stem}.mp4")
        print(f"\n正在生成调试视频: {output_path}")
        processor.debug_detection(video_path, output_path, max_frames=500)
        print(f"调试视频已保存: {output_path}")

    return stats


def analyze_all():
    """分析所有样本视频"""
    video_extensions = {".mp4", ".avi", ".mov", ".mkv"}
    videos = [
        f for f in SAMPLES_DIR.iterdir()
        if f.suffix.lower() in video_extensions
    ]

    if not videos:
        print(f"未找到样本视频: {SAMPLES_DIR}")
        return

    print(f"找到 {len(videos)} 个样本视频:")
    for v in videos:
        print(f"  - {v.name}")
    print()

    all_results = []
    for video in videos:
        stats = analyze_single(str(video))
        if stats:
            all_results.append((video.name, stats))

    # 汇总
    if all_results:
        print(f"\n{'='*60}")
        print("汇总统计")
        print(f"{'='*60}")
        total_shots = sum(r[1]["summary"]["total_shots"] for r in all_results)
        total_made = sum(r[1]["summary"]["made_shots"] for r in all_results)
        print(f"总视频数: {len(all_results)}")
        print(f"总投篮数: {total_shots}")
        print(f"总命中数: {total_made}")
        if total_shots > 0:
            print(f"总命中率: {total_made/total_shots:.1%}")


def main():
    if len(sys.argv) < 2:
        print("用法:")
        print("  python demo.py <video_path>           # 分析单个视频")
        print("  python demo.py --all                  # 分析所有样本视频")
        print("  python demo.py --debug <video_path>   # 调试模式")
        print()
        print("当前配置:")
        print(f"  模型: {config.detection.ball_model_name}")
        print(f"  跳帧: 每 {config.detection.skip_frames} 帧处理一次")
        print(f"  输入宽度: {config.detection.input_width}px")
        print(f"  颜色检测: {'启用' if config.detection.enable_color_detection else '禁用'}")
        print(f"  运动检测: {'启用' if config.detection.enable_motion_detection else '禁用'}")
        sys.exit(1)

    if sys.argv[1] == "--all":
        analyze_all()
    elif sys.argv[1] == "--debug":
        if len(sys.argv) < 3:
            print("用法: python demo.py --debug <video_path>")
            sys.exit(1)
        analyze_single(sys.argv[2], debug=True)
    else:
        analyze_single(sys.argv[1])


if __name__ == "__main__":
    main()
