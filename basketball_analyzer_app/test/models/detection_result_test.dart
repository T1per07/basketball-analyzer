import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/models/detection_result.dart';

void main() {
  group('BBox', () {
    test('computed properties are correct', () {
      const box = BBox(x1: 10, y1: 20, x2: 50, y2: 60, confidence: 0.8, classId: 1);
      expect(box.cx, 30.0);
      expect(box.cy, 40.0);
      expect(box.width, 40.0);
      expect(box.height, 40.0);
      expect(box.area, 1600.0);
    });

    test('zero-size box has zero area', () {
      const box = BBox(x1: 5, y1: 5, x2: 5, y2: 5);
      expect(box.area, 0.0);
      expect(box.width, 0.0);
      expect(box.height, 0.0);
    });

    test('default confidence is 0.5', () {
      const box = BBox(x1: 0, y1: 0, x2: 10, y2: 10);
      expect(box.confidence, 0.5);
      expect(box.classId, 0);
    });
  });

  group('DetectionResult', () {
    test('empty detection result has no detections', () {
      const result = DetectionResult(frameIndex: 0);
      expect(result.ballDetections, isEmpty);
      expect(result.playerDetections, isEmpty);
      expect(result.hoopDetections, isEmpty);
      expect(result.hoopPosition, isNull);
      expect(result.hoopBox, isNull);
    });

    test('detection result with hoop position', () {
      const result = DetectionResult(
        frameIndex: 10,
        hoopPosition: (320.0, 120.0),
        hoopBox: (290.0, 105.0, 60.0, 30.0),
      );
      expect(result.hoopPosition, (320.0, 120.0));
      expect(result.hoopBox, (290.0, 105.0, 60.0, 30.0));
    });

    test('detection result with ball detections', () {
      const result = DetectionResult(
        frameIndex: 5,
        ballDetections: [
          BBox(x1: 100, y1: 200, x2: 120, y2: 220, confidence: 0.9),
          BBox(x1: 300, y1: 400, x2: 310, y2: 410, confidence: 0.3),
        ],
      );
      expect(result.ballDetections.length, 2);
      expect(result.ballDetections[0].confidence, 0.9);
      expect(result.ballDetections[1].classId, 0);
    });
  });
}
