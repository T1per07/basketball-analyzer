import 'dart:math';
import '../models/shot_event.dart';
import '../models/config.dart';

/// 投篮检测器 — 轨迹驱动 UP→DOWN 状态机
/// 对应 Python models/shot_detector.py
class ShotDetector {
  double _fps;
  int _frameCount = 0;

  // hoop_pos: [(center_x, center_y, frame, width, height, conf)]
  final List<(double, double, int, double, double, double)> _hoopPos = [];
  // ball_pos: [(center_x, center_y, frame, width, height, conf)]
  final List<(double, double, int, double, double, double)> _ballPos = [];

  // UP/DOWN 状态机
  bool _up = false;
  bool _down = false;
  int _upFrame = 0;
  int _downFrame = 0;

  // 投篮结果
  final List<ShotResult> _shotResults = [];
  int _lastShotFrame = -999;

  // 每个投篮对应的球位置快照
  final Map<int, List<(double, double, int, double, double, double)>>
      _shotBallPositions = {};

  // 篮筐锁定
  (double, double, double, double)? _lockedHoop; // cx, cy, w, h

  static const _maxBallPosAge = 30;
  static const _maxHoopPosCount = 25;

  ShotDetector({double fps = 30.0}) : _fps = fps; // ignore: prefer_initializing_formals

  void setFps(double fps) {
    if (fps > 0) _fps = fps;
  }

  int get totalShots => _shotResults.length;
  int get totalMade => _shotResults.where((s) => s.made).length;
  List<ShotResult> get shotResults => _shotResults;
  bool get hoopDetected => _hoopPos.isNotEmpty;
  Map<int, List<(double, double, int, double, double, double)>> get shotBallPositions => _shotBallPositions;
  double get fps => _fps;

  void updateHoop(int x, int y, {int w = 60, int h = 30, double conf = 0.5}) {
    if (w < 15 || h < 15) return;

    final cx = x + w / 2.0;
    final cy = y + h / 2.0;
    if (cx < 20 || cy < 15) return;

    if (_lockedHoop != null) {
      final (lx, ly, lw, lh) = _lockedHoop!;
      final dist = sqrt((cx - lx) * (cx - lx) + (cy - ly) * (cy - ly));
      final maxDist = max(lw, lh) * 2.5;
      if (dist > maxDist) return;
    }

    _lockedHoop = (cx, cy, w.toDouble(), h.toDouble());
    _hoopPos.add((cx, cy, _frameCount, w.toDouble(), h.toDouble(), conf));
    if (_hoopPos.length > _maxHoopPosCount) {
      _hoopPos.removeAt(0);
    }
  }

  /// 处理一帧检测结果
  ShotResult? processFrame(
    List<(double, double)> ballPositions,
    List<double>? ballSizes,
    List<double>? ballConfs, {
    int frameIndex = 0,
  }) {
    _frameCount = frameIndex;
    if (_hoopPos.isEmpty) return null;

    ballSizes ??= List.filled(ballPositions.length, 0.0);
    ballConfs ??= List.filled(ballPositions.length, 0.5);

    final hoopLast = _hoopPos.last;
    final hoopCx = hoopLast.$1;
    final hoopCy = hoopLast.$2;
    final hoopW = hoopLast.$4;
    final hoopH = hoopLast.$5;

    for (int i = 0; i < ballPositions.length; i++) {
      final (cx, cy) = ballPositions[i];
      final area = i < ballSizes.length ? ballSizes[i] : 0.0;
      final conf = i < ballConfs.length ? ballConfs[i] : 0.5;

      final inHoop = _inHoopRegion(cx, cy, hoopCx, hoopCy, hoopW, hoopH);
      if (conf < 0.25 && !(inHoop && conf > 0.1)) continue;

      final w = area > 0 ? sqrt(area) : 10.0;
      _ballPos.add((cx, cy, frameIndex, w, w, conf));
    }

    _cleanBallPos(frameIndex);
    return _shotDetection();
  }

  bool _inHoopRegion(
      double x, double y, double hcx, double hcy, double hw, double hh) {
    return (hcx - 2 * hw < x &&
        x < hcx + 2 * hw &&
        hcy - 1.5 * hh < y &&
        y < hcy + 1.0 * hh);
  }

