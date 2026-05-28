import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/services/color_ball_detector.dart';
import 'package:basketball_analyzer/services/hoop_detector.dart';
import 'package:basketball_analyzer/services/shot_detector.dart';
import 'package:basketball_analyzer/services/trajectory_analyzer.dart';
import 'package:basketball_analyzer/services/shot_analyzer.dart';
import 'package:basketball_analyzer/models/models.dart';

/// 生成模拟 BGR 帧数据
Uint8List _makeFrame(int width, int height, {int? ballX, int? ballY}) {
  final rng = Random(42);
  final data = Uint8List(width * height * 3);
  for (int i = 0; i < data.length; i += 3) {
    // 默认：深色背景（模拟球场地板）
    data[i] = 60 + rng.nextInt(40);       // B
    data[i + 1] = 80 + rng.nextInt(40);   // G
    data[i + 2] = 70 + rng.nextInt(40);   // R
  }
  // 在指定位置画一个橙色球（20x20 区域）
  if (ballX != null && ballY != null) {
    for (int dy = -10; dy <= 10; dy++) {
      for (int dx = -10; dx <= 10; dx++) {
        final px = (ballX + dx).clamp(0, width - 1);
        final py = (ballY + dy).clamp(0, height - 1);
        if (dx * dx + dy * dy <= 100) {
          final idx = (py * width + px) * 3;
          data[idx] = 30;       // B (低)
          data[idx + 1] = 120;  // G (中)
          data[idx + 2] = 220;  // R (高 → 橙色)
        }
      }
    }
  }
  return data;
}

/// 生成模拟篮筐区域（红色矩形）
Uint8List _makeFrameWithHoop(int width, int height, int hoopX, int hoopY) {
  final data = _makeFrame(width, height);
  // 篮筐：40x20 红色区域
  for (int dy = -10; dy <= 10; dy++) {
    for (int dx = -20; dx <= 20; dx++) {
      final px = (hoopX + dx).clamp(0, width - 1);
      final py = (hoopY + dy).clamp(0, height - 1);
      final idx = (py * width + px) * 3;
      data[idx] = 40;       // B
      data[idx + 1] = 50;   // G
      data[idx + 2] = 200;  // R (红色)
    }
  }
  return data;
}

/// 测量 N 次操作的平均耗时
Future<double> _bench(String name, int iterations, Future<void> Function() fn) async {
  // 预热
  for (int i = 0; i < 3; i++) {
    await fn();
  }
  final sw = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    await fn();
  }
  sw.stop();
  final avgUs = sw.elapsedMicroseconds / iterations;
  final avgMs = avgUs / 1000;
  return avgMs;
}

