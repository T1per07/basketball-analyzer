import 'package:flutter/material.dart';
import '../app.dart';

/// 投篮叠加绘制器 — 在视频帧上绘制轨迹和标注
class ShotOverlayPainter extends CustomPainter {
  final List<(double, double)> trajectory;
  final (double, double)? hoopCenter;
  final (double, double, double, double)? hoopBox;
  final bool made;

  ShotOverlayPainter({
    this.trajectory = const [],
    this.hoopCenter,
    this.hoopBox,
    this.made = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制篮筐框
    if (hoopBox != null) {
      final (x, y, w, h) = hoopBox!;
      final boxPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.secondary;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          const Radius.circular(4),
        ),
        boxPaint,
      );
    }

    // 绘制篮筐中心
    if (hoopCenter != null) {
      final centerPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.primary;
      canvas.drawCircle(
        Offset(hoopCenter!.$1, hoopCenter!.$2),
        8,
        centerPaint,
      );
    }

    // 绘制轨迹
    if (trajectory.length >= 2) {
      final path = Path();
      path.moveTo(trajectory[0].$1, trajectory[0].$2);
      for (int i = 1; i < trajectory.length; i++) {
        path.lineTo(trajectory[i].$1, trajectory[i].$2);
      }

      final tracePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = AppColors.primary.withAlpha(180)
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, tracePaint);

      // 轨迹点
      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = AppColors.primary;
      for (final p in trajectory) {
        canvas.drawCircle(Offset(p.$1, p.$2), 3, dotPaint);
      }
    }

    // 命中标记
    if (made && hoopCenter != null) {
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'SCORE!',
          style: TextStyle(
            color: AppColors.success,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
          hoopCenter!.$1 - textPainter.width / 2,
          hoopCenter!.$2 - 30,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ShotOverlayPainter oldDelegate) {
    return oldDelegate.trajectory != trajectory ||
        oldDelegate.made != made;
  }
}
