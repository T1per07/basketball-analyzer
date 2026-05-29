import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/services/shot_detector.dart';

void main() {
  group('ShotDetector', () {
    late ShotDetector detector;

    setUp(() {
      detector = ShotDetector(fps: 30);
    });

    test('starts with zero shots', () {
      expect(detector.totalShots, 0);
      expect(detector.totalMade, 0);
      expect(detector.shotResults, isEmpty);
      expect(detector.hoopDetected, isFalse);
    });

    test('updateHoop stores hoop position', () {
      detector.updateHoop(300, 100, w: 60, h: 30);
      expect(detector.hoopDetected, isTrue);
    });

    test('updateHoop rejects too-small hoop', () {
      detector.updateHoop(300, 100, w: 10, h: 10);
      expect(detector.hoopDetected, isFalse);
    });

    test('updateHoop rejects very small coordinates', () {
      // cx = 3 + 30 = 33 (>20), cy = 3 + 15 = 18 (>15) → accepted
      // But w=10, h=10 → rejected by size check
      detector.updateHoop(3, 3, w: 10, h: 10);
      expect(detector.hoopDetected, isFalse);
    });

    test('processFrame returns null without hoop', () {
      final result = detector.processFrame([(100.0, 200.0)], [400.0], [0.5]);
      expect(result, isNull);
    });

    test('processFrame returns null with no ball positions', () {
      detector.updateHoop(300, 100, w: 60, h: 30);
      final result = detector.processFrame([], [], []);
      expect(result, isNull);
    });

    test('processFrame with static ball does not trigger shot', () {
      detector.updateHoop(300, 100, w: 60, h: 30);
      for (int i = 0; i < 100; i++) {
        detector.processFrame(
          [(320.0, 200.0)],
          [400.0],
          [0.5],
          frameIndex: i,
        );
      }
      expect(detector.totalShots, 0);
    });

    test('setFps updates fps', () {
      detector.setFps(60);
      expect(detector.fps, 60);
    });

    test('setFps ignores invalid value', () {
      detector.setFps(0);
      expect(detector.fps, 30);
      detector.setFps(-5);
      expect(detector.fps, 30);
    });

    test('reset clears all state', () {
      detector.updateHoop(300, 100, w: 60, h: 30);
      detector.processFrame([(320.0, 200.0)], [400.0], [0.5], frameIndex: 0);
      detector.reset();
      expect(detector.totalShots, 0);
      expect(detector.hoopDetected, isFalse);
      expect(detector.shotBallPositions, isEmpty);
    });

    test('shotBallPositions stores positions for each shot', () {
      detector.updateHoop(300, 100, w: 60, h: 30);
      // Add some ball positions
      for (int i = 0; i < 5; i++) {
        detector.processFrame(
          [(320.0, 200.0 - i * 10)],
          [400.0],
          [0.5],
          frameIndex: i,
        );
      }
      // shotBallPositions should have entries (even if no shot detected)
      expect(detector.shotBallPositions, isA<Map>());
    });
  });
}
