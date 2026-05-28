import 'dart:math';
import '../models/shot_event.dart';
import '../models/config.dart';

/// 投篮检测器 — 轨迹驱动 + 置信度评分
/// 替代旧的逐帧 UP/DOWN 状态机
///
/// 核心逻辑：
/// 1. 缓冲完整轨迹（非滚动窗口）
/// 2. 检测弧线最高点 (apex) 作为投篮触发
/// 3. 球下降经过篮筐水平或超时时评估投篮
/// 4. 置信度评分替代 2/3 投票
class ShotDetector {
  double _fps;
  int _frameCount = 0;

  // 篮筐位置
  final List<(double, double, int, double, double, double)> _hoopPos = [];
  static const _maxHoopPosCount = 25;

  // 轨迹缓冲区 — 保存完整飞行弧线
  final List<(double, double, int, double, double, double)> _trajectoryBuffer = [];
  static const _maxTrajectorySize = 200;

  // 状态
  bool _apexDetected = false;
  int _apexFrame = 0;
  int _lastShotFrame = -999;
  int _lastRealDetectionFrame = -999; // 最后一次真实球检测帧（非轨迹延续）

  // 结果
  final List<ShotResult> _shotResults = [];
  final Map<int, List<(double, double, int, double, double, double)>> _shotBallPositions = {};

  // 篮筐锁定
  (double, double, double, double)? _lockedHoop; // cx, cy, w, h

  ShotDetector({double fps = 30.0}) : _fps = fps;

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

    // 添加球位置到轨迹缓冲区
    for (int i = 0; i < ballPositions.length; i++) {
      final (cx, cy) = ballPositions[i];
      final area = i < ballSizes.length ? ballSizes[i] : 0.0;
      final conf = i < ballConfs.length ? ballConfs[i] : 0.5;

      // 置信度过滤
      final inHoop = _inHoopRegion(cx, cy, hoopCx, hoopCy, hoopW, hoopH);
      if (conf < 0.25 && !(inHoop && conf > 0.1)) continue;

      // 距离过滤 — 丢弃距上一帧过远的检测（噪声）
      if (_trajectoryBuffer.isNotEmpty) {
        final (px, py, _, _, _, _) = _trajectoryBuffer.last;
        final dist = sqrt((cx - px) * (cx - px) + (cy - py) * (cy - py));
        final maxDist = area > 0 ? 4 * sqrt(area) : 80.0;
        if (dist > maxDist && frameIndex - _trajectoryBuffer.last.$3 < 5) continue;
      }

      final w = area > 0 ? sqrt(area) : 10.0;
      _trajectoryBuffer.add((cx, cy, frameIndex, w, w, conf));
      _lastRealDetectionFrame = frameIndex;
    }

    // 如果没有球检测但 apex 已检测到且球在篮筐附近，用最后位置延续轨迹
    if (ballPositions.isEmpty && _apexDetected && _trajectoryBuffer.isNotEmpty) {
      final (lx, ly, _, _, _, _) = _trajectoryBuffer.last;
      final distToHoop = sqrt((lx - hoopCx) * (lx - hoopCx) + (ly - hoopCy) * (ly - hoopCy));
      if (distToHoop < hoopW * 4) {
        // 用最后已知位置延续（球可能在篮筐后/网中消失）
        _trajectoryBuffer.add((lx, ly, frameIndex, 0, 0, 0.1));
      }
    }

    // 清理旧数据
    while (_trajectoryBuffer.length > _maxTrajectorySize) {
      _trajectoryBuffer.removeAt(0);
    }
    // 移除超时数据（超过 5 秒）
    while (_trajectoryBuffer.isNotEmpty &&
        frameIndex - _trajectoryBuffer.first.$3 > (_fps * 5).round()) {
      _trajectoryBuffer.removeAt(0);
    }

