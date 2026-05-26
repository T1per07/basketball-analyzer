"""基准测试自动化回归脚本

用法:
    python tests/benchmark/run_benchmark.py [--update-baseline] [--video NAME]

功能:
    1. 遍历 tests/benchmark/videos/ 下所有视频
    2. 运行分析，输出统计表格
    3. 对比 baseline.json 基准，生成差异报告
    4. 退出码: 0=全部通过, 1=有回归, 2=运行错误
"""
import sys
import json
import time
import argparse
from pathlib import Path
from datetime import datetime

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "backend"))

import cv2
from services.video_processor import VideoProcessor, VideoInfo
from config.settings import config


BENCHMARK_DIR = Path(__file__).resolve().parent
VIDEOS_DIR = BENCHMARK_DIR / "videos"
BASELINE_PATH = BENCHMARK_DIR / "baseline.json"
REPORTS_DIR = BENCHMARK_DIR / "reports"


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
    info = get_video_info(video_path)
    processor = VideoProcessor(fps=info.fps)

    start = time.time()
    result = processor.analyzer.shot_detector  # placeholder for reset
    processor.analyzer.reset()

    cap = cv2.VideoCapture(video_path)
    frame_index = 0
    skip = max(1, int(info.fps / config.video.target_process_fps))
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        if frame_index % skip == 0:
            processor.analyzer.process_frame(frame, frame_index)
        frame_index += 1
    cap.release()
    result = processor.analyzer.build_result(frame_index, info.fps)
    elapsed = time.time() - start

    angles = [s.release_angle for s in result.shots if s.release_angle > 0]
    distances = [s.distance for s in result.shots if s.distance > 0]
    type_stats = result.get_stats_by_type()

    return {
        "video": Path(video_path).name,
        "resolution": f"{info.width}x{info.height}",
        "src_fps": info.fps,
        "duration": round(info.duration, 1),
        "total_frames": info.total_frames,
        "process_time_s": round(elapsed, 1),
        "process_fps": round(frame_index / elapsed, 1) if elapsed > 0 else 0,
        "total_shots": result.total_shots,
        "made_shots": result.made_shots,
        "percentage": round(result.overall_percentage, 4),
        "avg_distance_m": round(result.average_distance, 2),
        "distance_range": [round(min(distances), 1), round(max(distances), 1)] if distances else [0, 0],
        "zero_distance_count": sum(1 for s in result.shots if s.distance == 0),
        "bad_angle_count": sum(1 for s in result.shots if s.release_angle != 0 and (s.release_angle > 75 or s.release_angle < 15)),
        "avg_angle": round(sum(angles) / len(angles), 1) if angles else 0,
        "type_breakdown": {
            k: {"attempts": v["attempts"], "made": v["made"], "avg_distance": round(v["avg_distance"], 1)}
            for k, v in type_stats.items()
        },
    }


