import 'dart:math';
import '../models/ball_track.dart';
import '../models/trajectory_params.dart';
import '../models/config.dart';
import '../utils/math_utils.dart';

/// 轨迹分析器 — 抛物线拟合 + 运动学参数
/// 对应 Python models/trajectory.py TrajectoryAnalyzer
class TrajectoryAnalyzer {
  double _hoopPixelWidth = 0.0;
  (double, double)? _hoopPosition;
  final List<double> _hoopWidthHistory = [];
  int _frameWidth = AppConfig.trajectory.defaultFrameWidth;
  double _fps = 30.0;

  void updateHoopReference(
      (double, double)? hoopPosition, double hoopPixelWidth) {
    _hoopPosition = hoopPosition;
    if (hoopPixelWidth > 10) {
      _hoopPixelWidth = hoopPixelWidth;
      _hoopWidthHistory.add(hoopPixelWidth);
      if (_hoopWidthHistory.length > 60) {
        _hoopWidthHistory.removeAt(0);
      }
    }
  }

  void setFrameWidth(int width) => _frameWidth = width;
  void setFps(double fps) => _fps = fps;

  /// 拟合篮球抛物线轨迹
  TrajectoryParams? fitTrajectory(BallTrack track) {
    final positions = track.positions;
    if (positions.length < 3) return null;

    final x = positions.map((p) => p.$1).toList();
    final y = positions.map((p) => p.$2).toList();

    // 平滑处理
    final ySmooth = _savgolFilter(y, min(y.length, 9), 2);

    // 找最高点
    int apexIdx = 0;
    double minY = ySmooth[0];
    for (int i = 1; i < ySmooth.length; i++) {
      if (ySmooth[i] < minY) {
        minY = ySmooth[i];
        apexIdx = i;
      }
    }

    final apexX = x[apexIdx];
    final apexY = ySmooth[apexIdx];

    try {
      // 归一化 x 避免正规方程病态（x 范围 200-440 时 sum(x^4) ~ 2e11）
      final xMean = x.reduce((a, b) => a + b) / x.length;
      final xStd = sqrt(x.map((xi) => (xi - xMean) * (xi - xMean)).reduce((a, b) => a + b) / x.length);
      final xNorm = xStd > 0 ? x.map((xi) => (xi - xMean) / xStd).toList() : x.map((xi) => xi - xMean).toList();

      final coeffs = polyfit(xNorm, ySmooth, 2);
      if (coeffs.length < 3) return null;
      // 转换回原始坐标系: y = c0 + c1*xNorm + c2*xNorm² → y = a*x² + b*x + c
      final a = xStd > 0 ? coeffs[2] / (xStd * xStd) : coeffs[2];
      final b = xStd > 0 ? coeffs[1] / xStd - 2 * a * xMean : coeffs[1];
      final c = coeffs[0] - coeffs[1] * (xStd > 0 ? xMean / xStd : xMean) + a * xMean * xMean;

      // R² 计算
      final yPred = x.map((xi) => a * xi * xi + b * xi + c).toList();
      final yMean = ySmooth.reduce((a, b) => a + b) / ySmooth.length;
      double ssRes = 0, ssTot = 0;
      for (int i = 0; i < ySmooth.length; i++) {
        ssRes += (ySmooth[i] - yPred[i]) * (ySmooth[i] - yPred[i]);
        ssTot += (ySmooth[i] - yMean) * (ySmooth[i] - yMean);
      }
      final rSquared = ssTot > 0 ? 1 - (ssRes / ssTot) : 0.0;

      if (rSquared < AppConfig.shot.trajectoryRSquaredThreshold) return null;

      // 出手角度（与水平面的夹角，取绝对值）
      final xStart = x[0];
      final slopeStart = 2 * a * xStart + b;
      final releaseAngle = (atan(slopeStart)).abs() * 180 / pi;

      // 入射角度（与水平面的夹角，取绝对值）
      double entryAngle = 0.0;
      if (apexIdx < x.length - 1) {
        final xEnd = x.last;
        final slopeEnd = 2 * a * xEnd + b;
        entryAngle = (atan(slopeEnd)).abs() * 180 / pi;
      }

      final estimatedDistance = estimateDistance(track);

      // 运动学参数
      final nPoints = track.points.length;
      final flightTime = _fps > 0 ? nPoints / _fps : 0.0;

      double shotSpeed = 0.0;
      if (flightTime > 0 && estimatedDistance > 0) {
        final vHorizontal = estimatedDistance / flightTime;
        final releaseRad = releaseAngle.abs() * pi / 180;
        if (tan(releaseRad) > 0) {
          final vVertical = vHorizontal * tan(releaseRad);
          shotSpeed = sqrt(vHorizontal * vHorizontal + vVertical * vVertical);
        } else {
          shotSpeed = vHorizontal;
        }
      }

      // 弧线高度
      final releaseY = ySmooth[0];
      final arcHeightPx = (releaseY - apexY).abs();
      final ballPx = _estimateBallPixelSize(track);
      double arcHeight;
      if (ballPx > 5) {
        final metersPerPx = BallProperties.realDiameter / ballPx;
        arcHeight = arcHeightPx * metersPerPx;
      } else {
        arcHeight = arcHeightPx * AppConfig.trajectory.pixelToMeterFallback;
      }

      return TrajectoryParams(
        apexX: apexX,
        apexY: apexY,
        releaseAngle: releaseAngle,
        entryAngle: entryAngle,
        apexHeight: apexY,
        fitRSquared: rSquared,
        parabolaA: a,
        parabolaB: b,
        parabolaC: c,
        estimatedDistance: estimatedDistance,
        flightTime: double.parse(flightTime.toStringAsFixed(3)),
        shotSpeed: double.parse(shotSpeed.toStringAsFixed(2)),
        arcHeight: double.parse(arcHeight.toStringAsFixed(2)),
      );
    } catch (_) {
      return null;
    }
  }

