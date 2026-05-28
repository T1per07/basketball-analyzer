import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';

/// 便捷导出函数 — 自动选择输出路径
Future<String> exportAnalysisPdf(AnalysisResult result) async {
  final dir = await getApplicationDocumentsDirectory();
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final path = '${dir.path}${Platform.pathSeparator}shot_analysis_$timestamp.pdf';
  return PdfExporter.export(result, path);
}

/// PDF 导出工具
/// 对应 Python utils/export_pdf.py
class PdfExporter {
  static Future<String> export(AnalysisResult result, String outputPath) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          // 标题
          pw.Header(
            level: 0,
            child: pw.Text('投篮分析报告',
                style: pw.TextStyle(
                    fontSize: 24, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 20),

          // 汇总
          pw.Text('汇总统计',
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          _buildSummaryTable(result),
          pw.SizedBox(height: 20),

          // 按类型
          pw.Text('按类型统计',
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          _buildTypeTable(result),
          pw.SizedBox(height: 20),

          // 投篮详情
          pw.Text('投篮详情',
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          _buildShotTable(result),
        ],
      ),
    );

    final file = File(outputPath);
    await file.writeAsBytes(await pdf.save());
    return outputPath;
  }

  static pw.Table _buildSummaryTable(AnalysisResult result) {
    return pw.TableHelper.fromTextArray(
      headers: ['指标', '值'],
      data: [
        ['总投篮', '${result.totalShots}'],
        ['命中', '${result.madeShots}'],
        ['命中率', '${(result.overallPercentage * 100).toStringAsFixed(1)}%'],
        ['平均距离', '${result.averageDistance.toStringAsFixed(2)}m'],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellAlignment: pw.Alignment.centerLeft,
    );
  }

  static pw.Table _buildTypeTable(AnalysisResult result) {
    final stats = result.getStatsByType();
    return pw.TableHelper.fromTextArray(
      headers: ['类型', '尝试', '命中', '命中率', '平均距离'],
      data: stats.entries.map((e) => [
        e.key,
        '${e.value['attempts']}',
        '${e.value['made']}',
        '${(e.value['percentage'] * 100).toStringAsFixed(1)}%',
        '${(e.value['avg_distance'] as double).toStringAsFixed(2)}m',
      ]).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
    );
  }

  static pw.Table _buildShotTable(AnalysisResult result) {
    return pw.TableHelper.fromTextArray(
      headers: ['ID', '类型', '命中', '距离', '出手角', '速度'],
      data: result.shots.take(50).map((s) => [
        '${s.shotId}',
        s.shotType,
        s.made ? '是' : '否',
        '${s.distance.toStringAsFixed(1)}m',
        '${s.releaseAngle.toStringAsFixed(0)}°',
        '${s.shotSpeed.toStringAsFixed(1)}m/s',
      ]).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellStyle: const pw.TextStyle(fontSize: 9),
    );
  }
}
