import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/services/onnx_detector.dart';

/// 生成 BGR 测试帧，在指定位置画橙色球和红色篮筐
Uint8List _frame({
  int w = 640,
  int h = 480,
  List<(int, int, int)> balls = const [], // (x, y, radius)
  (int, int, int, int)? hoop, // x, y, w, h
}) {
  final rng = Random(42);
  final data = Uint8List(w * h * 3);
  for (int i = 0; i < data.length; i += 3) {
    data[i] = 50 + rng.nextInt(30);
    data[i + 1] = 70 + rng.nextInt(30);
    data[i + 2] = 60 + rng.nextInt(30);
  }
  for (final (bx, by, r) in balls) {
    for (int dy = -r; dy <= r; dy++) {
      for (int dx = -r; dx <= r; dx++) {
        if (dx * dx + dy * dy > r * r) continue;
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
  group('OnnxDetector 预处理', () {
    test('preprocess 输出大小和值范围正确', () {
      final detector = OnnxDetector();
      // 手动设置 inputSize（不加载模型）
      final frame = _frame(w: 640, h: 480, balls: [(320, 240, 20)]);
      final result = detector.preprocess(frame, 640, 480);

      expect(result.length, 640 * 640 * 3,
          reason: '输出应为 [3, 640, 640] 的 flat array');

      // 所有值应在 [0, 1] 范围内
      for (int i = 0; i < result.length; i++) {
        expect(result[i], inInclusiveRange(0.0, 1.0),
            reason: '归一化后值应在 [0, 1]: index=$i value=${result[i]}');
      }
    });

    test('preprocess BGR→RGB 转换正确', () {
      // 创建纯红色帧 (BGR: 0, 0, 255)
      final data = Uint8List(100 * 100 * 3);
      for (int i = 0; i < data.length; i += 3) {
        data[i] = 0; // B
        data[i + 1] = 0; // G
        data[i + 2] = 255; // R
      }

      // 用 640x640 输入，避免 resize 缩放干扰
      final detector = OnnxDetector(inputSize: 100);
      final result = detector.preprocess(data, 100, 100);

      // CHW 布局：R→G→B
      // R channel (index 0): 255/255 = 1.0
      expect(result[0], closeTo(1.0, 0.01), reason: 'R channel 应为 1.0');
      // G channel (index 100*100): 0/255 = 0.0
      expect(result[100 * 100], closeTo(0.0, 0.01),
          reason: 'G channel 应为 0.0');
      // B channel (index 2*100*100): 0/255 = 0.0
      expect(result[2 * 100 * 100], closeTo(0.0, 0.01),
          reason: 'B channel 应为 0.0');
    });
  });

  group('OnnxDetector 后处理', () {
    test('空输出返回空结果', () {
      final detector = OnnxDetector();
      final (boxes, confs, classes) =
          detector.postprocess([], [1, 6, 0], 640, 480);
      expect(boxes, isEmpty);
      expect(confs, isEmpty);
      expect(classes, isEmpty);
    });

    test('低置信度检测被过滤', () {
      final detector = OnnxDetector(confThreshold: 0.5);
      // 模拟输出: [1, 6, 2] — 2 个检测
      final output = <double>[
        320, 240, // cx
        320, 240, // cy
        60, 60, // w
        30, 30, // h
        0.3, 0.8, // conf (第一个低于阈值)
        0, 0, // class_id
      ];
      final (boxes, confs, classes) =
          detector.postprocess(output, [1, 6, 2], 640, 480);
      expect(boxes.length, 1, reason: '低置信度应被过滤');
      expect(confs.first, 0.8);
    });

    test('xywh→xyxy 转换正确', () {
      final detector = OnnxDetector(confThreshold: 0.1, inputSize: 640);
      // cx=100, cy=200, w=40, h=60 → x1=80, y1=170, x2=120, y2=230
      // 原始尺寸也是 640x640，缩放比例=1.0
      final output = <double>[100, 200, 40, 60, 0.9, 0];
      final (boxes, _, _) =
          detector.postprocess(output, [1, 6, 1], 640, 640);
      expect(boxes.length, 1);
      final (x1, y1, x2, y2) = boxes.first;
      expect(x1, closeTo(80.0, 1.0));
      expect(y1, closeTo(170.0, 1.0));
      expect(x2, closeTo(120.0, 1.0));
      expect(y2, closeTo(230.0, 1.0));
    });

    test('坐标缩放到原始尺寸', () {
      final detector = OnnxDetector(confThreshold: 0.1, inputSize: 320);
      // 模型输入 320x320，原始图像 640x640
      // cx=160, cy=120 在模型坐标 → 缩放后 cx=320, cy=240
      final output = <double>[160, 120, 40, 40, 0.9, 0];
      final (boxes, _, _) =
          detector.postprocess(output, [1, 6, 1], 640, 640);
      expect(boxes.length, 1);
      final (x1, y1, x2, y2) = boxes.first;
      // x1 = (160 - 20) * (640/320) = 140 * 2 = 280
      expect(x1, closeTo(280.0, 2.0));
      // y1 = (120 - 20) * (640/320) = 100 * 2 = 200
      expect(y1, closeTo(200.0, 2.0));
    });

    test('NMS 抑制重叠框', () {
      final detector = OnnxDetector(confThreshold: 0.1, nmsThreshold: 0.5);
      // 两个高度重叠的篮球检测
      final output = <double>[
        100, 100, 100, 100, // cx, cy, w, h — 框1
        105, 105, 100, 100, // cx, cy, w, h — 框2（重叠）
        0.9, 0.85, // conf
        0, 0, // class_id
      ];
      final (boxes, confs, _) =
          detector.postprocess(output, [1, 6, 2], 640, 480);
      expect(boxes.length, 1, reason: 'NMS 应抑制重叠框');
      expect(confs.first, 0.9, reason: '保留最高置信度');
    });

    test('不同类别不互相抑制', () {
      final detector = OnnxDetector(confThreshold: 0.1, nmsThreshold: 0.5);
      // 篮球和篮筐在同一位置
      final output = <double>[
        100, 100, 100, 100, // 篮球
        100, 100, 100, 100, // 篮筐
        0.9, 0.85,
        0, 1, // class 0 = basketball, class 1 = hoop
      ];
      final (boxes, _, classes) =
          detector.postprocess(output, [1, 6, 2], 640, 480);
      expect(boxes.length, 2, reason: '不同类别不应互相抑制');
      expect(classes.toSet().length, 2);
    });
  });

  group('OnnxDetector IoU 计算', () {
    test('完全重叠 IoU = 1.0', () {
      final detector = OnnxDetector();
      final iou = detector.computeIoU((0, 0, 100, 100), (0, 0, 100, 100));
      expect(iou, closeTo(1.0, 0.001));
    });

    test('无重叠 IoU = 0.0', () {
      final detector = OnnxDetector();
      final iou = detector.computeIoU((0, 0, 50, 50), (100, 100, 150, 150));
      expect(iou, closeTo(0.0, 0.001));
    });

    test('50% 重叠 IoU 正确', () {
      final detector = OnnxDetector();
      // 两个 100x100 框，水平偏移 50
      final iou = detector.computeIoU((0, 0, 100, 100), (50, 0, 150, 100));
      // 交集: 50*100 = 5000, 并集: 10000+10000-5000 = 15000
      expect(iou, closeTo(5000 / 15000, 0.01));
    });
  });
}

/// 辅助：检查值在范围内
Matcher inInclusiveRange(double min, double max) =>
    allOf(greaterThanOrEqualTo(min), lessThanOrEqualTo(max));