  double estimateDistance(BallTrack track) {
    final positions = track.positions;
    if (positions.length < 2) return 0.0;

    // 方法 1: 球像素大小（最准确，使用焦距和真实球直径）
    final avgBallSize = _estimateBallPixelSize(track);
    if (avgBallSize > 5) {
      final focalLength = _frameWidth /
          (2 * tan(AppConfig.trajectory.cameraFovDegrees * pi / 180));
      final distanceM =
          AppConfig.trajectory.ballDiameterReal * focalLength / avgBallSize;
      return distanceM.clamp(0.5, 15.0);
    }

    // 方法 2: 篮筐宽度参考
    if (_hoopPixelWidth > 0 && _hoopPosition != null) {
      final dist = _estimateDistanceFromHoop(track);
      if (dist > 0) return dist;
    }

    // 方法 3: 水平像素位移
    final xPositions = positions.map((p) => p.$1).toList();
    final pixelDisplacement = (xPositions.last - xPositions[0]).abs();
    if (_hoopPixelWidth > 0) {
      final metersPerPixel = CourtDimensions.rimDiameter / _hoopPixelWidth;
      return (pixelDisplacement * metersPerPixel).clamp(0.5, 10.0);
    }
    return pixelDisplacement * AppConfig.trajectory.pixelToMeterFallback;
  }

  double _estimateDistanceFromHoop(BallTrack track) {
    if (_hoopWidthHistory.isEmpty) return 0.0;
    final sorted = List<double>.from(_hoopWidthHistory)..sort();
    final refWidth = sorted[sorted.length ~/ 2];
    if (refWidth < 5 || _hoopPosition == null) return 0.0;

    final metersPerPixel = CourtDimensions.rimDiameter / refWidth;
    final positions = track.positions;
    final xs = positions.map((p) => p.$1).toList();
    final ys = positions.map((p) => p.$2).toList();

    final apexIdx = ys.indexOf(ys.reduce(min));
    final shooterX = xs[apexIdx];
    final startX = xs.sublist(0, max(1, xs.length ~/ 3)).reduce((a, b) => a + b) /
        max(1, xs.length ~/ 3);

    final hoopX = _hoopPosition!.$1;
    final dxApex = (shooterX - hoopX).abs();
    final dxStart = (startX - hoopX).abs();
    final pixelDist = max(dxApex, dxStart);

    final distanceM = pixelDist * metersPerPixel;
    return distanceM.clamp(0.5, 10.0);
  }

  double _estimateBallPixelSize(BallTrack track) {
    if (track.points.isEmpty) return 0.0;

    // 方法 1: 检测框面积
    final areas = track.points
        .where((p) => p.ballArea > 0)
        .map((p) => p.ballArea)
        .toList();
    if (areas.isNotEmpty) {
      areas.sort();
      final medianArea = areas[areas.length ~/ 2];
      final diameter = sqrt(medianArea);
      return diameter.clamp(5.0, 100.0);
    }

    // 方法 2: 轨迹点间距
    final positions = track.positions;
    if (positions.length < 2) return 0.0;

    final distances = <double>[];
    for (int i = 1; i < positions.length; i++) {
      final dx = positions[i].$1 - positions[i - 1].$1;
      final dy = positions[i].$2 - positions[i - 1].$2;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist > 0) distances.add(dist);
    }

    if (distances.isEmpty) return 0.0;
    distances.sort();
    final avgDistance = distances[distances.length ~/ 2];
    final ballSize = avgDistance / 3.0;
    return ballSize.clamp(10.0, 50.0);
  }

  /// 分类投篮类型
  String classifyShotType(TrajectoryParams? trajectory,
      {double fallbackDistance = 0.0}) {
    final distance = trajectory?.estimatedDistance ?? fallbackDistance;
    final releaseAngle = trajectory?.releaseAngle ?? 0.0;
    final tc = AppConfig.trajectory;

    if (distance < tc.layupMaxDistance) return 'layup';
    if (distance < tc.midRangeMaxDistance) {
      if (releaseAngle.abs() < 30) return 'layup';
      return 'mid_range';
    }
    return 'three_point';
  }

  /// Savitzky-Golay 平滑（简化版，polyorder=2）
  List<double> _savgolFilter(List<double> data, int window, int polyorder) {
    if (data.length < window || window < 3) return List.from(data);
    if (window % 2 == 0) window--;

    final half = window ~/ 2;
    final result = List<double>.from(data);

    for (int i = half; i < data.length - half; i++) {
      final segment = data.sublist(i - half, i + half + 1);
      // 简单二次多项式平滑
      final xVals = List.generate(window, (j) => j - half);
      try {
        final coeffs = polyfit(
            xVals.map((v) => v.toDouble()).toList(), segment, polyorder);
        result[i] = coeffs[0] + coeffs[1] * 0 + coeffs[2] * 0;
      } catch (_) {}
    }

    return result;
  }

  double get hoopPixelWidth => _hoopPixelWidth;
  (double, double)? get hoopPosition => _hoopPosition;
}
