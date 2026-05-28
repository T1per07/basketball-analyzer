/// 单帧检测结果
/// 对应 Python models/detection.py DetectionResult
class BBox {
  final double x1, y1, x2, y2;
  final double confidence;
  final int classId;

  const BBox({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.confidence = 0.5,
    this.classId = 0,
  });

  double get cx => (x1 + x2) / 2;
  double get cy => (y1 + y2) / 2;
  double get width => x2 - x1;
  double get height => y2 - y1;
  double get area => width * height;
}

class DetectionResult {
  final List<BBox> ballDetections;
  final List<BBox> playerDetections;
  final List<BBox> hoopDetections;
  final (double, double)? hoopPosition;
  final (double, double, double, double)? hoopBox; // x, y, w, h
  final int frameIndex;

  const DetectionResult({
    this.ballDetections = const [],
    this.playerDetections = const [],
    this.hoopDetections = const [],
    this.hoopPosition,
    this.hoopBox,
    required this.frameIndex,
  });
}
