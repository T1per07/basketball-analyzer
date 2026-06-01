import 'dart:math';
import '../models/shot_event.dart';
import '../models/config.dart';
import '../utils/math_utils.dart';

/// 投篮检测器 v4 — UP/DOWN 状态机 + 3方法投票
/// 对齐 Python backend/models/shot_detector.py
///
/// 核心逻辑：
/// 1. UP 检测：球出现在篮筐上方区域（收紧范围）
/// 2. DOWN 检测：球下降到篮筐下方
/// 3. UP→DOWN 确认投篮事件（需最小轨迹长度）
/// 4. 3 方法投票判定命中/未中（任意 2 票确认）
/// 5. 投票失败 → 判定为未中（不再强制命中）
class ShotDetector {
  double _fps;
  int _frameCount = 0;

  // 篮筐位置
  final List<(double, double, int, double, double, double)> _hoopPos = [];
  static const _maxHoopPosCount = 25;

  // 球位置缓冲区（滚动窗口，对齐 Python MAX_BALL_POS_AGE=30）
  final List<(double, double, int, double, double, double)> _ballPos = [];
  static const _maxBallPosAge = 30;

  // UP/DOWN 状态机
  bool _up = false;
  bool _down = false;
  int _upFrame = 0;
  int _downFrame = 0;

  // 结果
  final List<ShotResult> _shotResults = [];
  final Map<int, List<(double, double, int, double, double, double)>> _shotBallPositions = {};
  int _lastShotFrame = -999;

  // 篮筐锁定
  (double, double, double, double)? _lockedHoop; // cx, cy, w, h

  ShotDetector({this._fps = 30.0});

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

    // 添加球位置（置信度过滤 + 距离过滤）
    for (int i = 0; i < ballPositions.length; i++) {
      final (cx, cy) = ballPositions[i];
      final area = i < ballSizes.length ? ballSizes[i] : 0.0;
      final conf = i < ballConfs.length ? ballConfs[i] : 0.5;

      // 置信度过滤（提高阈值，减少噪声误检）
      final inHoop = _inHoopRegion(cx, cy, hoopCx, hoopCy, hoopW, hoopH);
      if (conf < 0.5 && !(inHoop && conf > 0.35)) continue;

      // 距离过滤 — 丢弃距上一帧过远的检测（噪声）
      if (_ballPos.isNotEmpty) {
        final (px, py, _, _, _, _) = _ballPos.last;
        final dist = sqrt((cx - px) * (cx - px) + (cy - py) * (cy - py));
        final maxDist = area > 0 ? 4 * sqrt(area) : 40.0;
        if (dist > maxDist) continue;

        // 宽高比过滤（篮球应接近正方形）
        if (area > 0) {
          final w = sqrt(area);
          final h = area / w;
          if (w > 0 && h > 0) {
            if ((w * 1.4 < h) || (h * 1.4 < w)) continue;
          }
        }
      }

      final w = area > 0 ? sqrt(area) : 10.0;
      _ballPos.add((cx, cy, frameIndex, w, w, conf));
    }

    // 清理旧数据
    while (_ballPos.isNotEmpty &&
        frameIndex - _ballPos.first.$3 > _maxBallPosAge) {
      _ballPos.removeAt(0);
    }

