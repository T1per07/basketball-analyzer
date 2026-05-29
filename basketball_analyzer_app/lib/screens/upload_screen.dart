import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../app_state.dart';
import '../models/models.dart';
import '../services/video_processor.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  String? _videoPath;
  final _processor = VideoProcessor();
  bool _useOnnx = false;
  bool _onnxAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkOnnx();
  }

  Future<void> _checkOnnx() async {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final modelPath = '$exeDir/data/flutter_assets/assets/models/best.onnx';
      final available = await _processor.enableOnnx(modelPath: modelPath);
      if (mounted) {
        setState(() => _onnxAvailable = available);
      }
    } catch (_) {
      // ONNX 不可用，忽略
    }
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _videoPath = result.files.single.path;
      });
      if (mounted) {
        context.read<AppState>().clear();
      }
    }
  }

  Future<void> _analyze() async {
    if (_videoPath == null) return;

    final appState = context.read<AppState>();
    appState.setAnalyzing(true);

    try {
      // 如果选择 ONNX，确保已启用
      if (_useOnnx) {
        await _processor.enableOnnx();
      }

      final result = await _processor.analyzeVideo(
        _videoPath!,
        onProgress: (current, total) {
          if (total > 0) {
            appState.setProgress(current / total);
          }
        },
      );

      appState.setResult(result);
    } catch (e) {
      appState.setError('分析失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          // 上传区域
          GestureDetector(
            onTap: appState.isAnalyzing ? null : _pickVideo,
            child: Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _videoPath != null
                      ? AppColors.primary
                      : AppColors.textDim.withAlpha(60),
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _videoPath != null
                        ? Icons.check_circle
                        : Icons.cloud_upload_outlined,
                    size: 48,
                    color: _videoPath != null
                        ? AppColors.success
                        : AppColors.textDim,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _videoPath != null
                        ? _videoPath!.split(Platform.pathSeparator).last
                        : '选择视频文件',
                    style: TextStyle(
                      fontSize: 16,
                      color: _videoPath != null
                          ? AppColors.text
                          : AppColors.textDim,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '支持 MP4, MOV, AVI, WebM, MKV',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textDim.withAlpha(150),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ONNX 模型开关
          if (_onnxAvailable)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.smart_toy, color: AppColors.secondary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'AI 模型检测 (ONNX)',
                      style: TextStyle(fontSize: 14, color: AppColors.text),
                    ),
                  ),
                  Switch(
                    value: _useOnnx,
                    onChanged: (v) => setState(() => _useOnnx = v),
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
            ),
          if (_onnxAvailable) const SizedBox(height: 16),

          // 分析按钮
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _videoPath != null && !appState.isAnalyzing
                  ? _analyze
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: appState.isAnalyzing
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                            '分析中... ${(appState.progress * 100).round()}%'),
                      ],
                    )
                  : const Text(
                      '开始分析',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          const SizedBox(height: 16),

          // 进度条
          if (appState.isAnalyzing)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: appState.progress,
                backgroundColor: AppColors.surface,
                color: AppColors.primary,
                minHeight: 6,
              ),
            ),

          // 错误提示
          if (appState.error != null)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error.withAlpha(80)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: AppColors.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      appState.error!,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // 结果预览
          if (appState.result != null) ...[
            const SizedBox(height: 24),
            _buildResultPreview(appState.result!),
          ],
        ],
      ),
    );
  }

  Widget _buildResultPreview(AnalysisResult result) {
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
            '分析完成',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem('投篮', '${result.totalShots}'),
              _statItem('命中', '${result.madeShots}'),
              _statItem(
                '命中率',
                '${(result.overallPercentage * 100).round()}%',
              ),
              _statItem(
                '平均距离',
                '${result.averageDistance.toStringAsFixed(1)}m',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
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
}
