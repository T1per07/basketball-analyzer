import 'config.dart';

/// 投篮检测结果 — 对应 Python shot_detector.py ShotResult
class ShotResult {
  final bool made;
  final int frame;
  final int hoopX;
  final int hoopWidth;
  final int ballId;
  final double confidence;
  final bool hasApex;
  final bool rimOverlap;
  final double entryAngle;
  final double releaseAngle;

  const ShotResult({
    required this.made,
    required this.frame,
    this.hoopX = 0,
    this.hoopWidth = 0,
    this.ballId = 0,
    this.confidence = 0.0,
    this.hasApex = false,
    this.rimOverlap = false,
    this.entryAngle = 0.0,
    this.releaseAngle = 0.0,
  });
}

/// 一次投篮事件 — 对应 Python shot_analyzer.py ShotEvent
class ShotEvent {
  final int shotId;
  final int trackId;
  final int frameStart;
  final int frameEnd;
  final String shotType;
  final bool made;
  final double distance;
  final double releaseAngle;
  final double entryAngle;
  final List<(double, double)> trajectoryPoints;
  final double confidence;
  final double crossingX;
  final int hoopX;

  // 运动学参数
  final double flightTime;
  final double shotSpeed;
  final double arcHeight;

  const ShotEvent({
    required this.shotId,
    this.trackId = 0,
    required this.frameStart,
    required this.frameEnd,
    required this.shotType,
    required this.made,
    required this.distance,
    this.releaseAngle = 0.0,
    this.entryAngle = 0.0,
    this.trajectoryPoints = const [],
    this.confidence = 0.0,
    this.crossingX = 0.0,
    this.hoopX = 0,
    this.flightTime = 0.0,
    this.shotSpeed = 0.0,
    this.arcHeight = 0.0,
  });
}

/// 完整分析结果
class AnalysisResult {
  final int totalFrames;
  final double fps;
  final List<ShotEvent> shots;

  const AnalysisResult({
    required this.totalFrames,
    required this.fps,
    this.shots = const [],
  });

  int get totalShots => shots.length;
  int get madeShots => shots.where((s) => s.made).length;
  double get overallPercentage =>
      totalShots > 0 ? madeShots / totalShots : 0.0;

  double get averageDistance {
    final distances = shots.where((s) => s.distance > 0).map((s) => s.distance);
    return distances.isNotEmpty
        ? distances.reduce((a, b) => a + b) / distances.length
        : 0.0;
  }

  Map<String, Map<String, dynamic>> getStatsByType() {
    final stats = <String, Map<String, dynamic>>{};
    for (final type in ShotType.values) {
      final typeShots =
          shots.where((s) => s.shotType == type.value).toList();
      if (typeShots.isNotEmpty) {
        final made = typeShots.where((s) => s.made).length;
        stats[type.value] = {
          'attempts': typeShots.length,
          'made': made,
          'percentage': made / typeShots.length,
          'avg_distance': typeShots
                  .map((s) => s.distance)
                  .reduce((a, b) => a + b) /
              typeShots.length,
        };
      }
    }
    return stats;
  }
}
