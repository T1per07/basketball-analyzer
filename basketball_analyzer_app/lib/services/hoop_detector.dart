import 'dart:math';
import 'dart:typed_data';

/// 篮筐检测器 — 颜色检测 + 校准跟踪
/// 对应 Python models/hoop_detector.py
class HoopDetector {
  List<(int, int, int, int)> _calibrationBuffer = [];
  bool _calibrated = false;
  (int, int, int, int)? _hoopBox; // x, y, w, h
  (int, int, int, int)? _lockedBox;
  static const _calibFrames = 12;

  bool get isCalibrated => _calibrated;

  (int, int)? get hoopPosition {
    if (_hoopBox == null) return null;
    final (x, y, w, h) = _hoopBox!;
    return (x + w ~/ 2, y + h ~/ 2);
  }

  (int, int, int, int)? get hoopBox => _hoopBox;

  /// 处理一帧，返回篮筐中心位置
  /// [frameBgr] 是 BGR 格式的图像数据（Uint8List）
  /// [width], [height] 是图像尺寸
  (int, int)? detect(Uint8List frameBgr, int width, int height) {
    if (!_calibrated) {
      return _calibrate(frameBgr, width, height);
    }
    return _track(frameBgr, width, height);
  }

  (int, int)? _calibrate(Uint8List frameBgr, int width, int height) {
    final candidates = _findColorCandidates(frameBgr, width, height, 0, 0);
    if (candidates.isNotEmpty) {
      // 选择最接近正方形的候选（篮筐通常是近正方形区域）
      candidates.sort((a, b) {
        final aspectA = (a.$3 / max(a.$4, 1) - 1.0).abs();
        final aspectB = (b.$3 / max(b.$4, 1) - 1.0).abs();
        final sizeA = a.$3 * a.$4;
        final sizeB = b.$3 * b.$4;
        final scoreA = aspectA * 2 + sizeA / 2000;
        final scoreB = aspectB * 2 + sizeB / 2000;
        return scoreA.compareTo(scoreB);
      });
      final best = candidates.first;
      _calibrationBuffer.add((best.$1, best.$2, best.$3, best.$4));
    }

    if (_calibrationBuffer.length >= _calibFrames) {
      _finishCalibration();
    }
    return hoopPosition;
  }

  void _finishCalibration() {
    if (_calibrationBuffer.isEmpty) return;

    final xs = _calibrationBuffer.map((b) => b.$1).toList()..sort();
    final ys = _calibrationBuffer.map((b) => b.$2).toList()..sort();
    final medX = xs[xs.length ~/ 2];
    final medY = ys[ys.length ~/ 2];

    final filtered = _calibrationBuffer
        .where((b) => (b.$1 - medX).abs() < 100 && (b.$2 - medY).abs() < 80)
        .toList();
    final use = filtered.isNotEmpty ? filtered : _calibrationBuffer;

    final avgX = _median(use.map((b) => b.$1).toList());
    final avgY = _median(use.map((b) => b.$2).toList());
    final avgW = _median(use.map((b) => b.$3).toList());
    final avgH = _median(use.map((b) => b.$4).toList());

    if (avgW < 15 || avgH < 8) return;

    _hoopBox = (avgX, avgY, avgW, avgH);
    _lockedBox = (avgX, avgY, avgW, avgH);
    _calibrated = true;
  }

  (int, int)? _track(Uint8List frameBgr, int width, int height) {
    if (_lockedBox == null) return hoopPosition;

    final (lx, ly, lw, lh) = _lockedBox!;
    final marginX = lw;
    final marginY = lh;
    final x1 = max(0, lx - marginX);
    final y1 = max(0, ly - marginY);
    final x2 = min(width, lx + lw + marginX);
    final y2 = min(height, ly + lh + marginY);

    final roiW = x2 - x1;
    final roiH = y2 - y1;
    if (roiW <= 0 || roiH <= 0) return hoopPosition;

    final candidates = _findColorCandidates(frameBgr, width, height, x1, y1,
        roiX1: x1, roiY1: y1, roiW: roiW, roiH: roiH);

    if (candidates.isNotEmpty) {
      // 按距离锁定位置排序
      final lcX = lx + lw ~/ 2;
      final lcY = ly + lh ~/ 2;
      candidates.sort((a, b) {
        final aCx = a.$1 + a.$3 ~/ 2;
        final aCy = a.$2 + a.$4 ~/ 2;
        final bCx = b.$1 + b.$3 ~/ 2;
        final bCy = b.$2 + b.$4 ~/ 2;
        final distA = (aCx - lcX) * (aCx - lcX) + (aCy - lcY) * (aCy - lcY);
        final distB = (bCx - lcX) * (bCx - lcX) + (bCy - lcY) * (bCy - lcY);
        return distA.compareTo(distB);
      });

      final best = candidates.first;
      final (bx, by, bw, bh) = best;
      final cx = bx + bw ~/ 2;
      final cy = by + bh ~/ 2;
      final dist = (cx - lcX) * (cx - lcX) + (cy - lcY) * (cy - lcY);
      final maxDist = (lw * 0.6) * (lw * 0.6);

      if (dist < maxDist) {
        if (bw < 12 || bh < 6) {

          return hoopPosition;
        }
        const alpha = 0.08;
        final newX = (alpha * bx + (1 - alpha) * lx).round();
        final newY = (alpha * by + (1 - alpha) * ly).round();
        final newW = (alpha * bw + (1 - alpha) * lw).round();
        final newH = (alpha * bh + (1 - alpha) * lh).round();
        _hoopBox = (newX, newY, newW, newH);
        _lockedBox = _hoopBox;
      }
    } else {
    }

    return hoopPosition;
  }

