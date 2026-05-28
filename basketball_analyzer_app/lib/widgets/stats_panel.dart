import 'package:flutter/material.dart';
import '../app.dart';
import '../models/models.dart';

/// 统计面板组件
class StatsPanel extends StatelessWidget {
  final AnalysisResult result;

  const StatsPanel({super.key, required this.result});

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
            '投篮统计',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 16),
          // 主统计
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _bigStat(
                '命中率',
                '${(result.overallPercentage * 100).round()}%',
                AppColors.primary,
              ),
              _bigStat(
                '投篮',
                '${result.totalShots}',
                AppColors.secondary,
              ),
              _bigStat(
                '命中',
                '${result.madeShots}',
                AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 次统计
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _smallStat(
                '平均距离',
                '${result.averageDistance.toStringAsFixed(1)}m',
              ),
              _smallStat(
                '最远命中',
                '${_maxMadeDistance().toStringAsFixed(1)}m',
              ),
              _smallStat(
                'eFG%',
                '${_effectiveFg().toStringAsFixed(1)}%',
              ),
            ],
          ),
          const Divider(color: AppColors.textDim, height: 32),
          // 运动学参数
          if (_hasKinematics()) ...[
            const Text(
              '运动学参数',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textDim,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _smallStat('平均出手速度', '${_avgSpeed().toStringAsFixed(1)} m/s'),
                _smallStat('平均飞行时间', '${_avgFlightTime().toStringAsFixed(2)} s'),
                _smallStat('平均弧线高度', '${_avgArcHeight().toStringAsFixed(2)} m'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  double _maxMadeDistance() {
    final made = result.shots.where((s) => s.made && s.distance > 0);
    return made.isNotEmpty
        ? made.map((s) => s.distance).reduce((a, b) => a > b ? a : b)
        : 0.0;
  }

  double _effectiveFg() {
    if (result.totalShots == 0) return 0.0;
    final threeMade =
        result.shots.where((s) => s.made && s.shotType == 'three_point').length;
    return (result.madeShots + 0.5 * threeMade) / result.totalShots * 100;
  }

  bool _hasKinematics() {
    return result.shots.any((s) => s.shotSpeed > 0);
  }

  double _avgSpeed() {
    final withSpeed = result.shots.where((s) => s.shotSpeed > 0);
    return withSpeed.isNotEmpty
        ? withSpeed.map((s) => s.shotSpeed).reduce((a, b) => a + b) /
            withSpeed.length
        : 0.0;
  }

  double _avgFlightTime() {
    final withTime = result.shots.where((s) => s.flightTime > 0);
    return withTime.isNotEmpty
        ? withTime.map((s) => s.flightTime).reduce((a, b) => a + b) /
            withTime.length
        : 0.0;
  }

  double _avgArcHeight() {
    final withArc = result.shots.where((s) => s.arcHeight > 0);
    return withArc.isNotEmpty
        ? withArc.map((s) => s.arcHeight).reduce((a, b) => a + b) /
            withArc.length
        : 0.0;
  }

  Widget _bigStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textDim),
        ),
      ],
    );
  }

  Widget _smallStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textDim),
        ),
      ],
    );
  }
}
