import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/services/hoop_detector.dart';

Uint8List _makeFrameWithHoop({
  int w = 640,
  int h = 480,
  required int hoopX,
  required int hoopY,
  int hoopW = 60,
  int hoopH = 20,
}) {
  final data = Uint8List(w * h * 3);
  // Dark background
  for (int i = 0; i < data.length; i += 3) {
    data[i] = 40;
    data[i + 1] = 50;
    data[i + 2] = 45;
  }
  // Red/orange hoop: R=180, G=50, B=30
  for (int dy = -(hoopH ~/ 2); dy <= hoopH ~/ 2; dy++) {
    for (int dx = -(hoopW ~/ 2); dx <= hoopW ~/ 2; dx++) {
      final px = (hoopX + dx).clamp(0, w - 1);
      final py = (hoopY + dy).clamp(0, h - 1);
      final idx = (py * w + px) * 3;
      data[idx] = 30;     // B
      data[idx + 1] = 50;  // G
      data[idx + 2] = 180; // R
    }
  }
  return data;
}

void main() {
  group('HoopDetector', () {
    late HoopDetector detector;

    setUp(() {
      detector = HoopDetector();
    });

    test('starts uncalibrated', () {
      expect(detector.isCalibrated, isFalse);
      expect(detector.hoopPosition, isNull);
      expect(detector.hoopBox, isNull);
    });

    test('calibrates after enough frames with hoop', () {
      for (int i = 0; i < 20; i++) {
        final frame = _makeFrameWithHoop(hoopX: 320, hoopY: 150);
        detector.detect(frame, 640, 480);
      }
      expect(detector.isCalibrated, isTrue);
      expect(detector.hoopPosition, isNotNull);
    });

    test('calibration timeout uses partial data', () {
      // Only 5 frames with hoop (less than _calibFrames=12)
      for (int i = 0; i < 5; i++) {
        final frame = _makeFrameWithHoop(hoopX: 320, hoopY: 150);
        detector.detect(frame, 640, 480);
      }
      // After 60 attempts with partial data, should calibrate
      for (int i = 0; i < 60; i++) {
        final frame = _makeFrameWithHoop(hoopX: 320, hoopY: 150);
        detector.detect(frame, 640, 480);
      }
      expect(detector.isCalibrated, isTrue);
    });

    test('tracks hoop position after calibration', () {
      // Calibrate
      for (int i = 0; i < 20; i++) {
        final frame = _makeFrameWithHoop(hoopX: 320, hoopY: 150);
        detector.detect(frame, 640, 480);
      }
      expect(detector.isCalibrated, isTrue);

      final pos1 = detector.hoopPosition;
      expect(pos1, isNotNull);

      // Track with slightly moved hoop
      for (int i = 0; i < 5; i++) {
        final frame = _makeFrameWithHoop(hoopX: 325, hoopY: 152);
        detector.detect(frame, 640, 480);
      }

      final pos2 = detector.hoopPosition;
      expect(pos2, isNotNull);
      // Position should be close to original (EMA tracking)
      expect((pos2!.$1 - pos1!.$1).abs(), lessThan(20));
    });

    test('reset clears calibration state', () {
      for (int i = 0; i < 20; i++) {
        final frame = _makeFrameWithHoop(hoopX: 320, hoopY: 150);
        detector.detect(frame, 640, 480);
      }
      expect(detector.isCalibrated, isTrue);

      detector.reset();
      expect(detector.isCalibrated, isFalse);
      expect(detector.hoopPosition, isNull);
    });
  });
}