  void _cleanBallPos(int frameCount) {
    if (_ballPos.length < 2) return;

    final (x1, y1, f1, w1, h1, c1) = _ballPos[_ballPos.length - 2];
    final (x2, y2, f2, w2, h2, c2) = _ballPos.last;

    final dist = sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
    final maxDist =
        w1 > 0 ? 4 * sqrt(w1 * w1 + h1 * h1) : 40.0;
    final fDif = f2 - f1;

    if (dist > maxDist && fDif < 5) {
      _ballPos.removeLast();
      return;
    }

    if (w2 > 0 && h2 > 0) {
      if ((w2 * 1.4 < h2) || (h2 * 1.4 < w2)) {
        _ballPos.removeLast();
        return;
      }
    }

    if (_ballPos.isNotEmpty &&
        frameCount - _ballPos.first.$3 > _maxBallPosAge) {
      _ballPos.removeAt(0);
    }
  }

  // ===== 投篮事件触发 =====

  bool _detectUp() {
    if (_ballPos.isEmpty || _hoopPos.isEmpty) return false;

    final (bx, by, _, _, _, _) = _ballPos.last;
    final (hcx, hcy, _, hw, hh, _) = _hoopPos.last;

    // 球在篮筐上方区域
    final x1 = hcx - 8 * hw;
    final x2 = hcx + 8 * hw;
    final y1 = hcy - 4 * hh;
    final y2 = hcy + 0.3 * hh;

    return x1 < bx && bx < x2 && y1 < by && by < y2;
  }

  bool _detectDown() {
    if (_ballPos.length < 2 || _hoopPos.isEmpty) return false;

    final by = _ballPos.last.$2;
    final prevBy = _ballPos[_ballPos.length - 2].$2;
    final hcy = _hoopPos.last.$2;
    final hh = _hoopPos.last.$5;

    // 球正在下降且经过篮筐水平附近
    return by > prevBy && prevBy < hcy + 0.5 * hh && by > hcy - 0.8 * hh;
  }

  // ===== 多方法命中检测 =====

  bool _checkScore() {
    if (_ballPos.length < 2 || _hoopPos.isEmpty) return false;

    final (hcx, hcy, _, hw, hh, _) = _hoopPos.last;
    int votes = 0;

    if (_methodATrajectory(hcx, hcy, hw, hh)) votes++;
    if (_methodBCrossing(hcx, hcy, hw, hh)) votes++;
    if (_methodCProximityDown(hcx, hcy, hw, hh)) votes++;

    return votes >= 2;
  }

  bool _methodATrajectory(
      double hcx, double hcy, double hw, double hh) {
    final rimHeight = hcy - 0.5 * hh;

    final xPts = <double>[];
    final yPts = <double>[];

    for (int i = _ballPos.length - 1; i >= 0; i--) {
      final (bx, by, _, _, _, _) = _ballPos[i];
      if (by < rimHeight) {
        xPts.add(bx);
        yPts.add(by);
        if (i + 1 < _ballPos.length) {
          xPts.add(_ballPos[i + 1].$1);
          yPts.add(_ballPos[i + 1].$2);
        }
        break;
      }
    }

    if (xPts.length < 2) return false;

    try {
      if (xPts.length >= 3) {
        final coeffs = _polyfit(xPts, yPts, 2);
        if (coeffs.length >= 3) {
          final a = coeffs[0], b = coeffs[1], c = coeffs[2];
          final discriminant = b * b - 4 * a * (c - rimHeight);
          if (discriminant >= 0) {
            final sqrtD = sqrt(discriminant);
            for (final predictedX in [
              (-b + sqrtD) / (2 * a),
              (-b - sqrtD) / (2 * a)
            ]) {
              if (_checkRimHit(predictedX, hcx, hw)) return true;
            }
          }
        }
      } else {
        // 线性
        final m = (yPts[1] - yPts[0]) / (xPts[1] - xPts[0]);
        final b = yPts[0] - m * xPts[0];
        if (m.abs() > 1e-6) {
          final predictedX = (rimHeight - b) / m;
          if (_checkRimHit(predictedX, hcx, hw)) return true;
        }
      }
    } catch (_) {}

    return false;
  }

