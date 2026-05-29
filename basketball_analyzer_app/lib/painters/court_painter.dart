import 'dart:math';
import 'package:flutter/material.dart';
import '../app.dart';

/// 球场绘制器 — 绘制半场球场 + 投篮点
class CourtPainter extends CustomPainter {
  final List<CourtShotPoint> shots;

  CourtPainter({this.shots = const []});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppColors.textDim.withAlpha(80);

    final w = size.width;
    final h = size.height;

    // 球场背景
    final courtPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF1A3A2A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(8)),
      courtPaint,
    );

    // 边框
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(2, 2, w - 4, h - 4), const Radius.circular(6)),
      paint,
    );

    // 篮筐位置（底部中央）
    final rimX = w / 2;
    final rimY = h * 0.85;
    final rimRadius = w * 0.03;

    // 篮筐
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AppColors.primary;
    canvas.drawCircle(Offset(rimX, rimY), rimRadius, rimPaint);

    // 罚球区
    final ftWidth = w * 0.3;
    final ftHeight = h * 0.2;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(rimX, rimY - ftHeight / 2),
        width: ftWidth,
        height: ftHeight,
      ),
      paint,
    );

    // 三分线
    final threeRadius = w * 0.42;
    final threePath = Path()
      ..moveTo(rimX - ftWidth / 2, rimY)
      ..arcTo(
        Rect.fromCenter(
          center: Offset(rimX, rimY),
          width: threeRadius * 2,
          height: threeRadius * 2,
        ),
        pi,
        pi,
        false,
      )
      ..lineTo(rimX + ftWidth / 2, rimY);
    canvas.drawPath(threePath, paint);

    // 限制区
    final restrictRadius = w * 0.1;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(rimX, rimY),
        width: restrictRadius * 2,
        height: restrictRadius * 2,
      ),
      pi,
      pi,
      false,
      paint,
    );

    // 中线
    canvas.drawLine(
      Offset(0, h * 0.5),
      Offset(w, h * 0.5),
      paint,
    );

    // 绘制投篮点
    for (final shot in shots) {
      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = shot.made ? AppColors.success : AppColors.error;
      canvas.drawCircle(
        Offset(shot.x * w, shot.y * h),
        4,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CourtPainter oldDelegate) {
    if (oldDelegate.shots.length != shots.length) return true;
    for (int i = 0; i < shots.length; i++) {
      if (oldDelegate.shots[i].x != shots[i].x ||
          oldDelegate.shots[i].y != shots[i].y ||
          oldDelegate.shots[i].made != shots[i].made) return true;
    }
    return false;
  }
}

class CourtShotPoint {
  final double x;
  final double y;
  final bool made;
  final String type;

  const CourtShotPoint({
    required this.x,
    required this.y,
    required this.made,
    this.type = 'mid_range',
  });
}
