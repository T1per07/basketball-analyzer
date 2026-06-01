import 'dart:math';
import 'dart:typed_data';

/// 篮筐检测器 — 颜色检测 + 连通组件分析 + 校准跟踪
class HoopDetector {
  final List<(int, int, int, int)> _calibrationBuffer = [];
  bool _calibrated = false;
  (int, int, int, int)? _hoopBox; // x, y, w, h
  (int, int, int, int)? _lockedBox;
  static const _calibFrames = 18; // 增加校准帧数要求（更可靠的锁定）
  static const _calibMaxAttempts = 90; // 超时：90帧未完成校准则放弃
  int _calibAttemptCount = 0;

  // Pre-allocated buffers for connected components analysis in
  // _findHoopCandidates. Reused across calls to avoid per-call
  // allocation of Uint8List(rw*rh) and Int32List(rw*rh).
  Uint8List? _ccMask;
  Int32List? _ccLabels;
  int _ccBufSize = 0;

  bool get isCalibrated => _calibrated;

  (int, int)? get hoopPosition {
    if (_hoopBox == null) return null;
    final (x, y, w, h) = _hoopBox!;
    return (x + w ~/ 2, y + h ~/ 2);
  }

  (int, int, int, int)? get hoopBox => _hoopBox;

  /// 处理一帧，返回篮筐中心位置
  (int, int)? detect(Uint8List frameBgr, int width, int height) {
    if (!_calibrated) {
      return _calibrate(frameBgr, width, height);
    }
    return _track(frameBgr, width, height);
  }