  bool _checkRimHit(double predictedX, double hcx, double hw) {
    final rimX1 = hcx - 0.6 * hw;
    final rimX2 = hcx + 0.6 * hw;
    if (rimX1 < predictedX && predictedX < rimX2) return true;
    if (rimX1 - 20 < predictedX && predictedX < rimX2 + 20) return true;
    return false;
  }

  bool _methodBCrossing(
      double hcx, double hcy, double hw, double hh) {
    final rimTop = hcy - 0.5 * hh;
    final rimBottom = hcy + 0.5 * hh;

    final above = <int>[];
    final below = <int>[];
    final recent = _ballPos.length > 20
        ? _ballPos.sublist(_ballPos.length - 20)
        : _ballPos;

    for (int i = 0; i < recent.length; i++) {
      final (x, y, _, _, _, _) = recent[i];
      if ((x - hcx).abs() < hw * 3.0) {
        if (y < rimTop) {
          above.add(i);
        } else if (y > rimBottom) {
          below.add(i);
        }
      }
    }

    for (final ai in above) {
      for (final bi in below) {
        if (bi <= ai || bi - ai > 15) continue;
        bool valid = true;
        for (int k = ai; k <= bi; k++) {
          if ((recent[k].$1 - hcx).abs() > hw * 4.0) {
            valid = false;
            break;
          }
        }
        if (valid) return true;
      }
    }

    return false;
  }

  bool _methodCProximityDown(
      double hcx, double hcy, double hw, double hh) {
    final rimLeft = hcx - 1.5 * hw;
    final rimRight = hcx + 1.5 * hw;
    final rimTop = hcy - 1.0 * hh;
    final rimBottom = hcy + 1.0 * hh;

    final inRim = <(double, double)>[];
    final recent = _ballPos.length > 15
        ? _ballPos.sublist(_ballPos.length - 15)
        : _ballPos;

    for (final (x, y, _, _, _, _) in recent) {
      if (rimLeft < x &&
          x < rimRight &&
          rimTop < y &&
          y < rimBottom) {
        inRim.add((x, y));
      }
    }

    if (inRim.length < 2) return false;

    for (int i = 1; i < inRim.length; i++) {
      if (inRim[i].$2 > inRim[i - 1].$2 + 1) return true;
    }

    return false;
  }

  // ===== 主检测逻辑 =====

  ShotResult? _shotDetection() {
    if (_hoopPos.isEmpty || _ballPos.isEmpty) return null;

    // 步骤 1: 检测 UP
    if (!_up) {
      _up = _detectUp();
      if (_up) _upFrame = _ballPos.last.$3;
    }

    // 步骤 2: 检测 DOWN
    if (_up && !_down) {
      _down = _detectDown();
      if (_down) _downFrame = _ballPos.last.$3;
    }

    // 步骤 3: 检查投篮
    if (_up && _down && _upFrame < _downFrame) {
      final cooldown = max(
        AppConfig.shot.cooldownMinFrames,
        (AppConfig.shot.cooldownFpsRatio * _fps).round(),
      );
      if (_frameCount - _lastShotFrame < cooldown) {
        _up = false;
        _down = false;
        return null;
      }

      bool made = _checkScore();

      final (entryAngle, releaseAngle) = _computeAngles();
      final hcx = _hoopPos.last.$1;
      final hw = _hoopPos.last.$4;
      final confidence = _computeShotConfidence();

      final result = ShotResult(
        made: made,
        frame: _frameCount,
        hoopX: hcx.round(),
        hoopWidth: hw.round(),
        ballId: 0,
        confidence: confidence,
        hasApex: _hasApex(),
        rimOverlap: made,
        entryAngle: entryAngle,
        releaseAngle: releaseAngle,
      );

      _shotResults.add(result);
      final shotIdx = _shotResults.length - 1;
      _shotBallPositions[shotIdx] = List.from(_ballPos);
      _lastShotFrame = _frameCount;
      _up = false;
      _down = false;
      return result;
    }

    return null;
  }

  bool _hasApex() {
    if (_ballPos.length < 5) return false;
    final ys = _ballPos
        .skip(max(0, _ballPos.length - 20))
        .map((p) => p.$2)
        .toList();
    final minIdx = ys.indexOf(ys.reduce(min));
    return minIdx >= 2 && minIdx <= ys.length - 3;
  }

