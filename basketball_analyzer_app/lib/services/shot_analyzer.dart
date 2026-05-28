import 'dart:math';
import 'dart:typed_data';
import '../models/models.dart';
import 'hoop_detector.dart';
import 'color_ball_detector.dart';
import 'shot_detector.dart';
import 'trajectory_analyzer.dart';

/// 投篮分析器 — 整合检测、跟踪、轨迹分析、命中判定
/// 对应 Python services/shot_analyzer.py ShotAnalyzer
class ShotAnalyzer {
  final hoopDetector = HoopDetector();
  final colorDetector = ColorBallDetector();
  final ShotDetector shotDetector;
  final TrajectoryAnalyzer trajectoryAnalyzer = TrajectoryAnalyzer();

  int _shotCounter = 0;
  (int, int)? _hoopPosition;

  ShotAnalyzer({double fps = 30.0}) : shotDetector = ShotDetector(fps: fps);

  void reset() {
    hoopDetector.reset();
    shotDetector.reset();
    _shotCounter = 0;
  }

  /// 处理一帧
  /// [frameBgr] BGR 格式图像数据
  void processFrame(Uint8List frameBgr, int width, int height, int frameIndex) {
    // 颜色检测球
    final ballDetections = colorDetector.detect(frameBgr, width, height);

    // 篮筐检测
    final hoopPos = hoopDetector.detect(frameBgr, width, height);
    if (hoopPos != null && hoopDetector.hoopBox != null) {
      final (hx, hy, hw, hh) = hoopDetector.hoopBox!;
      shotDetector.updateHoop(hx, hy, w: hw, h: hh);
      _hoopPosition = hoopPos;

      trajectoryAnalyzer.updateHoopReference(
        (hoopPos.$1.toDouble(), hoopPos.$2.toDouble()),
        hw.toDouble(),
      );
    }

    // 提取球位置数据 — 每帧只保留最佳候选
    final ballPositions = <(double, double)>[];
    final ballSizes = <double>[];
    final ballConfs = <double>[];

    if (ballDetections.isNotEmpty) {
      // 选择面积最大的检测（篮球通常是最大的橙色区域）
      var best = ballDetections.first;
      for (final det in ballDetections.skip(1)) {
        final bestArea = (best.$3 - best.$1) * (best.$4 - best.$2);
        final detArea = (det.$3 - det.$1) * (det.$4 - det.$2);
        if (detArea > bestArea) best = det;
      }
      final (x1, y1, x2, y2, conf) = best;
      final cx = (x1 + x2) / 2;
      final cy = (y1 + y2) / 2;
      final area = (x2 - x1) * (y2 - y1);
      ballPositions.add((cx, cy));
      ballSizes.add(area);
      ballConfs.add(conf);
    }

    // ShotDetector 处理
    shotDetector.processFrame(
      ballPositions,
      ballSizes,
      ballConfs,
      frameIndex: frameIndex,
    );
  }

  /// 构建分析结果
  AnalysisResult buildResult(int totalFrames, double fps) {
    final shotResults = shotDetector.shotResults;
    final shots = <ShotEvent>[];

    for (int i = 0; i < shotResults.length; i++) {
      final sr = shotResults[i];
      final positions = shotDetector.shotBallPositions[i] ?? [];

      // 构建轨迹
      final track = BallTrack(trackId: i);
      final shotFrame = sr.frame;
      final lookback = (2.0 * shotDetector.fps).round();
      final startFrame = max(0, shotFrame - lookback);

      final segment = positions
          .where((p) => p.$3 >= startFrame && p.$3 <= shotFrame)
          .toList();
      final useSegment = segment.length >= 2
          ? segment
          : (positions.length >= 2
              ? positions.sublist(max(0, positions.length - 30))
              : positions);

      for (final (cx, cy, frame, w, h, conf) in useSegment) {
        track.addPoint(frame, cx, cy,
            confidence: conf, ballArea: w * h);
      }

      // 轨迹拟合
      TrajectoryParams? trajectory;
      double distance = 0.0;
      double releaseAngle = 0.0;
      double entryAngle = 0.0;
      double trajConfidence = 0.0;
      String shotType = 'mid_range';

      if (track.length >= 2) {
        trajectory = trajectoryAnalyzer.fitTrajectory(track);
        if (trajectory != null) {
          distance = trajectory.estimatedDistance;
          releaseAngle = trajectory.releaseAngle;
          entryAngle = trajectory.entryAngle;
          trajConfidence = trajectory.fitRSquared;
          shotType = trajectoryAnalyzer.classifyShotType(trajectory);
        } else {
          distance = _fallbackDistance(track);
          shotType = trajectoryAnalyzer.classifyShotType(null,
              fallbackDistance: distance);
        }
      }

      // 角度合理性校验
      if (releaseAngle > 75 || releaseAngle < 15) releaseAngle = 0.0;
      if (entryAngle > 80 || entryAngle < 10) entryAngle = 0.0;

      final trajPoints =
          track.points.map((p) => (p.x, p.y)).toList();

      _shotCounter++;
      shots.add(ShotEvent(
        shotId: _shotCounter,
        frameStart: max(0, sr.frame - (1.5 * fps).round()),
        frameEnd: sr.frame,
        shotType: shotType,
        made: sr.made,
        distance: distance,
        releaseAngle: releaseAngle,
        entryAngle: entryAngle,
        trajectoryPoints: trajPoints,
        confidence: max(trajConfidence, sr.confidence),
        hoopX: sr.hoopX,
        flightTime: trajectory?.flightTime ?? 0.0,
        shotSpeed: trajectory?.shotSpeed ?? 0.0,
        arcHeight: trajectory?.arcHeight ?? 0.0,
      ));
    }

    return AnalysisResult(
      totalFrames: totalFrames,
      fps: fps,
      shots: shots,
    );
  }

  double _fallbackDistance(BallTrack track) {
    // 方法 1: 球像素大小
    final distance = trajectoryAnalyzer.estimateDistance(track);
    if (distance > 0) return distance;

    if (track.points.isEmpty) return 0.0;

    // 方法 2: 篮筐宽度换算
    final hoopW = trajectoryAnalyzer.hoopPixelWidth;
    final hoopPos = trajectoryAnalyzer.hoopPosition ??
        (_hoopPosition != null
            ? (_hoopPosition!.$1.toDouble(), _hoopPosition!.$2.toDouble())
            : null);

    if (hoopW > 0 && hoopPos != null) {
      final mpp = CourtDimensions.rimDiameter / hoopW;
      final start = track.points.first;
      final pixelDist = sqrt(
          (start.x - hoopPos.$1) * (start.x - hoopPos.$1) +
              (start.y - hoopPos.$2) * (start.y - hoopPos.$2));
      return (pixelDist * mpp).clamp(0.5, 10.0);
    }

    // 方法 3: 轨迹跨度
    final xs = track.points.map((p) => p.x).toList();
    final span = xs.reduce(max) - xs.reduce(min);
    if (span > 0) return (span * 0.025).clamp(0.5, 8.0);

    return 0.0;
  }

  Map<String, String> getCurrentStats() {
    final total = shotDetector.totalShots;
    final made = shotDetector.totalMade;
    return {
      '投篮': '$total',
      '命中': '$made',
      '命中率': total > 0 ? '${(made / total * 100).round()}%' : '0%',
      '篮筐': hoopDetector.isCalibrated ? '已锁定' : '搜索中',
    };
  }
}