  (int, int)? _calibrate(Uint8List frameBgr, int width, int height) {
    _calibAttemptCount++;

    final candidates = _findHoopCandidates(frameBgr, width, height, 0, 0, width, height);
    if (candidates.isNotEmpty) {
      // 选择最接近矩形（宽>高）且面积合理的候选
      candidates.sort((a, b) {
        final aspectA = a.$3 / max(a.$4, 1); // 宽高比，篮筐应该 > 1.5
        final aspectB = b.$3 / max(b.$4, 1);
        // 篮筐特征：宽高比接近 2:1，面积中等
        final scoreA = (aspectA - 2.0).abs() * 2 + (a.$3 * a.$4) / 5000;
        final scoreB = (aspectB - 2.0).abs() * 2 + (b.$3 * b.$4) / 5000;
        return scoreA.compareTo(scoreB);
      });
      final best = candidates.first;
      _calibrationBuffer.add((best.$1, best.$2, best.$3, best.$4));
    }

    if (_calibrationBuffer.length >= _calibFrames) {
      _finishCalibration();
    } else if (_calibAttemptCount >= _calibMaxAttempts && _calibrationBuffer.isNotEmpty) {
      // 超时：用已收集的数据完成校准（即使不足 _calibFrames 帧）
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
        .where((b) => (b.$1 - medX).abs() < 60 && (b.$2 - medY).abs() < 50)
        .toList();
    // 要求至少 60% 的校准帧通过一致性检查
    final use = filtered.length >= _calibrationBuffer.length * 0.6
        ? filtered
        : <(int, int, int, int)>[];
    if (use.isEmpty) return;

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

    final candidates = _findHoopCandidates(frameBgr, width, height, x1, y1, x2, y2);

    if (candidates.isNotEmpty) {
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
      final maxDist = (lw * 0.4) * (lw * 0.4);

      if (dist < maxDist) {
        if (bw < 12 || bh < 6) return hoopPosition;
        const alpha = 0.08;
        final newX = (alpha * bx + (1 - alpha) * lx).round();
        final newY = (alpha * by + (1 - alpha) * ly).round();
        final newW = (alpha * bw + (1 - alpha) * lw).round();
        final newH = (alpha * bh + (1 - alpha) * lh).round();
        _hoopBox = (newX, newY, newW, newH);
        _lockedBox = _hoopBox;
      }
    }

    return hoopPosition;
  }

  /// 用连通组件分析找篮筐候选
  List<(int, int, int, int)> _findHoopCandidates(
    Uint8List frameBgr, int frameW, int frameH,
    int roiX1, int roiY1, int roiX2, int roiY2,
  ) {
    final rw = roiX2 - roiX1;
    final rh = roiY2 - roiY1;
    if (rw <= 0 || rh <= 0) return [];

    // 生成篮筐颜色掩码 — reuse pre-allocated buffers
    final size = rw * rh;
    if (_ccMask == null || _ccBufSize < size) {
      _ccMask = Uint8List(size);
      _ccLabels = Int32List(size);
      _ccBufSize = size;
    } else {
      _ccMask!.fillRange(0, size, 0);
      _ccLabels!.fillRange(0, size, 0);
    }
    final mask = _ccMask!;
    for (int y = 0; y < rh; y++) {
      for (int x = 0; x < rw; x++) {
        final fx = roiX1 + x;
        final fy = roiY1 + y;
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

    // 连通组件分析（Union-Find 两遍扫描）— labels pre-allocated above
    final labels = _ccLabels!;
    final parent = <int>[0];
    final count = <int>[0];
    int nextLabel = 1;

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

    for (int y = 0; y < rh; y++) {
      for (int x = 0; x < rw; x++) {
        if (mask[y * rw + x] == 0) continue;

        int left = 0, above = 0;
        if (x > 0) left = labels[y * rw + (x - 1)];
        if (y > 0) above = labels[(y - 1) * rw + x];

        if (left == 0 && above == 0) {
          labels[y * rw + x] = nextLabel;
          parent.add(nextLabel);
          count.add(1);
          nextLabel++;
        } else if (left != 0 && above == 0) {
          labels[y * rw + x] = find(left);
          count[find(left)]++;
        } else if (left == 0 && above != 0) {
          labels[y * rw + x] = find(above);
          count[find(above)]++;
        } else {
          union(left, above);
          final root = find(left);
          labels[y * rw + x] = root;
          count[root]++;
        }
      }
    }

    // 收集边界框
    final bboxes = <int, List<int>>{};
    for (int y = 0; y < rh; y++) {
      for (int x = 0; x < rw; x++) {
        if (labels[y * rw + x] == 0) continue;
        final root = find(labels[y * rw + x]);
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

    // 过滤：面积、宽高比
    final totalPixels = rw * rh;
    final minArea = max(8, (totalPixels * 0.0005).round());
    final maxArea = (totalPixels * 0.1).round();
    final results = <(int, int, int, int)>[];

    for (final bb in bboxes.values) {
      final area = bb[4];
      if (area < minArea || area > maxArea) continue;

      final bw = bb[2] - bb[0] + 1;
      final bh = bb[3] - bb[1] + 1;
      final aspect = bw / max(bh, 1);
      // 篮筐特征：宽 > 高，宽高比 1.0-5.0
      if (aspect < 1.0 || aspect > 5.0) continue;
      // 最小尺寸
      if (bw < 10 || bh < 5) continue;

      results.add((bb[0] + roiX1, bb[1] + roiY1, bw, bh));
    }

    return results;
  }

  /// 检查 RGB 是否在篮筐颜色范围内（红/橙红）
  /// 注意排除篮球橙色（G>70）以避免颜色污染
  /// 收紧条件：要求更高的 R 值和更低的 G/B 比值
  bool _isHoopColor(int r, int g, int b) {
    // 篮筐红色：R 高，G 低，B 低
    // 排除篮球橙色、肤色、木地板
    if (g > 70) return false; // 排除篮球橙色
    if (b > 100) return false; // 排除紫色/粉色干扰
    // 严格红色：R > 140, R > G * 1.5
    if (r > 140 && r > g * 1.5 && b < 80) return true;
    // 深红色：R > 160, G < 60
    if (r > 160 && g < 60 && b < 70) return true;
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
    _calibAttemptCount = 0;
  }
}
