import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../app_state.dart';
import '../models/models.dart';
import '../painters/court_painter.dart';
import '../utils/utils.dart';
import '../widgets/widgets.dart';

/// 统计分析页面 — 从 AppState 读取真实分析结果
class AnalysisScreen extends StatelessWidget {
  const AnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final result = appState.result;

    if (result == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 64, color: AppColors.textDim.withAlpha(80)),
            const SizedBox(height: 16),
            Text(
              '请先上传视频并完成分析',
              style: TextStyle(fontSize: 16, color: AppColors.textDim),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          // 主统计面板
          StatsPanel(result: result),
          const SizedBox(height: 16),
          // 按类型统计
          _buildTypeStats(result),
          const SizedBox(height: 16),
          // 投篮热力图
          ShotChart(shots: _buildCourtShots(result)),
          const SizedBox(height: 16),
          // 导出按钮
          _buildExportButtons(context, result),
        ],
      ),
    );
  }

  Widget _buildTypeStats(AnalysisResult result) {
    final statsByType = result.getStatsByType();
    final typeLabels = {
      'three_point': ('三分球', Icons.gps_fixed),
      'mid_range': ('中距离', Icons.adjust),
      'layup': ('上篮', Icons.directions_run),
      'free_throw': ('罚球', Icons.flag),
      'dunk': ('扣篮', Icons.sports_basketball),
    };

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
            '按类型统计',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          if (statsByType.isEmpty)
            Text(
              '暂无投篮数据',
              style: TextStyle(color: AppColors.textDim, fontSize: 13),
            )
          else
            ...statsByType.entries.map((entry) {
              final label = typeLabels[entry.key]?.$1 ?? entry.key;
              final icon = typeLabels[entry.key]?.$2 ?? Icons.circle;
              final data = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: AppColors.primary),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 60,
                      child: Text(label,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.text)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: data['percentage'] as double,
                          backgroundColor: AppColors.background,
                          color: AppColors.primary,
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 80,
                      child: Text(
                        '${data['made']}/${data['attempts']}  ${((data['percentage'] as double) * 100).round()}%',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textDim),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  List<CourtShotPoint> _buildCourtShots(AnalysisResult result) {
    if (result.shots.isEmpty) return [];

    // Normalize hoopX to 0-1 range (horizontal court position)
    final hoopXs = result.shots.map((s) => s.hoopX).toList();
    final minX = hoopXs.reduce((a, b) => a < b ? a : b).toDouble();
    final maxX = hoopXs.reduce((a, b) => a > b ? a : b).toDouble();
    final xRange = maxX - minX;

    // Normalize distance to 0-1 range (0=hoop, 1=half court)
    final distances = result.shots.map((s) => s.distance).toList();
    final maxDist = distances.reduce((a, b) => a > b ? a : b);
    final distRange = maxDist > 0 ? maxDist : 1.0;

    return result.shots.map((s) {
      final normX = xRange > 0 ? (s.hoopX - minX) / xRange : 0.5;
      // y: 0 = near hoop (bottom of court), 1 = far (top of court)
      final normY = 1.0 - (s.distance / distRange).clamp(0.0, 1.0);
      return CourtShotPoint(
        x: normX.clamp(0.05, 0.95),
        y: normY.clamp(0.3, 0.95),
        made: s.made,
        type: s.shotType,
      );
    }).toList();
  }

  Widget _buildExportButtons(BuildContext context, AnalysisResult result) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _exportExcel(context, result),
            icon: const Icon(Icons.table_chart, size: 18),
            label: const Text('导出 Excel'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.secondary,
              side: const BorderSide(color: AppColors.secondary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _exportPdf(context, result),
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: const Text('导出 PDF'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _exportExcel(
      BuildContext context, AnalysisResult result) async {
    try {
      final path = await exportAnalysisExcel(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出: $path')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  Future<void> _exportPdf(BuildContext context, AnalysisResult result) async {
    try {
      final path = await exportAnalysisPdf(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出: $path')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }
}
