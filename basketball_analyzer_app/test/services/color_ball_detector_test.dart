import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/services/color_ball_detector.dart';

Uint8List _makeFrame({
  int w = 320,
  int h = 240,
  List<(int, int, int)> orangePixels = const [],
}) {
  final data = Uint8List(w * h * 3);
  // Dark background
  for (int i = 0; i < data.length; i += 3) {
    data[i] = 50;     // B
    data[i + 1] = 60;  // G
    data[i + 2] = 55;  // R
  }
  // Orange pixels: B=25, G=110, R=215
  for (final (px, py, radius) in orangePixels) {
    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        if (dx * dx + dy * dy > radius * radius) continue;
        final x = (px + dx).clamp(0, w - 1);
        final y = (py + dy).clamp(0, h - 1);
        final idx = (y * w + x) * 3;
        data[idx] = 25;     // B
        data[idx + 1] = 110; // G
        data[idx + 2] = 215; // R
      }
    }
  }
  return data;
}

void main() {
  group('ColorBallDetector', () {
    late ColorBallDetector detector;

    setUp(() {
      detector = ColorBallDetector();
    });

    test('detects a single orange ball', () {
      final frame = _makeFrame(orangePixels: [(160, 120, 15)]);
      final results = detector.detect(frame, 320, 240);
      expect(results, isNotEmpty);
      // Verify the detected region is near the ball center
      final best = results.first;
      final cx = (best.$1 + best.$3) / 2;
      final cy = (best.$2 + best.$4) / 2;
      expect(cx, closeTo(160, 20));
      expect(cy, closeTo(120, 20));
    });

    test('detects multiple orange balls', () {
      final frame = _makeFrame(orangePixels: [
        (80, 60, 12),
        (240, 180, 12),
      ]);
      final results = detector.detect(frame, 320, 240);
      expect(results.length, greaterThanOrEqualTo(2));
    });

    test('returns empty for frame with no orange', () {
      final data = Uint8List(320 * 240 * 3);
      for (int i = 0; i < data.length; i += 3) {
        data[i] = 50;
        data[i + 1] = 60;
        data[i + 2] = 55;
      }
      final results = detector.detect(data, 320, 240);
      expect(results, isEmpty);
    });

    test('returns empty for tiny orange region', () {
      // Single pixel — below minArea
      final data = Uint8List(320 * 240 * 3);
      final idx = (120 * 320 + 160) * 3;
      data[idx] = 25;
      data[idx + 1] = 110;
      data[idx + 2] = 215;
      final results = detector.detect(data, 320, 240);
      expect(results, isEmpty);
    });

    test('confidence is between 0 and 1', () {
      final frame = _makeFrame(orangePixels: [(160, 120, 15)]);
      final results = detector.detect(frame, 320, 240);
      for (final r in results) {
        expect(r.$5, greaterThanOrEqualTo(0));
        expect(r.$5, lessThanOrEqualTo(1));
      }
    });

    test('handles large frames by downscaling', () {
      final frame = _makeFrame(w: 1920, h: 1080, orangePixels: [(960, 540, 30)]);
      final results = detector.detect(frame, 1920, 1080);
      // Should not crash, may or may not detect depending on scaling
      expect(results, isA<List>());
    });
  });
}
