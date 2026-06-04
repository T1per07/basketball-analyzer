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
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.textDim.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bar_chart,
                size: 48,
                color: AppColors.textDim.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '请先上传视频并完成分析',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textDim,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '上传投篮视频，AI 将自动分析投篮数据',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textDim.withOpacity(0.7),
              ),
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
      'three_point': ('三分球', Icons.gps_fixed, const Color(0xFFFF6B2B)),
      'mid_range': ('中距离', Icons.adjust, const Color(0xFFFF9800)),
      'layup': ('上篮', Icons.directions_run, const Color(0xFF00E5FF)),
      'free_throw': ('罚球', Icons.flag, const Color(0xFF39FF14)),
      'dunk': ('扣篮', Icons.sports_basketball, const Color(0xFFFF3C3C)),
    };

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            tag: 'BREAKDOWN',
            title: '按类型统计',
            description: '不同投篮类型的命中率分析',
          ),
          if (statsByType.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  '暂无投篮数据',
                  style: TextStyle(
                    color: AppColors.textDim.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
              ),
            )
          else
            ...statsByType.entries.map((entry) {
              final label = typeLabels[entry.key]?.$1 ?? entry.key;
              final icon = typeLabels[entry.key]?.$2 ?? Icons.circle;
              final color = typeLabels[entry.key]?.$3 ?? AppColors.primary;
              final data = entry.value;
              final percentage = data['percentage'] as double;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: color.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 20, color: color),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: percentage,
                              backgroundColor: AppColors.surface,
                              color: color,
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${(percentage * 100).round()}%',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        Text(
                          '${data['made']}/${data['attempts']}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textDim,
                          ),
                        ),
                      ],
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
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            tag: 'EXPORT',
            title: '导出数据',
            description: '将分析结果导出为 Excel 或 PDF 格式',
          ),
          Row(
            children: [
              Expanded(
                child: AnimatedButton(
                  onPressed: () => _exportExcel(context, result),
                  color: AppColors.secondary,
                  borderRadius: 12,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.table_chart, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        '导出 Excel',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedButton(
                  onPressed: () => _exportPdf(context, result),
                  color: AppColors.primary,
                  borderRadius: 12,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.picture_as_pdf, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        '导出 PDF',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
