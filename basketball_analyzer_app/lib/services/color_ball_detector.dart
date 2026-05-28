import 'dart:math';
import 'dart:typed_data';

/// 基于 HSV 颜色空间的篮球检测器
/// 对应 Python models/detection.py ColorBallDetector
class ColorBallDetector {
  // 橙色篮球 HSV 范围
  // H: 5-25 (橙色色相)
  // S: 100-255 (高饱和度)
  // V: 100-255 (高亮度)
  static const _hMin = 5, _hMax = 25;
  static const _sMin = 150, _vMin = 150;
  static const _targetWidth = 320;

  List<(double, double, double, double, double)> detect(
      Uint8List frameBgr, int width, int height) {
    // 缩放
    double scale = 1.0;
    int sw = width, sh = height;
    if (width > _targetWidth) {
      scale = _targetWidth / width;
      sw = _targetWidth;
      sh = (height * scale).round();
    }

    // 步骤 1: 生成二值掩码（橙色像素）
    final mask = Uint8List(sw * sh);
    for (int y = 0; y < sh; y++) {
      for (int x = 0; x < sw; x++) {
        final srcX = (x / scale).round().clamp(0, width - 1);
        final srcY = (y / scale).round().clamp(0, height - 1);
        final idx = (srcY * width + srcX) * 3;
        if (idx + 2 >= frameBgr.length) continue;

        final b = frameBgr[idx];
        final g = frameBgr[idx + 1];
        final r = frameBgr[idx + 2];

        if (_isOrangeHsv(r, g, b)) {
          mask[y * sw + x] = 1;
        }
      }
    }

    // 步骤 2: 连通组件分析
    final labels = Int32List(sw * sh);
    final parent = <int>[0];
    final count = <int>[0];
    int nextLabel = 1;

    // Union-Find 查找
    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }

    void union(int a, int b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[max(ra, rb)] = min(ra, rb);
    }

    // 第一遍：标记
    for (int y = 0; y < sh; y++) {
      for (int x = 0; x < sw; x++) {
        if (mask[y * sw + x] == 0) continue;

        int left = 0, above = 0;
        if (x > 0) left = labels[y * sw + (x - 1)];
        if (y > 0) above = labels[(y - 1) * sw + x];

        if (left == 0 && above == 0) {
          labels[y * sw + x] = nextLabel;
          parent.add(nextLabel);
          count.add(1);
          nextLabel++;
        } else if (left != 0 && above == 0) {
          labels[y * sw + x] = find(left);
          count[find(left)]++;
        } else if (left == 0 && above != 0) {
          labels[y * sw + x] = find(above);
          count[find(above)]++;
        } else {
          union(left, above);
          final root = find(left);
          labels[y * sw + x] = root;
          count[root]++;
        }
      }
    }

    // 第二遍：收集边界框
    final bboxes = <int, List<int>>{}; // label → [minX, minY, maxX, maxY, area]
    for (int y = 0; y < sh; y++) {
      for (int x = 0; x < sw; x++) {
        if (labels[y * sw + x] == 0) continue;
        final root = find(labels[y * sw + x]);
        if (!bboxes.containsKey(root)) {
          bboxes[root] = [x, y, x, y, 0];
        }
        final bb = bboxes[root]!;
        bb[0] = min(bb[0], x);
        bb[1] = min(bb[1], y);
        bb[2] = max(bb[2], x);
        bb[3] = max(bb[3], y);
        bb[4]++;
      }
    }

    // 步骤 3: 过滤 — 面积、宽高比、圆形度
    final totalPixels = sw * sh;
    final minArea = max(12, (totalPixels * 0.0002).round());
    final maxArea = (totalPixels * 0.02).round();
    final results = <(double, double, double, double, double)>[];

    for (final bb in bboxes.values) {
      final area = bb[4];
      if (area < minArea || area > maxArea) continue;

      final bw = bb[2] - bb[0] + 1;
      final bh = bb[3] - bb[1] + 1;
      final aspect = bw / max(bh, 1);
      if (aspect < 0.5 || aspect > 2.0) continue;

      // 填充率：area / (bw * bh)，越接近1越紧凑
      final fillRatio = area / (bw * bh);
      if (fillRatio < 0.4) continue; // 太稀疏
      if (fillRatio > 0.85) continue; // 太连续（地板、大面积橙色区域）

      // 最小边界框尺寸
      if (bw < 4 || bh < 4) continue;

      final conf = min(0.4 + fillRatio * 0.3 + (area / maxArea) * 0.2, 0.9);
      results.add((
        bb[0] / scale,
        bb[1] / scale,
        (bb[2] + 1) / scale,
        (bb[3] + 1) / scale,
        conf,
      ));
    }

    return results;
  }

  /// BGR → HSV 转换后检查是否为橙色
  bool _isOrangeHsv(int r, int g, int b) {
    final h = _hue(r, g, b);
    final s = _saturation(r, g, b);
    final v = max(r, max(g, b));

    // 橙色色相范围 (0-180 度 OpenCV 标准)
    if (h >= _hMin && h <= _hMax && s >= _sMin && v >= _vMin) return true;
    // 处理红色环绕 (H 接近 180)
    if (h >= 165 && s >= _sMin && v >= _vMin) return true;
    return false;
  }

  /// 计算色相 (0-180, OpenCV 标准)
  int _hue(int r, int g, int b) {
    final maxC = max(r, max(g, b));
    final minC = min(r, min(g, b));
    if (maxC == minC) return 0;

    final diff = maxC - minC;
    double h;
    if (maxC == r) {
      h = 60 * ((g - b) / diff);
    } else if (maxC == g) {
      h = 60 * (2 + (b - r) / diff);
    } else {
      h = 60 * (4 + (r - g) / diff);
    }
    if (h < 0) h += 360;
    return (h / 2).round(); // 转为 0-180 范围
  }

  /// 计算饱和度 (0-255)
  int _saturation(int r, int g, int b) {
    final maxC = max(r, max(g, b));
    if (maxC == 0) return 0;
    final minC = min(r, min(g, b));
    return ((maxC - minC) / maxC * 255).round();
  }

}