  /// 颜色检测找篮筐候选
  /// 返回 (x, y, w, h) 列表
  List<(int, int, int, int)> _findColorCandidates(
    Uint8List frameBgr, int frameW, int frameH,
    int offsetX, int offsetY,
    {int? roiX1, int? roiY1, int? roiW, int? roiH}
  ) {
    // 简化实现：扫描 ROI 区域，查找红/橙色像素聚类
    final rx1 = roiX1 ?? 0;
    final ry1 = roiY1 ?? 0;
    final rw = roiW ?? frameW;
    final rh = roiH ?? frameH;

    final minArea = (rw * rh * 0.001).round();
    final maxArea = (rw * rh * 0.06).round();

    // 简化版颜色检测：用像素扫描代替完整 OpenCV 流水线
    // 标记符合颜色范围的像素
    final mask = Uint8List(rw * rh);
    for (int y = 0; y < rh; y++) {
      for (int x = 0; x < rw; x++) {
        final fx = rx1 + x;
        final fy = ry1 + y;
        if (fx >= frameW || fy >= frameH) continue;

        final idx = (fy * frameW + fx) * 3;
        if (idx + 2 >= frameBgr.length) continue;

        final b = frameBgr[idx];
        final g = frameBgr[idx + 1];
        final r = frameBgr[idx + 2];

        if (_isHoopColor(r, g, b)) {
          mask[y * rw + x] = 1;
        }
      }
    }

    // 简化连通域分析：用网格分块统计
    final blockSize = max(8, min(rw, rh) ~/ 20);
    final gridW = (rw / blockSize).ceil();
    final gridH = (rh / blockSize).ceil();
    final candidates = <(int, int, int, int)>[];

    for (int gy = 0; gy < gridH; gy++) {
      for (int gx = 0; gx < gridW; gx++) {
        int count = 0;
        final x1 = gx * blockSize;
        final y1g = gy * blockSize;
        final x2 = min(x1 + blockSize, rw);
        final y2 = min(y1g + blockSize, rh);

        for (int y = y1g; y < y2; y++) {
          for (int x = x1; x < x2; x++) {
            if (mask[y * rw + x] > 0) count++;
          }
        }

        final area = (x2 - x1) * (y2 - y1g);
        if (count >= minArea && count <= maxArea && count > area * 0.1) {
          // 检查是否在画面上半部分
          final absY = y1g + offsetY;
          if (absY < frameH * 0.75) {
            candidates.add((x1 + offsetX, y1g + offsetY, x2 - x1, y2 - y1g));
          }
        }
      }
    }

    return candidates;
  }

  /// 检查 RGB 是否在篮筐颜色范围内（红/橙红）
  bool _isHoopColor(int r, int g, int b) {
    // 简化版：用 RGB 范围近似 HSV 判断
    // 红色/橙红色：R 高，G 中低，B 低
    if (r > 120 && r > g * 1.3 && g < 180 && b < 150) return true;
    if (r > 150 && g > 40 && g < 120 && b < 100) return true;
    return false;
  }

  int _median(List<int> values) {
    if (values.isEmpty) return 0;
    final sorted = List<int>.from(values)..sort();
    return sorted[sorted.length ~/ 2];
  }

  void reset() {
    _calibrationBuffer.clear();
    _calibrated = false;
    _hoopBox = null;
    _lockedBox = null;
  }
}
