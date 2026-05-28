import 'dart:math';
import 'dart:typed_data';

/// 基于颜色的篮球检测器
/// 对应 Python models/detection.py ColorBallDetector
class ColorBallDetector {
  // 橙色篮球 HSV 范围（用 RGB 近似）
  // 橙色：R 高(180-255), G 中(80-200), B 低(0-100)

  static const _targetWidth = 320;

  List<(double, double, double, double, double)> detect(
      Uint8List frameBgr, int width, int height) {
    // 返回 (x1, y1, x2, y2, confidence) 列表

    // 缩放
    double scale = 1.0;
    int sw = width, sh = height;
    if (width > _targetWidth) {
      scale = _targetWidth / width;
      sw = _targetWidth;
      sh = (height * scale).round();
    }

    final minArea = max(50, (sw * sh * 0.0005).round());
    final maxArea = (sw * sh * 0.015).round();

    // 用网格扫描检测橙色区域
    final blockSize = max(6, min(sw, sh) ~/ 30);
    final gridW = (sw / blockSize).ceil();
    final gridH = (sh / blockSize).ceil();

    final results = <(double, double, double, double, double)>[];

    for (int gy = 0; gy < gridH; gy++) {
      for (int gx = 0; gx < gridW; gx++) {
        int orangeCount = 0;
        final x1 = gx * blockSize;
        final y1 = gy * blockSize;
        final x2 = min(x1 + blockSize, sw);
        final y2 = min(y1 + blockSize, sh);

        for (int y = y1; y < y2; y++) {
          for (int x = x1; x < x2; x++) {
            final srcX = (x / scale).round().clamp(0, width - 1);
            final srcY = (y / scale).round().clamp(0, height - 1);
            final idx = (srcY * width + srcX) * 3;
            if (idx + 2 >= frameBgr.length) continue;

            final b = frameBgr[idx];
            final g = frameBgr[idx + 1];
            final r = frameBgr[idx + 2];
            if (_isOrange(r, g, b)) {
              orangeCount++;
            }
          }
        }

        final area = (x2 - x1) * (y2 - y1);
        if (orangeCount >= minArea &&
            orangeCount <= maxArea &&
            orangeCount > area * 0.15) {
          // 检查纵横比
          final bw = (x2 - x1).toDouble();
          final bh = (y2 - y1).toDouble();
          final aspect = bw / max(bh, 1);
          if (aspect >= 0.5 && aspect <= 2.0) {
            final conf = min(0.3 + (orangeCount / maxArea) * 0.3, 0.8);
            // 转换回原始坐标
            results.add((
              x1 / scale,
              y1 / scale,
              x2 / scale,
              y2 / scale,
              conf,
            ));
          }
        }
      }
    }

    return results;
  }

  /// 检查 RGB 是否为橙色（篮球颜色）
  bool _isOrange(int r, int g, int b) {
    // 橙色：R 高，G 中，B 低
    // 高饱和度橙色
    if (r > 160 && g > 80 && g < 200 && b < 100 && r > g) return true;
    // 偏红橙（暖光下）
    if (r > 180 && g > 60 && g < 150 && b < 80 && r > g * 1.2) return true;
    return false;
  }
}