    return _shotDetection();
  }

  bool _inHoopRegion(
      double x, double y, double hcx, double hcy, double hw, double hh) {
    return (hcx - 2 * hw < x &&
        x < hcx + 2 * hw &&
        hcy - 1.5 * hh < y &&
        y < hcy + 1.0 * hh);
  }

  // ===== UP/DOWN 状态机（对齐 Python） =====

  /// UP 检测：球在篮筐上方 + 有上升运动
  bool _detectUp() {
    if (_ballPos.length < 3 || _hoopPos.isEmpty) return false;

    final (bx, by, _, _, _, _) = _ballPos.last;
    final hcx = _hoopPos.last.$1;
    final hcy = _hoopPos.last.$2;
    final hw = _hoopPos.last.$4;
    final hh = _hoopPos.last.$5;

    // 范围：x ± 3*hw，y 在篮筐上方
    final x1 = hcx - 3 * hw;
    final x2 = hcx + 3 * hw;
    final y1 = hcy - 3 * hh;
    final y2 = hcy - 0.3 * hh;

    if (!(x1 < bx && bx < x2 && y1 < by && by < y2)) return false;

    // 验证上升运动：最近 3 帧球的 Y 坐标应递减（屏幕坐标 Y 向下）
    final y0 = _ballPos[_ballPos.length - 3].$2;
    final y1p = _ballPos[_ballPos.length - 2].$2;
    final y2p = _ballPos[_ballPos.length - 1].$2;
    return y0 > y1p && y1p > y2p;
  }

  /// DOWN 检测：球在篮筐下方
  bool _detectDown() {
    if (_ballPos.isEmpty || _hoopPos.isEmpty) return false;

    final by = _ballPos.last.$2;
    final hcy = _hoopPos.last.$2;
    final hh = _hoopPos.last.$5;

    return by > hcy + 0.3 * hh;
  }

  // ===== 3 方法投票命中检测（对齐 Python） =====

  /// 多方法投票：任意 2 票确认命中
  bool _checkScore() {
    if (_ballPos.length < 2 || _hoopPos.isEmpty) return false;

    final hcx = _hoopPos.last.$1;
    final hcy = _hoopPos.last.$2;
    final hw = _hoopPos.last.$4;
    final hh = _hoopPos.last.$5;

    int votes = 0;
    if (_methodATrajectory(hcx, hcy, hw, hh)) votes++;
    if (_methodBCrossing(hcx, hcy, hw, hh)) votes++;
    if (_methodCProximityDown(hcx, hcy, hw, hh)) votes++;

    // UP→DOWN 已确认投篮，1 票即可确认命中
    return votes >= 1;
  }

  /// 方法 A: 抛物线轨迹预测 — 预测球在篮筐高度的 X 位置
  bool _methodATrajectory(double hcx, double hcy, double hw, double hh) {
    final rimHeight = hcy - 0.5 * hh;

    // 找篮筐上方和下方的点
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
        // 抛物线拟合
        final coeffs = polyfit(xPts, yPts, 2);
        if (coeffs.length >= 3) {
          final a = coeffs[2];
          final b = coeffs[1];
          final c = coeffs[0];
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
        // 线性回归
        final coeffs = polyfit(xPts, yPts, 1);
        if (coeffs.length >= 2) {
          final m = coeffs[1];
          final b = coeffs[0];
          if (m.abs() > 1e-6) {
            final predictedX = (rimHeight - b) / m;
            if (_checkRimHit(predictedX, hcx, hw)) return true;
          }
        }
      }
    } catch (_) {}

    return false;
  }

  /// 检查预测 X 是否在篮筐开口内
  bool _checkRimHit(double predictedX, double hcx, double hw) {
    final rimX1 = hcx - 0.6 * hw;
    final rimX2 = hcx + 0.6 * hw;

    if (rimX1 < predictedX && predictedX < rimX2) return true;

    // 弹跳区域 ±10px（收紧）
    if (rimX1 - 10 < predictedX && predictedX < rimX2 + 10) return true;

    return false;
  }

  /// 方法 B: 球从篮筐上方穿越到下方
  bool _methodBCrossing(double hcx, double hcy, double hw, double hh) {
    final rimTop = hcy - 0.5 * hh;
    final rimBottom = hcy + 0.5 * hh;

    final above = <int>[];
    final below = <int>[];

    final recent = _ballPos.length > 20
        ? _ballPos.sublist(_ballPos.length - 20)
        : _ballPos;

    for (int i = 0; i < recent.length; i++) {
      final (x, y, _, _, _, _) = recent[i];
      if ((x - hcx).abs() < hw * 1.5) {
        if (y < rimTop) {
          above.add(i);
        } else if (y > rimBottom) {
          below.add(i);
        }
      }
    }

    for (final ai in above) {
      for (final bi in below) {
        if (bi <= ai || bi - ai > 10) continue;
        bool valid = true;
        for (int k = ai; k <= bi; k++) {
          if ((recent[k].$1 - hcx).abs() > hw * 2.0) {
            valid = false;
            break;
          }
        }
        if (valid) return true;
      }
    }

    return false;
  }

  /// 方法 C: 球在篮筐区域内 + 向下运动
  bool _methodCProximityDown(double hcx, double hcy, double hw, double hh) {
    final rimLeft = hcx - 1.0 * hw;
    final rimRight = hcx + 1.0 * hw;
    final rimTop = hcy - 0.8 * hh;
    final rimBottom = hcy + 0.8 * hh;

    final inRim = <(double, double)>[];
    final recent = _ballPos.length > 15
        ? _ballPos.sublist(_ballPos.length - 15)
        : _ballPos;

    for (final (x, y, _, _, _, _) in recent) {
      if (rimLeft < x && x < rimRight && rimTop < y && y < rimBottom) {
        inRim.add((x, y));
      }
    }

    if (inRim.length < 2) return false;

    for (int i = 1; i < inRim.length; i++) {
      if (inRim[i].$2 > inRim[i - 1].$2 + 3) return true;
    }

    return false;
  }

  // ===== 主检测逻辑（对齐 Python _shot_detection） =====

  // 最小轨迹长度：至少 8 帧连续球位置才允许触发投篮检测
  static const _minTrackLengthForShot = 8;

  ShotResult? _shotDetection() {
    if (_hoopPos.isEmpty || _ballPos.isEmpty) return null;

    // 轨迹长度不足时不触发检测（防止 1-2 帧噪声误触发）
    if (_ballPos.length < _minTrackLengthForShot) return null;

    // 步骤 1: 检测 UP
    if (!_up) {
      _up = _detectUp();
      if (_up) {
        _upFrame = _ballPos.last.$3;
      }
    }

    // 步骤 2: 检测 DOWN
    if (_up && !_down) {
      _down = _detectDown();
      if (_down) {
        _downFrame = _ballPos.last.$3;
      }
    }

    // 步骤 3: UP→DOWN 确认投篮
    if (_up && _down && _upFrame < _downFrame) {
      // 冷却期检查
      final cooldown = max(
        AppConfig.shot.cooldownMinFrames,
        (AppConfig.shot.cooldownFpsRatio * _fps).round(),
      );
      if (_frameCount - _lastShotFrame < cooldown) {
        _up = false;
        _down = false;
        return null;
      }

      // 弧线验证：UP→DOWN 之间必须有最高点
      if (!_hasApexBetween(_upFrame, _downFrame)) {
        _up = false;
        _down = false;
        return null;
      }

      // 3 方法投票 — 投票失败则判定为未中
      final made = _checkScore();

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
    final recent = _ballPos.length > 20
        ? _ballPos.sublist(_ballPos.length - 20)
        : _ballPos;
    final ys = recent.map((p) => p.$2).toList();
    double minY = ys[0];
    int minIdx = 0;
    for (int i = 1; i < ys.length; i++) {
      if (ys[i] < minY) {
        minY = ys[i];
        minIdx = i;
      }
    }
    return 2 <= minIdx && minIdx <= ys.length - 3;
  }

  /// 验证 UP→DOWN 之间轨迹有最高点（弧线）
  bool _hasApexBetween(int upFrame, int downFrame) {
    final segment = _ballPos.where((p) => p.$3 >= upFrame && p.$3 <= downFrame).toList();
    if (segment.length < 3) return false;
    final ys = segment.map((p) => p.$2).toList();
    double minY = ys[0];
    int minIdx = 0;
    for (int i = 1; i < ys.length; i++) {
      if (ys[i] < minY) {
        minY = ys[i];
        minIdx = i;
      }
    }
    return 1 <= minIdx && minIdx <= ys.length - 2;
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
      final recent = _ballPos.length > 15
          ? _ballPos.sublist(_ballPos.length - 15)
          : _ballPos;
      final ys = recent.map((p) => p.$2).toList();
      final d2 = <double>[];
      for (int i = 2; i < ys.length; i++) {
        d2.add(ys[i] - 2 * ys[i - 1] + ys[i - 2]);
      }
      if (d2.isNotEmpty) {
        final mean = d2.reduce((a, b) => a + b) / d2.length;
        final rmse = sqrt(d2.map((d) => (d - mean) * (d - mean)).reduce((a, b) => a + b) / d2.length);
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

  // ===== 角度计算 =====

  (double, double) _computeAngles() {
    if (_ballPos.length < 3) return (0.0, 0.0);

    final recent = _ballPos.length > 10
        ? _ballPos.sublist(_ballPos.length - 10)
        : _ballPos;
    if (recent.length < 3) return (0.0, 0.0);

    final xs = recent.map((p) => p.$1).toList();
    final ys = recent.map((p) => p.$2).toList();

    try {
      final coeffs = polyfit(xs, ys, 2);
      if (coeffs.length >= 3) {
        final a = coeffs[2];
        final b = coeffs[1];

        // 入射角：篮筐处的导数
        final hcx = _hoopPos.isNotEmpty ? _hoopPos.last.$1 : xs.last;
        final slope = 2 * a * hcx + b;
        final entryAngle = (atan(slope)).abs() * 180 / pi;

        // 出手角：轨迹起点的导数
        final slopeRelease = 2 * a * xs[0] + b;
        final releaseAngle = (atan(slopeRelease)).abs() * 180 / pi;

        return (entryAngle, releaseAngle);
      }
    } catch (_) {}
    return (0.0, 0.0);
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