void main() {
  group('Performance Benchmarks', () {
    test('ColorBallDetector — 640x480 per frame', () async {
      final detector = ColorBallDetector();
      final frame = _makeFrame(640, 480, ballX: 320, ballY: 240);
      const iterations = 100;

      final avgMs = await _bench('ColorBallDetector', iterations, () async {
        detector.detect(frame, 640, 480);
      });

      print('ColorBallDetector 640x480: ${avgMs.toStringAsFixed(2)} ms/frame');
      print('  → ${(1000 / avgMs).round()} FPS equivalent');
      expect(avgMs, lessThan(100), reason: 'Should be under 100ms per frame');
    });

    test('ColorBallDetector — 1280x720 per frame', () async {
      final detector = ColorBallDetector();
      final frame = _makeFrame(1280, 720, ballX: 640, ballY: 360);
      const iterations = 50;

      final avgMs = await _bench('ColorBallDetector 720p', iterations, () async {
        detector.detect(frame, 1280, 720);
      });

      print('ColorBallDetector 1280x720: ${avgMs.toStringAsFixed(2)} ms/frame');
      print('  → ${(1000 / avgMs).round()} FPS equivalent');
      expect(avgMs, lessThan(300), reason: 'Should be under 300ms per frame');
    });

    test('HoopDetector — 640x480 per frame', () async {
      final detector = HoopDetector();
      final frame = _makeFrameWithHoop(640, 480, 320, 100);
      const iterations = 100;

      final avgMs = await _bench('HoopDetector', iterations, () async {
        detector.detect(frame, 640, 480);
      });

      print('HoopDetector 640x480: ${avgMs.toStringAsFixed(2)} ms/frame');
      print('  → ${(1000 / avgMs).round()} FPS equivalent');
      expect(avgMs, lessThan(100), reason: 'Should be under 100ms per frame');
    });

    test('ShotDetector — processFrame per call', () async {
      final detector = ShotDetector(fps: 30);
      detector.updateHoop(300, 100, w: 60, h: 30);
      const iterations = 10000;

      final avgMs = await _bench('ShotDetector', iterations, () async {
        final positions = [(320.0, 200.0)];
        final sizes = [400.0];
        final confs = [0.5];
        detector.processFrame(positions, sizes, confs, frameIndex: 0);
      });

      print('ShotDetector processFrame: ${(avgMs * 1000).toStringAsFixed(1)} µs/call');
      print('  → ${(1000 / avgMs).round()} calls/sec');
      expect(avgMs, lessThan(1), reason: 'Should be under 1ms per call');
    });

    test('TrajectoryAnalyzer — polynomial fit (20 points)', () async {
      final analyzer = TrajectoryAnalyzer();
      analyzer.setFrameWidth(640);
      analyzer.setFps(30);
      analyzer.updateHoopReference((320.0, 100.0), 60.0);
      const iterations = 5000;

      // 模拟一条抛物线轨迹
      final track = BallTrack(trackId: 0);
      for (int i = 0; i < 20; i++) {
        final t = i / 20.0;
        final x = 200 + t * 240;
        final y = 300 - 200 * t + 200 * t * t; // 抛物线
        track.addPoint(i, x, y, confidence: 0.8, ballArea: 400);
      }

      final avgMs = await _bench('TrajectoryAnalyzer', iterations, () async {
        analyzer.fitTrajectory(track);
      });

      print('TrajectoryAnalyzer fit (20pts): ${(avgMs * 1000).toStringAsFixed(1)} µs/call');
      print('  → ${(1000 / avgMs).round()} calls/sec');
      expect(avgMs, lessThan(2), reason: 'Should be under 2ms per fit');
    });

    test('ShotAnalyzer — full pipeline per frame (640x480)', () async {
      final analyzer = ShotAnalyzer(fps: 30);
      final frame = _makeFrameWithHoop(640, 480, 320, 100);
      const iterations = 50;

      final avgMs = await _bench('ShotAnalyzer', iterations, () async {
        analyzer.processFrame(frame, 640, 480, 0);
      });

      print('ShotAnalyzer 640x480: ${avgMs.toStringAsFixed(2)} ms/frame');
      print('  → ${(1000 / avgMs).round()} FPS equivalent');
      expect(avgMs, lessThan(200), reason: 'Should be under 200ms per frame');
    });

    test('Memory — BallTrack 1000 points', () {
      final track = BallTrack(trackId: 0);
      for (int i = 0; i < 1000; i++) {
        track.addPoint(i, i * 0.5, 300 - i * 0.3, confidence: 0.7, ballArea: 400);
      }
      expect(track.length, 1000);
      // 不应抛异常
      final center = track.getCenterAt(500);
      expect(center, isNotNull);
    });

    test('Memory — ShotDetector 10000 frames', () {
      final detector = ShotDetector(fps: 30);
      detector.updateHoop(300, 100, w: 60, h: 30);
      for (int i = 0; i < 10000; i++) {
        detector.processFrame(
          [(320.0 + sin(i * 0.1) * 50, 200.0 - cos(i * 0.1) * 80)],
          [400.0],
          [0.6],
          frameIndex: i,
        );
      }
      expect(detector.totalShots, greaterThanOrEqualTo(0));
      // 不应 OOM
    });
  });
}