    return _detectShot();
  }

  bool _inHoopRegion(
      double x, double y, double hcx, double hcy, double hw, double hh) {
    return (hcx - 2 * hw < x &&
        x < hcx + 2 * hw &&
        hcy - 1.5 * hh < y &&
        y < hcy + 1.0 * hh);
  }

  // ===== 轨迹驱动投篮检测 =====

  ShotResult? _detectShot() {
    if (_hoopPos.isEmpty || _trajectoryBuffer.length < 5) return null;

    final (hcx, hcy, _, hw, hh, _) = _hoopPos.last;

    // 步骤 1: 检测弧线最高点 (apex)
    if (!_apexDetected) {
      if (_detectApex(hcy, hh)) {
        _apexDetected = true;
        _apexFrame = _trajectoryBuffer.last.$3;
      }
    }

    // 步骤 2: apex 后检查投篮结束条件
    if (_apexDetected) {
      final framesSinceApex = _frameCount - _apexFrame;
      final maxShotDuration = (_fps * 3).round();

      // 结束条件: 球下降经过篮筐水平 或 球进入篮筐区域后消失 或 超时
      bool ballBelowHoop = _ballBelowHoop(hcy, hh);
      bool ballNearHoopAndLost = _ballNearHoopAndLost(hcx, hcy, hw, hh);
      bool timeout = framesSinceApex > maxShotDuration;

      if (ballBelowHoop || ballNearHoopAndLost || timeout) {
        // 冷却期检查
        final cooldown = max(
          AppConfig.shot.cooldownMinFrames,
          (AppConfig.shot.cooldownFpsRatio * _fps).round(),
        );
        if (_frameCount - _lastShotFrame < cooldown) {
          _resetDetection();
          return null;
        }

        // 评估投篮
        final (made, confidence) = _evaluateShot(hcx, hcy, hw, hh);

        final (entryAngle, releaseAngle) = _computeAngles();
        final result = ShotResult(
          made: made,
          frame: _frameCount,
          hoopX: hcx.round(),
          hoopWidth: hw.round(),
          ballId: 0,
          confidence: confidence,
          hasApex: true,
          rimOverlap: made,
          entryAngle: entryAngle,
          releaseAngle: releaseAngle,
        );

        _shotResults.add(result);
        final shotIdx = _shotResults.length - 1;
        _shotBallPositions[shotIdx] = List.from(_trajectoryBuffer);
        _lastShotFrame = _frameCount;
        _resetDetection();
        return result;
      }
    }

    return null;
  }

  /// 检测弧线最高点 — 球从上升转为下降
  bool _detectApex(double hcy, double hh) {
    if (_trajectoryBuffer.length < 5) return false;

    // 搜索整个轨迹缓冲区找最低 y（最高点，屏幕坐标 y 向下）
    double minY = double.infinity;
    int minIdx = 0;
    for (int i = 0; i < _trajectoryBuffer.length; i++) {
      if (_trajectoryBuffer[i].$2 < minY) {
        minY = _trajectoryBuffer[i].$2;
        minIdx = i;
      }
    }

    // apex 前必须有足够的上升轨迹，后必须有足够的下降轨迹
    if (minIdx < 2 || minIdx >= _trajectoryBuffer.length - 2) return false;

    // 取 apex 前后较大范围均值（前5后5，或全部可用点）
    final beforeStart = max(0, minIdx - 5);
    final afterEnd = min(_trajectoryBuffer.length, minIdx + 6);
    final beforeApex = _trajectoryBuffer.sublist(beforeStart, minIdx);
    final afterApex = _trajectoryBuffer.sublist(minIdx + 1, afterEnd);

    if (beforeApex.isEmpty || afterApex.isEmpty) return false;

    final avgBefore = beforeApex.map((p) => p.$2).reduce((a, b) => a + b) / beforeApex.length;
    final avgAfter = afterApex.map((p) => p.$2).reduce((a, b) => a + b) / afterApex.length;

    // 球在上升（y 减小）然后下降（y 增大）
    bool hasApex = avgAfter > minY && avgBefore > minY;

    // apex 应该在篮筐上方附近（给一定容差）
    bool apexNearHoop = minY < hcy + hh * 2;

    // 最小弧线高度（排除运球和传球）— 用首尾差而非 apex 附近
    final firstY = _trajectoryBuffer.first.$2;
    final lastY = _trajectoryBuffer.last.$2;
    double totalArc = (firstY - minY).abs();
    bool minArc = totalArc > 20;

    return hasApex && apexNearHoop && minArc;
  }

  /// 检查球是否下降到篮筐水平以下
  bool _ballBelowHoop(double hcy, double hh) {
    if (_trajectoryBuffer.isEmpty) return false;
    final lastY = _trajectoryBuffer.last.$2;
    return lastY > hcy + hh * 0.5;
  }

  /// 检查球是否在篮筐附近消失（检测失败）— 可能穿过篮筐
  bool _ballNearHoopAndLost(
      double hcx, double hcy, double hw, double hh) {
    if (_trajectoryBuffer.isEmpty) return false;

    // 使用最后已知球位置（可能是延续点）
    final (lx, ly, _, _, _, _) = _trajectoryBuffer.last;

    // 球最近在篮筐附近（3 倍宽度范围内）
    final dist = sqrt((lx - hcx) * (lx - hcx) + (ly - hcy) * (ly - hcy));
    final nearHoop = dist < hw * 3;

    // 球的真实检测已丢失超过 3 帧（用 _lastRealDetectionFrame 而非轨迹延续帧）
    bool lost = _frameCount - _lastRealDetectionFrame > 3;

    // 球在 apex 后（已开始下降阶段）
    bool afterApex = _frameCount - _apexFrame > (_fps * 0.3).round();

    return nearHoop && lost && afterApex;
  }

  /// 评估投篮命中/未中 — 置信度评分系统
  (bool, double) _evaluateShot(
      double hcx, double hcy, double hw, double hh) {
    double score = 0.0;

    // 证据 1: 轨迹交叉篮筐平面 (0.5 分)
    if (_crossesRimPlane(hcx, hcy, hw, hh)) score += 0.5;

    // 证据 2: 球在篮筐附近下降 (0.3 分)
    if (_descendedNearHoop(hcx, hcy, hw, hh)) score += 0.3;

    // 证据 3: 弧线形状合理 (0.2 分)
    if (_hasValidArc()) score += 0.2;

    // 证据 4: 球消失在篮筐下方 (0.4 分)
    if (_ballDisappearedBelowHoop(hcx, hcy, hw, hh)) score += 0.4;

    // 证据 5: 球在篮筐附近消失 — 强命中信号 (0.6 分)
    // 当球在 apex 后消失在篮筐附近，极可能穿过篮筐
    if (_ballLostNearHoopAfterApex(hcx, hcy, hw, hh)) score += 0.6;

    bool made = score >= 0.5;
    return (made, score.clamp(0.0, 1.0));
  }

  /// 检查轨迹是否从篮筐上方穿过到下方
  bool _crossesRimPlane(
      double hcx, double hcy, double hw, double hh) {
    if (_trajectoryBuffer.length < 3) return false;

    final rimY = hcy;
    final rimLeft = hcx - hw * 1.5;
    final rimRight = hcx + hw * 1.5;

    for (int i = 1; i < _trajectoryBuffer.length; i++) {
      final prevY = _trajectoryBuffer[i - 1].$2;
      final currY = _trajectoryBuffer[i].$2;

      // 球从上方到下方穿过篮筐水平
      if (prevY < rimY && currY >= rimY) {
        // 插值计算穿越点的 x
        final prevX = _trajectoryBuffer[i - 1].$1;
        final currX = _trajectoryBuffer[i].$1;
        final t = (rimY - prevY) / (currY - prevY);
        final crossX = prevX + t * (currX - prevX);

        // 穿越点在篮筐范围内
        if (crossX >= rimLeft && crossX <= rimRight) {
          return true;
        }
      }
    }
    return false;
  }

  /// 检查球是否在篮筐附近下降
  bool _descendedNearHoop(
      double hcx, double hcy, double hw, double hh) {
    if (_trajectoryBuffer.length < 5) return false;

    // 找 apex 之后在篮筐附近的点
    double minY = double.infinity;
    int minIdx = 0;
    for (int i = 0; i < _trajectoryBuffer.length; i++) {
      if (_trajectoryBuffer[i].$2 < minY) {
        minY = _trajectoryBuffer[i].$2;
        minIdx = i;
      }
    }

    if (minIdx >= _trajectoryBuffer.length - 2) return false;

    // 检查 apex 后是否有下降且在篮筐附近的点
    int nearHoopCount = 0;
    for (int i = minIdx + 1; i < _trajectoryBuffer.length; i++) {
      final (x, y, _, _, _, _) = _trajectoryBuffer[i];
      final dx = (x - hcx).abs();
      final dy = (y - hcy).abs();
      if (dx < hw * 3 && dy < hh * 3) {
        nearHoopCount++;
      }
    }

    return nearHoopCount >= 2;
  }

  /// 检查弧线形状是否合理（先上后下）
  bool _hasValidArc() {
    if (_trajectoryBuffer.length < 5) return false;

    double minY = double.infinity;
    int minIdx = 0;
    for (int i = 0; i < _trajectoryBuffer.length; i++) {
      if (_trajectoryBuffer[i].$2 < minY) {
        minY = _trajectoryBuffer[i].$2;
        minIdx = i;
      }
    }

    if (minIdx < 1 || minIdx >= _trajectoryBuffer.length - 1) return false;

    // 检查 apex 前后是否在合理位置
    final beforeY = _trajectoryBuffer[minIdx - 1].$2;
    final afterY = _trajectoryBuffer[minIdx + 1].$2;

    // 前后都比 apex 低（y 更大）
    return beforeY > minY && afterY > minY;
  }

  /// 检查球是否消失在篮筐下方（补篮/扣篮场景）
  bool _ballDisappearedBelowHoop(
      double hcx, double hcy, double hw, double hh) {
    if (_trajectoryBuffer.length < 3) return false;

    final lastPoint = _trajectoryBuffer.last;
    final (lx, ly, _, _, _, _) = lastPoint;

    // 球在篮筐下方且接近篮筐
    bool belowHoop = ly > hcy;
    bool nearHoop = (lx - hcx).abs() < hw * 2;

    // 检查最近几帧是否有球位置（如果球消失，说明可能穿过篮筐）
    bool recentActivity = _frameCount - lastPoint.$3 < 3;

    return belowHoop && nearHoop && recentActivity;
  }

  /// 检查球是否在 apex 后消失在篮筐附近 — 强命中信号
  /// 当球在上升后消失在篮筐区域，极可能穿过篮筐
  bool _ballLostNearHoopAfterApex(
      double hcx, double hcy, double hw, double hh) {
    if (_trajectoryBuffer.length < 3) return false;

    // 球的真实检测已丢失
    bool lost = _frameCount - _lastRealDetectionFrame > 3;
    if (!lost) return false;

    // 最后已知位置在篮筐附近
    final (lx, ly, _, _, _, _) = _trajectoryBuffer.last;
    final dist = sqrt((lx - hcx) * (lx - hcx) + (ly - hcy) * (ly - hcy));
    bool nearHoop = dist < hw * 4;

    // 在 apex 之后
    bool afterApex = _frameCount - _apexFrame > (_fps * 0.2).round();

    return nearHoop && afterApex;
  }

  // ===== 角度计算 =====

  (double, double) _computeAngles() {
    if (_trajectoryBuffer.length < 3) return (0.0, 0.0);

    // 使用完整轨迹（非截断窗口）
    final points = _trajectoryBuffer;
    if (points.length < 3) return (0.0, 0.0);

    final xs = points.map((p) => p.$1).toList();
    final ys = points.map((p) => p.$2).toList();

    try {
      // 归一化 x 避免数值问题
      final xMean = xs.reduce((a, b) => a + b) / xs.length;
      final xStd = sqrt(xs.map((xi) => (xi - xMean) * (xi - xMean)).reduce((a, b) => a + b) / xs.length);
      final xNorm = xStd > 0
          ? xs.map((xi) => (xi - xMean) / xStd).toList()
          : xs.map((xi) => xi - xMean).toList();

      final coeffs = _polyfit(xNorm, ys, 2);
      if (coeffs.length >= 3) {
        // 转换回原始坐标系
        final a = xStd > 0 ? coeffs[0] / (xStd * xStd) : coeffs[0];
        final b = xStd > 0
            ? coeffs[1] / xStd - 2 * a * xMean
            : coeffs[1];

        // 入射角：在篮筐位置的斜率
        final hcx = _hoopPos.isNotEmpty ? _hoopPos.last.$1 : xs.last;
        final slopeEntry = 2 * a * hcx + b;
        final entryAngle = (atan(slopeEntry)).abs() * 180 / pi;

        // 出手角：在轨迹起点的斜率
        final slopeRelease = 2 * a * xs[0] + b;
        final releaseAngle = (atan(slopeRelease)).abs() * 180 / pi;

        return (entryAngle, releaseAngle);
      }
    } catch (_) {}
    return (0.0, 0.0);
  }

  /// 多项式拟合（带部分主元高斯消元）
  List<double> _polyfit(List<double> x, List<double> y, int degree) {
    final n = x.length;
    if (n < degree + 1) throw Exception('Not enough points');

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

    for (int i = 0; i < cols; i++) {
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

  void _resetDetection() {
    _apexDetected = false;
    _apexFrame = 0;
    _lastRealDetectionFrame = -999;
    _trajectoryBuffer.clear();
  }

  void reset() {
    _hoopPos.clear();
    _trajectoryBuffer.clear();
    _shotResults.clear();
    _shotBallPositions.clear();
    _lockedHoop = null;
    _apexDetected = false;
    _apexFrame = 0;
    _lastShotFrame = -999;
    _lastRealDetectionFrame = -999;
    _frameCount = 0;
  }
}