def load_baseline() -> dict:
    if not BASELINE_PATH.exists():
        return {}
    with open(BASELINE_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def save_baseline(results: list[dict]):
    baseline = {
        "version": "1.0.0",
        "created": datetime.now().strftime("%Y-%m-%d"),
        "description": "基准测试集 - 自动生成",
        "tolerance": {
            "total_shots_max_diff": 5,
            "percentage_max_diff": 0.05,
            "zero_distance_max": 0,
            "bad_angle_max": 0,
            "distance_max_diff_pct": 0.15,
        },
        "videos": {},
    }
    for r in results:
        baseline["videos"][r["video"]] = {
            "category": "primary",
            "resolution": r["resolution"],
            "fps": r["src_fps"],
            "duration_s": r["duration"],
            "expected": {
                "total_shots": r["total_shots"],
                "made_shots": r["made_shots"],
                "percentage": r["percentage"],
                "avg_distance_m": r["avg_distance_m"],
                "distance_range": r["distance_range"],
                "zero_distance_count": r["zero_distance_count"],
                "bad_angle_count": r["bad_angle_count"],
                "type_breakdown": {
                    k: {"min_attempts": max(0, v["attempts"] - 5), "max_attempts": v["attempts"] + 5}
                    for k, v in r["type_breakdown"].items()
                },
            },
        }
    with open(BASELINE_PATH, "w", encoding="utf-8") as f:
        json.dump(baseline, f, indent=2, ensure_ascii=False)
    print(f"\n基线已更新: {BASELINE_PATH}")


def check_regression(actual: dict, baseline: dict) -> list[str]:
    """对比实际结果与基线，返回差异列表"""
    issues = []
    name = actual["video"]
    expected = baseline.get("videos", {}).get(name)
    if not expected:
        issues.append(f"[NEW] {name} — 新视频，无基线对照")
        return issues

    exp = expected["expected"]
    tol = baseline.get("tolerance", {})

    # 投篮数差异
    shot_diff = abs(actual["total_shots"] - exp["total_shots"])
    max_shot_diff = tol.get("total_shots_max_diff", 5)
    if shot_diff > max_shot_diff:
        issues.append(
            f"[REGRESSION] {name} 投篮数: {actual['total_shots']} (基线 {exp['total_shots']}, 差 {shot_diff})"
        )

    # 零距离
    if actual["zero_distance_count"] > tol.get("zero_distance_max", 0):
        issues.append(
            f"[REGRESSION] {name} 零距离: {actual['zero_distance_count']} (基线要求 ≤{tol.get('zero_distance_max', 0)})"
        )

    # 坏角
    if actual["bad_angle_count"] > tol.get("bad_angle_max", 0):
        issues.append(
            f"[REGRESSION] {name} 坏角: {actual['bad_angle_count']} (基线要求 ≤{tol.get('bad_angle_max', 0)})"
        )

    # 命中率差异
    pct_diff = abs(actual["percentage"] - exp["percentage"])
    if pct_diff > tol.get("percentage_max_diff", 0.05):
        issues.append(
            f"[REGRESSION] {name} 命中率: {actual['percentage']:.1%} (基线 {exp['percentage']:.1%}, 差 {pct_diff:.1%})"
        )

    # 平均距离差异
    if exp["avg_distance_m"] > 0:
        dist_diff_pct = abs(actual["avg_distance_m"] - exp["avg_distance_m"]) / exp["avg_distance_m"]
        if dist_diff_pct > tol.get("distance_max_diff_pct", 0.15):
            issues.append(
                f"[REGRESSION] {name} 均距: {actual['avg_distance_m']}m (基线 {exp['avg_distance_m']}m, 差 {dist_diff_pct:.0%})"
            )

    return issues


def print_results_table(results: list[dict]):
    print("\n" + "=" * 100)
    print("基准测试结果")
    print("=" * 100)
    header = f"{'视频':<30} {'投篮':>5} {'命中':>5} {'命中率':>7} {'均距':>8} {'零距':>5} {'坏角':>5} {'角度':>6} {'耗时':>8} {'帧率':>6}"
    print(header)
    print("-" * len(header))
    for r in results:
        print(
            f"{r['video']:<30} {r['total_shots']:>5} {r['made_shots']:>5} "
            f"{r['percentage']:>7.1%} {r['avg_distance_m']:>7.1f}m "
            f"{r['zero_distance_count']:>5} {r['bad_angle_count']:>5} "
            f"{r['avg_angle']:>5.1f}° {r['process_time_s']:>7.1f}s {r['process_fps']:>5.1f}"
        )

    print("\n按类型:")
    for r in results:
        types = r.get("type_breakdown", {})
        parts = [f"{k}:{v['attempts']}投{v['made']}中({v['avg_distance']}m)" for k, v in types.items()]
        print(f"  {r['video']:<28} {', '.join(parts)}")


def print_regression_report(all_issues: list[str]):
    if not all_issues:
        print("\n✅ 回归测试通过 — 无差异")
        return
    print(f"\n❌ 发现 {len(all_issues)} 个回归问题:")
    for issue in all_issues:
        print(f"  {issue}")


def main():
    parser = argparse.ArgumentParser(description="篮球分析基准测试")
    parser.add_argument("--update-baseline", action="store_true", help="更新基线")
    parser.add_argument("--video", type=str, help="只测试指定视频")
    args = parser.parse_args()

    videos = sorted(VIDEOS_DIR.glob("*.mp4"))
    if args.video:
        videos = [v for v in videos if args.video in v.name]
    if not videos:
        print("未找到测试视频")
        return 2

    print(f"找到 {len(videos)} 个测试视频")
    print(f"基线文件: {BASELINE_PATH}")

    results = []
    for vpath in videos:
        print(f"\n分析: {vpath.name} ...", end=" ", flush=True)
        try:
            r = analyze_video(str(vpath))
            results.append(r)
            print(f"OK ({r['total_shots']}投{r['made_shots']}中, {r['process_fps']}fps)")
        except Exception as e:
            print(f"ERROR: {e}")
            import traceback
            traceback.print_exc()

    print_results_table(results)

    if args.update_baseline:
        save_baseline(results)
        return 0

    baseline = load_baseline()
    if not baseline:
        print("\n⚠️  无基线文件，使用 --update-baseline 生成")
        return 0

    all_issues = []
    for r in results:
        issues = check_regression(r, baseline)
        all_issues.extend(issues)

    print_regression_report(all_issues)

    # 保存报告
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    report_path = REPORTS_DIR / f"report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump({
            "timestamp": datetime.now().isoformat(),
            "results": results,
            "regression_issues": all_issues,
            "passed": len(all_issues) == 0,
        }, f, indent=2, ensure_ascii=False)
    print(f"\n报告已保存: {report_path}")

    return 0 if len(all_issues) == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
