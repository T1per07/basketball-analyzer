import 'dart:math';
import 'dart:typed_data';

/// 基于 HSV 颜色空间的篮球检测器
/// 对应 Python models/detection.py ColorBallDetector
class ColorBallDetector {
  // 橙色篮球 HSV 范围（对齐 Python ColorBallDetector）
  // 范围 1: H=5-22, S=100-255, V=100-255 (标准橙色)
  // 范围 2: H=0-8, S=120-255, V=120-255 (偏红橙，暖光下)
  static const _hMin = 5, _hMax = 22;
  static const _sMin = 100, _vMin = 100;
  // 第二组范围（暖光偏红）
  static const _h2Max = 8;
  static const _s2Min = 120, _v2Min = 120;
  static const _targetWidth = 320;

  // Pre-allocated buffers for connected components analysis.
  // Reused across frames to avoid allocating Uint8List(sw*sh) and
  // Int32List(sw*sh) on every call — critical for live mode where
  // detect() is called every 3rd frame.
  Uint8List? _mask;
  Int32List? _labels;
  Uint8List? _morphBuf; // 临时缓冲区用于形态学操作
  int _bufSize = 0;

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
    // Reuse pre-allocated buffers when possible
    final size = sw * sh;
    if (_mask == null || _bufSize < size) {
      _mask = Uint8List(size);
      _labels = Int32List(size);
      _morphBuf = Uint8List(size);
      _bufSize = size;
    } else {
      _mask!.fillRange(0, size, 0);
      _labels!.fillRange(0, size, 0);
    }
    final mask = _mask!;
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

    // 步骤 2: 连通组件分析 (labels already pre-allocated above)
    final labels = _labels!;
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

    // 步骤 3: 过滤 — 面积、宽高比（对齐 Python）
    final totalPixels = sw * sh;
    final minArea = max(50, (totalPixels * 0.0005).round());
    final maxArea = (totalPixels * 0.015).round();
    final results = <(double, double, double, double, double)>[];

    for (final bb in bboxes.values) {
      final area = bb[4];
      if (area < minArea || area > maxArea) continue;

      final bw = bb[2] - bb[0] + 1;
      final bh = bb[3] - bb[1] + 1;
      final aspect = bw / max(bh, 1);
      if (aspect < 0.5 || aspect > 2.0) continue;

      // 最小边界框尺寸
      if (bw < 4 || bh < 4) continue;

      // 填充率：area / (bw * bh)
      final fillRatio = area / (bw * bh);
      if (fillRatio < 0.3) continue; // 太稀疏

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
  /// 对齐 Python ColorBallDetector 双范围检测
  bool _isOrangeHsv(int r, int g, int b) {
    final h = _hue(r, g, b);
    final s = _saturation(r, g, b);
    final v = max(r, max(g, b));

    // 范围 1: 标准橙色 (H=5-22, S>=100, V>=100)
    if (h >= _hMin && h <= _hMax && s >= _sMin && v >= _vMin) return true;
    // 范围 2: 偏红橙，暖光下 (H=0-8, S>=120, V>=120)
    if (h >= 0 && h <= _h2Max && s >= _s2Min && v >= _v2Min) return true;
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

  /// 形态学 OPEN（腐蚀 + 膨胀）— 去除小噪点
  /// 对齐 Python cv2.MORPH_OPEN with 5x5 elliptical kernel
  void _morphOpen(Uint8List mask, int w, int h) {
    final buf = _morphBuf!;
    // 腐蚀：3x3 十字核（近似 5x5 椭圆）
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (mask[y * w + x] == 0) continue;
        bool erode = false;
        for (final (dy, dx) in [(0, -1), (0, 1), (-1, 0), (1, 0), (0, -2), (0, 2), (-2, 0), (2, 0)]) {
          final ny = y + dy, nx = x + dx;
          if (ny < 0 || ny >= h || nx < 0 || nx >= w || mask[ny * w + nx] == 0) {
            erode = true;
            break;
          }
        }
        buf[y * w + x] = erode ? 0 : 1;
      }
    }
    // 膨胀：恢复被腐蚀的区域
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (buf[y * w + x] == 1) continue;
        bool dilate = false;
        for (final (dy, dx) in [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
          final ny = y + dy, nx = x + dx;
          if (ny >= 0 && ny < h && nx >= 0 && nx < w && buf[ny * w + nx] == 1) {
            dilate = true;
            break;
          }
        }
        mask[y * w + x] = dilate ? 1 : 0;
      }
    }
  }

  /// 形态学 CLOSE（膨胀 + 腐蚀）— 填充小孔洞
  /// 对齐 Python cv2.MORPH_CLOSE with 5x5 elliptical kernel
  void _morphClose(Uint8List mask, int w, int h) {
    final buf = _morphBuf!;
    // 膨胀
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (mask[y * w + x] == 1) {
          buf[y * w + x] = 1;
          continue;
        }
        bool dilate = false;
        for (final (dy, dx) in [(0, -1), (0, 1), (-1, 0), (1, 0), (0, -2), (0, 2), (-2, 0), (2, 0)]) {
          final ny = y + dy, nx = x + dx;
          if (ny >= 0 && ny < h && nx >= 0 && nx < w && mask[ny * w + nx] == 1) {
            dilate = true;
            break;
          }
        }
        buf[y * w + x] = dilate ? 1 : 0;
      }
    }
    // 腐蚀
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (buf[y * w + x] == 0) {
          mask[y * w + x] = 0;
          continue;
        }
        bool erode = false;
        for (final (dy, dx) in [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
          final ny = y + dy, nx = x + dx;
          if (ny < 0 || ny >= h || nx < 0 || nx >= w || buf[ny * w + nx] == 0) {
            erode = true;
            break;
          }
        }
        mask[y * w + x] = erode ? 0 : 1;
      }
    }
  }

}
