import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/services/shot_analyzer.dart';
import 'package:basketball_analyzer/services/hoop_detector.dart';
import 'package:basketball_analyzer/services/color_ball_detector.dart';

Uint8List _frame({
  int w = 640,
  int h = 480,
  List<(int, int)> balls = const [],
  (int, int, int, int)? hoop,
}) {
  final rng = Random(42);
  final data = Uint8List(w * h * 3);
  for (int i = 0; i < data.length; i += 3) {
    data[i] = 50 + rng.nextInt(30);
    data[i + 1] = 70 + rng.nextInt(30);
    data[i + 2] = 60 + rng.nextInt(30);
  }
  for (final (bx, by) in balls) {
    for (int dy = -12; dy <= 12; dy++) {
      for (int dx = -12; dx <= 12; dx++) {
        if (dx * dx + dy * dy > 144) continue;
        final px = (bx + dx).clamp(0, w - 1);
        final py = (by + dy).clamp(0, h - 1);
        final idx = (py * w + px) * 3;
        data[idx] = 25;
        data[idx + 1] = 110;
        data[idx + 2] = 215;
      }
    }
  }
  if (hoop != null) {
    final (hx, hy, hw, hh) = hoop;
    for (int dy = -(hh ~/ 2); dy <= hh ~/ 2; dy++) {
      for (int dx = -(hw ~/ 2); dx <= hw ~/ 2; dx++) {
        final px = (hx + dx).clamp(0, w - 1);
        final py = (hy + dy).clamp(0, h - 1);
        final idx = (py * w + px) * 3;
        data[idx] = 35;
        data[idx + 1] = 45;
        data[idx + 2] = 195;
      }
    }
  }
  return data;
}

void main() {
  test('调试场景1: 诊断检测管线', () {
    final hoopDetector = HoopDetector();
    final colorDetector = ColorBallDetector();
    final analyzer = ShotAnalyzer(fps: 30);

    const hoopX = 320, hoopY = 120;

    // 校准期：只有篮筐
    print('\n=== 校准期 (帧 0-14) ===');
    for (int i = 0; i < 15; i++) {
      final frame = _frame(hoop: (hoopX, hoopY, 60, 30));

      // 单独测试 HoopDetector
      final hoopPos = hoopDetector.detect(frame, 640, 480);
      if (i == 0 || i == 5 || i == 10 || i == 14) {
        print('  帧$i: hoopPos=$hoopPos calibrated=${hoopDetector.isCalibrated} box=${hoopDetector.hoopBox}');
      }

      // 单独测试 ColorBallDetector
      final balls = colorDetector.detect(frame, 640, 480);
      if (i == 0 || i == 14) {
        print('  帧$i: balls=${balls.length} detections=$balls');
      }

      analyzer.processFrame(frame, 640, 480, i);
    }

    print('\n=== 校准后状态 ===');
    print('  hoopDetected: ${analyzer.shotDetector.hoopDetected}');

    // 投篮期
    print('\n=== 投篮期 (帧 15-74) ===');
    final rng = Random(42);
    for (int i = 0; i < 60; i++) {
      final t = i / 59.0;
      final x = 200 + (320 - 200) * t;
      final y = 300 + (120 + 40 - 300) * t - 150 * sin(pi * t);

      final data = Uint8List(640 * 480 * 3);
      for (int p = 0; p < data.length; p += 3) {
        data[p] = 50 + rng.nextInt(30);
        data[p + 1] = 70 + rng.nextInt(30);
        data[p + 2] = 60 + rng.nextInt(30);
      }
      // 画球
      for (int dy = -12; dy <= 12; dy++) {
        for (int dx = -12; dx <= 12; dx++) {
          if (dx * dx + dy * dy > 144) continue;
          final px = (x.round() + dx).clamp(0, 639);
          final py = (y.round() + dy).clamp(0, 479);
          final idx = (py * 640 + px) * 3;
          data[idx] = 25;
          data[idx + 1] = 110;
          data[idx + 2] = 215;
        }
      }
      // 画篮筐
      for (int dy = -15; dy <= 15; dy++) {
        for (int dx = -30; dx <= 30; dx++) {
          final px = (hoopX + dx).clamp(0, 639);
          final py = (hoopY + dy).clamp(0, 479);
          final idx = (py * 640 + px) * 3;
          data[idx] = 35;
          data[idx + 1] = 45;
          data[idx + 2] = 195;
        }
      }

      final balls = colorDetector.detect(data, 640, 480);
      final hoopPos = hoopDetector.detect(data, 640, 480);

      if (i % 10 == 0 || (i >= 20 && i <= 30)) {
        print('  帧${15+i}: ball=(${x.round()},${y.round()}) '
            'balls_detected=${balls.length} hoop=$hoopPos');
        if (balls.isNotEmpty) {
          for (final b in balls) {
            print('    ball candidate: $b');
          }
        }
      }

      analyzer.processFrame(data, 640, 480, 15 + i);
    }

    // 后 15 帧
    for (int i = 0; i < 15; i++) {
      analyzer.processFrame(
        _frame(hoop: (hoopX, hoopY, 60, 30)),
        640, 480, 75 + i,
      );
    }

    final result = analyzer.buildResult(90, 30.0);
    print('\n=== 结果 ===');
    print('  投篮: ${result.totalShots}, 命中: ${result.madeShots}');
    for (final s in result.shots) {
      print('  #${s.shotId}: ${s.made ? "命中" : "未中"} conf=${s.confidence}');
    }
  });
}
