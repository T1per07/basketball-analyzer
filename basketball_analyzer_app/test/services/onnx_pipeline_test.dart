import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/services/shot_analyzer.dart';
import 'package:basketball_analyzer/services/onnx_detector.dart';
import 'package:basketball_analyzer/models/models.dart';

/// 生成 BGR 帧
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
  group('ONNX 流水线集成', () {
    test('OnnxDetector 可创建且默认未初始化', () {
      final detector = OnnxDetector();
      expect(detector.isInitialized, false);
      expect(detector.inputSize, 640);
    });

    test('OnnxDetector 自定义参数', () {
      final detector = OnnxDetector(
        confThreshold: 0.3,
        nmsThreshold: 0.5,
        inputSize: 320,
      );
      expect(detector.confThreshold, 0.3);
      expect(detector.nmsThreshold, 0.5);
      expect(detector.inputSize, 320);
    });

    test('preprocess 不同尺寸帧不崩溃', () {
      final detector = OnnxDetector(inputSize: 640);

      // 640x480
      final f1 = _frame(w: 640, h: 480);
      final r1 = detector.preprocess(f1, 640, 480);
      expect(r1.length, 640 * 640 * 3);

      // 1280x720
      final f2 = _frame(w: 1280, h: 720);
      final r2 = detector.preprocess(f2, 1280, 720);
      expect(r2.length, 640 * 640 * 3);

      // 320x240
      final f3 = _frame(w: 320, h: 240);
      final r3 = detector.preprocess(f3, 320, 240);
      expect(r3.length, 640 * 640 * 3);
    });

    test('preprocess 值范围始终在 [0, 1]', () {
      final detector = OnnxDetector(inputSize: 320);
      // 帧包含极端值
      final data = Uint8List(100 * 100 * 3);
      for (int i = 0; i < data.length; i++) {
        data[i] = i % 256; // 0-255 全范围
      }
      final result = detector.preprocess(data, 100, 100);
      for (int i = 0; i < result.length; i++) {
        expect(result[i], inInclusiveRange(0.0, 1.0));
      }
    });

    test('postprocess 模拟完整检测流程', () {
      final detector = OnnxDetector(confThreshold: 0.2, nmsThreshold: 0.5);

      // 模型输出 [1, 6, N] 列优先: [cx_all, cy_all, w_all, h_all, conf_all, class_all]
      // 2 个检测：1 篮球, 1 篮筐
      final output = <double>[
        300, 100, // cx
        200, 250, // cy
        50, 60, // w
        30, 40, // h
        0.85, 0.6, // conf
        0, 1, // class: basketball, hoop
      ];
      final (boxes, confs, classes) =
          detector.postprocess(output, [1, 6, 2], 640, 480);

      expect(boxes.length, 2);
      expect(classes.contains(OnnxDetector.classBasketball), true);
      expect(classes.contains(OnnxDetector.classHoop), true);
    });

    test('postprocess 分离篮球和篮筐', () {
      final detector = OnnxDetector(confThreshold: 0.1);

      // 2 个篮球 + 1 个篮筐 — 列优先布局
      final output = <double>[
        100, 300, 400, // cx
        200, 100, 150, // cy
        30, 35, 80, // w
        30, 35, 40, // h
        0.9, 0.8, 0.85, // conf
        0, 0, 1, // class
      ];
      final (boxes, confs, classes) =
          detector.postprocess(output, [1, 6, 3], 640, 480);

      expect(boxes.length, 3);

      // 分离篮球和篮筐
      final basketballs = <int>[];
      final hoops = <int>[];
      for (int i = 0; i < classes.length; i++) {
        if (classes[i] == OnnxDetector.classBasketball) basketballs.add(i);
        if (classes[i] == OnnxDetector.classHoop) hoops.add(i);
      }

      expect(basketballs.length, 2);
      expect(hoops.length, 1);
    });

    test('ShotAnalyzer enableOnnx 不崩溃（未初始化时）', () {
      final analyzer = ShotAnalyzer(fps: 30);
      // 未初始化 ONNX 时调用 enableOnnx 不应崩溃
      analyzer.enableOnnx();
      // 应该回退到颜色检测
      analyzer.processFrame(
        _frame(hoop: (320, 120, 60, 30)),
        640, 480, 0,
      );
      expect(analyzer.shotDetector.totalShots, 0);
    });
  });
}

/// 辅助
Matcher inInclusiveRange(double min, double max) =>
    allOf(greaterThanOrEqualTo(min), lessThanOrEqualTo(max));