  (double, double) _computeAngles() {
    if (_ballPos.length < 3) return (0.0, 0.0);

    final recent = _ballPos.length > 10
        ? _ballPos.sublist(_ballPos.length - 10)
        : _ballPos;
    if (recent.length < 3) return (0.0, 0.0);

    final xs = recent.map((p) => p.$1).toList();
    final ys = recent.map((p) => p.$2).toList();

    try {
      final coeffs = _polyfit(xs, ys, 2);
      if (coeffs.length >= 3) {
        final a = coeffs[0], b = coeffs[1];
        final hcx = _hoopPos.isNotEmpty ? _hoopPos.last.$1 : xs.last;
        final slope = 2 * a * hcx + b;
        final entryAngle = (atan(slope)).abs() * 180 / pi;

        final slopeRelease = 2 * a * xs[0] + b;
        final releaseAngle = (atan(slopeRelease)).abs() * 180 / pi;

        return (entryAngle, releaseAngle);
      }
    } catch (_) {}
    return (0.0, 0.0);
  }

  double _computeShotConfidence() {
    final n = _ballPos.length;
    final scores = <double>[];

    if (n < 5) {
      scores.add(0.3);
    } else if (n < 60) {
      scores.add(1.0);
    } else {
      scores.add(0.7);
    }

    if (_ballPos.length >= 4) {
      final ys = _ballPos
          .skip(max(0, _ballPos.length - 15))
          .map((p) => p.$2)
          .toList();
      final d2 = <double>[];
      for (int i = 2; i < ys.length; i++) {
        d2.add(ys[i] - 2 * ys[i - 1] + ys[i - 2]);
      }
      if (d2.isNotEmpty) {
        final mean = d2.reduce((a, b) => a + b) / d2.length;
        final rmse =
            sqrt(d2.map((d) => (d - mean) * (d - mean)).reduce((a, b) => a + b) /
                d2.length);
        scores.add(max(0.0, 1.0 - rmse / 20.0));
      } else {
        scores.add(0.5);
      }
    } else {
      scores.add(0.5);
    }

    scores.add(_hasApex() ? 1.0 : 0.4);
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  /// 多项式拟合（简化版 polyfit）
  List<double> _polyfit(List<double> x, List<double> y, int degree) {
    final n = x.length;
    if (n < degree + 1) throw Exception('Not enough points');

    // 构建正规方程 X^T X c = X^T y
    final cols = degree + 1;
    final ata = List.generate(cols, (_) => List.filled(cols, 0.0));
    final aty = List.filled(cols, 0.0);

    for (int i = 0; i < n; i++) {
      for (int j = 0; j < cols; j++) {
        for (int k = 0; k < cols; k++) {
          ata[j][k] += pow(x[i], j + k).toDouble();
        }
        aty[j] += pow(x[i], j).toDouble() * y[i];
      }
    }

    // 高斯消元
    for (int i = 0; i < cols; i++) {
      // 主元选择
      int maxRow = i;
      for (int k = i + 1; k < cols; k++) {
        if (ata[k][i].abs() > ata[maxRow][i].abs()) maxRow = k;
      }
      final tmp = ata[i];
      ata[i] = ata[maxRow];
      ata[maxRow] = tmp;
      final tmpY = aty[i];
      aty[i] = aty[maxRow];
      aty[maxRow] = tmpY;

      if (ata[i][i].abs() < 1e-12) throw Exception('Singular matrix');

      for (int k = i + 1; k < cols; k++) {
        final factor = ata[k][i] / ata[i][i];
        for (int j = i; j < cols; j++) {
          ata[k][j] -= factor * ata[i][j];
        }
        aty[k] -= factor * aty[i];
      }
    }

    // 回代
    final result = List.filled(cols, 0.0);
    for (int i = cols - 1; i >= 0; i--) {
      result[i] = aty[i];
      for (int j = i + 1; j < cols; j++) {
        result[i] -= ata[i][j] * result[j];
      }
      result[i] /= ata[i][i];
    }

    return result;
  }

  void reset() {
    _hoopPos.clear();
    _ballPos.clear();
    _shotResults.clear();
    _shotBallPositions.clear();
    _lockedHoop = null;
    _up = false;
    _down = false;
    _upFrame = 0;
    _downFrame = 0;
    _lastShotFrame = -999;
    _frameCount = 0;
  }
}
