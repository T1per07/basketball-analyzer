import 'track_point.dart';

/// 篮球轨迹（带 Kalman 预测）
/// 对应 Python models/tracking.py BallTrack
class BallTrack {
  final int trackId;
  final List<TrackPoint> points = [];

  // Kalman 状态（简化的 4 维：x, y, vx, vy）
  double _stateX = 0, _stateY = 0, _stateVx = 0, _stateVy = 0;
  bool _kfInitialized = false;
  int _lastRealFrame = -1;

  BallTrack({required this.trackId});

  void addPoint(int frameIndex, double x, double y,
      {double confidence = 1.0, double ballArea = 0.0}) {
    if (!_kfInitialized) {
      _stateX = x;
      _stateY = y;
      _stateVx = 0;
      _stateVy = 0;
      _kfInitialized = true;
    } else {
      // Kalman predict + correct (简化版)
      _stateVx = (x - _stateX);
      _stateVy = (y - _stateY);
      _stateX = x;
      _stateY = y;
    }

    points.add(TrackPoint(
      frameIndex: frameIndex,
      x: x,
      y: y,
      confidence: confidence,
      predicted: false,
      ballArea: ballArea,
    ));
    _lastRealFrame = frameIndex;
  }

  /// 遮挡期间预测球的位置（最多预测 10 帧）
  (double, double)? predictPosition(int frameIndex) {
    if (!_kfInitialized || _lastRealFrame < 0) return null;
    final framesLost = frameIndex - _lastRealFrame;
    if (framesLost <= 0 || framesLost > 10) return null;

    final px = _stateX + _stateVx * framesLost;
    final py = _stateY + _stateVy * framesLost;
    return (px, py);
  }

  void addPredictedPoint(int frameIndex, double x, double y) {
    points.add(TrackPoint(
      frameIndex: frameIndex,
      x: x,
      y: y,
      confidence: 0.3,
      predicted: true,
    ));
  }

  List<(double, double)> get positions =>
      points.map((p) => (p.x, p.y)).toList();

  List<int> get frameIndices => points.map((p) => p.frameIndex).toList();

  int get length => points.length;

  (double, double)? getCenterAt(int frameIndex) {
    for (final p in points) {
      if (p.frameIndex == frameIndex) return (p.x, p.y);
    }
    return null;
  }
}
