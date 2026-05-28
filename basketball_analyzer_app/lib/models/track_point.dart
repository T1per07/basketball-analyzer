/// 轨迹点 — 对应 Python models/tracking.py TrackPoint
class TrackPoint {
  final int frameIndex;
  final double x;
  final double y;
  final double confidence;
  final bool predicted;
  final double ballArea;

  const TrackPoint({
    required this.frameIndex,
    required this.x,
    required this.y,
    this.confidence = 1.0,
    this.predicted = false,
    this.ballArea = 0.0,
  });
}
