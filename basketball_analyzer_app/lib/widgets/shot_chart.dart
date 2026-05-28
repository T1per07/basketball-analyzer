import 'package:flutter/material.dart';
import '../app.dart';
import '../painters/court_painter.dart';

/// 投篮热力图组件 — 在球场图上显示投篮分布
class ShotChart extends StatelessWidget {
  final List<CourtShotPoint> shots;

  const ShotChart({super.key, this.shots = const []});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '投篮热力图',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 1.5,
            child: CustomPaint(
              painter: CourtPainter(shots: shots),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(AppColors.success, '命中'),
              const SizedBox(width: 16),
              _legendDot(AppColors.error, '未中'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textDim),
        ),
      ],
    );
  }
}
