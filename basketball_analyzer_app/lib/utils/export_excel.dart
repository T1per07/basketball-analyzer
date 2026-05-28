import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';

/// 便捷导出函数 — 自动选择输出路径
Future<String> exportAnalysisExcel(AnalysisResult result) async {
  final dir = await getApplicationDocumentsDirectory();
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final path = '${dir.path}${Platform.pathSeparator}shot_analysis_$timestamp.xlsx';
  return ExcelExporter.export(result, path);
}

/// Excel 导出工具
/// 对应 Python utils/export_excel.py
class ExcelExporter {
  static Future<String> export(AnalysisResult result, String outputPath) async {
    final excel = Excel.createExcel();

    // Sheet 1: 汇总
    final summary = excel['Summary'];
    summary.appendRow([TextCellValue('指标'), TextCellValue('值')]);
    summary.appendRow([TextCellValue('总投篮'), IntCellValue(result.totalShots)]);
    summary.appendRow([TextCellValue('命中'), IntCellValue(result.madeShots)]);
    summary.appendRow([TextCellValue('命中率'), TextCellValue('${(result.overallPercentage * 100).toStringAsFixed(1)}%')]);
    summary.appendRow([TextCellValue('平均距离'), TextCellValue('${result.averageDistance.toStringAsFixed(2)}m')]);

    // Sheet 2: 按类型
    final byType = excel['By Type'];
    byType.appendRow([
      TextCellValue('类型'), TextCellValue('尝试'), TextCellValue('命中'),
      TextCellValue('命中率'), TextCellValue('平均距离'),
    ]);
    for (final entry in result.getStatsByType().entries) {
      byType.appendRow([
        TextCellValue(entry.key),
        IntCellValue(entry.value['attempts'] as int),
        IntCellValue(entry.value['made'] as int),
        TextCellValue('${((entry.value['percentage'] as double) * 100).toStringAsFixed(1)}%'),
        TextCellValue('${(entry.value['avg_distance'] as double).toStringAsFixed(2)}m'),
      ]);
    }

    // Sheet 3: 所有投篮
    final allShots = excel['All Shots'];
    allShots.appendRow([
      TextCellValue('ID'), TextCellValue('类型'), TextCellValue('命中'),
      TextCellValue('距离'), TextCellValue('出手角度'), TextCellValue('入射角度'),
      TextCellValue('出手速度'), TextCellValue('飞行时间'), TextCellValue('弧线高度'),
      TextCellValue('置信度'),
    ]);
    for (final shot in result.shots) {
      allShots.appendRow([
        IntCellValue(shot.shotId),
        TextCellValue(shot.shotType),
        TextCellValue(shot.made ? '是' : '否'),
        TextCellValue('${shot.distance.toStringAsFixed(2)}m'),
        TextCellValue('${shot.releaseAngle.toStringAsFixed(1)}°'),
        TextCellValue('${shot.entryAngle.toStringAsFixed(1)}°'),
        TextCellValue('${shot.shotSpeed.toStringAsFixed(1)}m/s'),
        TextCellValue('${shot.flightTime.toStringAsFixed(3)}s'),
        TextCellValue('${shot.arcHeight.toStringAsFixed(2)}m'),
        TextCellValue(shot.confidence.toStringAsFixed(2)),
      ]);
    }

    // 删除默认 Sheet
    excel.delete('Sheet1');

    final bytes = excel.save();
    if (bytes != null) {
      final file = File(outputPath);
      await file.writeAsBytes(bytes);
    }
    return outputPath;
  }
}
