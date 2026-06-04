import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../app_state.dart';
import '../models/models.dart';
import '../services/video_processor.dart';
import '../widgets/widgets.dart';

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
      String? modelPath;
      // 桌面端：从文件系统加载模型
      if (!Platform.isAndroid && !Platform.isIOS) {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        modelPath = '$exeDir/data/flutter_assets/assets/models/best.onnx';
      }
      // 移动端：modelPath 为 null，ONNX 会自动从 asset 加载
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          // 上传区域
          GestureDetector(
            onTap: appState.isAnalyzing ? null : _pickVideo,
            child: GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 40),
              borderColor: _videoPath != null
                  ? AppColors.primary.withOpacity(0.5)
                  : null,
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: _videoPath != null
                            ? AppColors.success.withOpacity(0.2)
                            : AppColors.primary.withOpacity(0.2),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_videoPath != null
                                    ? AppColors.success
                                    : AppColors.primary)
                                .withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: -5,
                          ),
                        ],
                      ),
                      child: Icon(
                        _videoPath != null
                            ? Icons.check_circle
                            : Icons.cloud_upload_outlined,
                        size: 40,
                        color: _videoPath != null
                            ? AppColors.success
                            : AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _videoPath != null
                          ? _videoPath!.split(Platform.pathSeparator).last
                          : '选择视频文件',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: _videoPath != null
                            ? AppColors.text
                            : AppColors.textDim,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '支持 MP4, MOV, AVI, WebM, MKV',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textDim.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ONNX 模型开关
          if (_onnxAvailable)
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.smart_toy,
                        color: AppColors.secondary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI 模型检测 (ONNX)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        Text(
                          '使用深度学习模型进行更准确的检测',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textDim,
                          ),
                        ),
                      ],
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
          if (_onnxAvailable) const SizedBox(height: 24),

          // 分析按钮
          GlowButton(
            onPressed: _videoPath != null && !appState.isAnalyzing
                ? _analyze
                : null,
            color: _videoPath != null && !appState.isAnalyzing
                ? AppColors.primary
                : AppColors.textMuted,
            borderRadius: 12,
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: SizedBox(
              width: double.infinity,
              child: Center(
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
                            '分析中... ${(appState.progress * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        '开始分析',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 进度条
          if (appState.isAnalyzing)
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '分析进度',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textDim,
                        ),
                      ),
                      Text(
                        '${(appState.progress * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: appState.progress,
                      backgroundColor: AppColors.surface,
                      color: AppColors.primary,
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),

          // 错误提示
          if (appState.error != null)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.error.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.info_outline,
                        color: AppColors.error, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      appState.error!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 13,
                      ),
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
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '分析完成',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                  Text(
                    '点击 STATS 查看详细统计',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 统计卡片
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              StatCard(
                label: '总投篮',
                value: '${result.totalShots}',
                icon: Icons.sports_basketball,
                color: AppColors.primary,
              ),
              StatCard(
                label: '命中',
                value: '${result.madeShots}',
                icon: Icons.check_circle,
                color: AppColors.success,
              ),
              StatCard(
                label: '命中率',
                value: '${(result.overallPercentage * 100).round()}%',
                icon: Icons.percent,
                color: AppColors.secondary,
              ),
              StatCard(
                label: '平均距离',
                value: '${result.averageDistance.toStringAsFixed(1)}m',
                icon: Icons.straighten,
                color: const Color(0xFFFF9800),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
