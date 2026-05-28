import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../app.dart';
import '../services/video_processor.dart';

/// 实时检测页面
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isStreaming = false;
  bool _isInitializing = false;
  bool _useOnnx = false;
  bool _onnxAvailable = false;
  bool _onnxProcessing = false; // 防止并发 ONNX 推理
  int _selectedCamera = 0;
  int _frameIndex = 0;
  String? _error;

  final _processor = VideoProcessor();

  // Pre-allocated BGR buffer for YUV→BGR conversion.
  // Reused across frames to avoid allocating Uint8List(w*h*3) every frame.
  Uint8List? _bgrBuffer;
  int _bgrW = 0;
  int _bgrH = 0;

  final Map<String, String> _liveStats = {
    '投篮': '0',
    '命中': '0',
    '命中率': '0%',
    '篮筐': '搜索中',
  };

  @override
  void initState() {
    super.initState();
    _initCameras();
    _checkOnnx();
  }

  Future<void> _checkOnnx() async {
    try {
      final modelPath = '${Directory.current.path}/assets/models/best.onnx';
      final available = await _processor.enableOnnx(modelPath: modelPath);
      if (mounted) {
        setState(() => _onnxAvailable = available);
      }
    } catch (_) {
      // ONNX 不可用
    }
  }

  Future<void> _initCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty && mounted) {
        setState(() => _error = '未检测到摄像头');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '摄像头不可用: $e');
      }
    }
  }

  Future<void> _startStream() async {
    if (_cameras.isEmpty) {
      setState(() => _error = '没有可用的摄像头');
      return;
    }

    setState(() {
      _isInitializing = true;
      _error = null;
    });

    // 启用 ONNX（如果选择）
    if (_useOnnx && _onnxAvailable) {
      await _processor.enableOnnx();
    } else {
      // 确保使用颜色检测
      _processor.reset();
    }

    try {
      final camera = _cameras[_selectedCamera % _cameras.length];
      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      _processor.reset();
      _frameIndex = 0;

      await _cameraController!.startImageStream(_processCameraImage);

      if (mounted) {
        setState(() {
          _isStreaming = true;
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _error = '启动摄像头失败: $e';
        });
      }
    }
  }

  Future<void> _stopStream() async {
    if (_cameraController != null) {
      if (_cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
      await _cameraController!.dispose();
      _cameraController = null;
    }
    if (mounted) {
      setState(() => _isStreaming = false);
    }
  }

  void _processCameraImage(CameraImage image) {
    _frameIndex++;

    // 每 3 帧处理一次，降低 CPU 负载
    if (_frameIndex % 3 != 0) return;

    // ONNX 模式：异步处理，跳过正在处理的帧
    if (_useOnnx && _onnxAvailable) {
      if (_onnxProcessing) return;
      _onnxProcessing = true;
      final bgrBytes = _yuv420ToBgr(image);
      if (bgrBytes != null) {
        _processor.processSingleFrameAsync(
          bgrBytes, image.width, image.height, _frameIndex,
        ).then((_) {
          _onnxProcessing = false;
          if (_frameIndex % 90 == 0 && mounted) {
            final stats = _processor.getCurrentStats();
            setState(() => _liveStats.addAll(stats));
          }
        }).catchError((_) {
          _onnxProcessing = false;
        });
      } else {
        _onnxProcessing = false;
      }
      return;
    }

    // 颜色检测模式：同步处理
    try {
      final bgrBytes = _yuv420ToBgr(image);
      if (bgrBytes != null) {
        _processor.processSingleFrame(
          bgrBytes, image.width, image.height, _frameIndex,
        );

        // 每 30 帧更新一次 HUD
        if (_frameIndex % 90 == 0 && mounted) {
          final stats = _processor.getCurrentStats();
          setState(() => _liveStats.addAll(stats));
        }
      }
    } catch (_) {
      // 帧处理失败静默跳过
    }
  }

  /// YUV420 (camera) → BGR (detector)
  Uint8List? _yuv420ToBgr(CameraImage image) {
    if (image.planes.length < 3) return null;

    final yPlane = image.planes[0].bytes;
    final uPlane = image.planes[1].bytes;
    final vPlane = image.planes[2].bytes;
    final yRowStride = image.planes[0].bytesPerRow;
    final uvRowStride = image.planes[1].bytesPerRow;
    final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    final w = image.width;
    final h = image.height;
    final needed = w * h * 3;

    // Reuse pre-allocated buffer when dimensions match
    if (_bgrBuffer == null || _bgrW != w || _bgrH != h) {
      _bgrBuffer = Uint8List(needed);
      _bgrW = w;
      _bgrH = h;
    }
    final bgr = _bgrBuffer!;

    for (int row = 0; row < h; row++) {
      for (int col = 0; col < w; col++) {
        final yIndex = row * yRowStride + col;
        final uvRow = row ~/ 2;
        final uvCol = col ~/ 2;
        final uvIndex = uvRow * uvRowStride + uvCol * uvPixelStride;

        if (yIndex >= yPlane.length || uvIndex >= uPlane.length) continue;

        final y = yPlane[yIndex];
        final u = uPlane[uvIndex];
        final v = vPlane[uvIndex];

        // YUV → RGB using fixed-point integer arithmetic.
        // Coefficients scaled by 256: 1.402≈359, 0.344136≈88,
        // 0.714136≈183, 1.772≈454. The +128 before >>8 provides
        // proper rounding (equivalent to .round()).
        final int du = u - 128;
        final int dv = v - 128;
        final int ri = y + ((359 * dv + 128) >> 8);
        final int gi = y - ((88 * du + 183 * dv + 128) >> 8);
        final int bi = y + ((454 * du + 128) >> 8);

        // BGR order, inline clamp (faster than .clamp() method call)
        final idx = (row * w + col) * 3;
        bgr[idx]     = bi < 0 ? 0 : (bi > 255 ? 255 : bi);
        bgr[idx + 1] = gi < 0 ? 0 : (gi > 255 ? 255 : gi);
        bgr[idx + 2] = ri < 0 ? 0 : (ri > 255 ? 255 : ri);
      }
    }

    return bgr;
  }

  @override
  void dispose() {
    _bgrBuffer = null;
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Windows 不支持 camera 包
    if (!kIsWeb && Platform.isWindows) {
      return _buildUnsupported();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 视频预览区域
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isStreaming
                      ? AppColors.success.withAlpha(100)
                      : AppColors.textDim.withAlpha(40),
                  width: 2,
                ),
              ),
              child: _buildCameraPreview(),
            ),
          ),
          const SizedBox(height: 16),

          // 摄像头选择
          if (_cameras.length > 1)
            Row(
              children: [
                const Text(
                  '摄像头:',
                  style: TextStyle(color: AppColors.textDim, fontSize: 13),
                ),
                const SizedBox(width: 8),
                ...List.generate(_cameras.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_cameras[i].name),
                      selected: _selectedCamera == i,
                      onSelected: _isStreaming
                          ? null
                          : (v) {
                              if (v) setState(() => _selectedCamera = i);
                            },
                      selectedColor: AppColors.primary.withAlpha(60),
                      labelStyle: TextStyle(
                        color: _selectedCamera == i
                            ? AppColors.primary
                            : AppColors.textDim,
                        fontSize: 12,
                      ),
                      side: BorderSide(
                        color: _selectedCamera == i
                            ? AppColors.primary
                            : AppColors.textDim.withAlpha(60),
                      ),
                      backgroundColor: AppColors.surface,
                    ),
                  );
                }),
              ],
            ),
          const SizedBox(height: 12),

          // ONNX 模型开关
          if (_onnxAvailable && !_isStreaming)
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
          if (_onnxAvailable && !_isStreaming) const SizedBox(height: 12),

          // 启动/停止按钮
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isInitializing
                  ? null
                  : (_isStreaming ? _stopStream : _startStream),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isStreaming ? AppColors.error : AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isInitializing
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('正在启动摄像头...'),
                      ],
                    )
                  : Text(
                      _isStreaming ? '停止检测' : '启动实时检测',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: AppColors.error, fontSize: 14)),
          ],
        ),
      );
    }

    if (_isStreaming && _cameraController != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CameraPreview(_cameraController!),
          ),
          // HUD 叠加
          Positioned(top: 12, left: 12, child: _buildHud()),
          // 录制指示
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(180),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_manual_record,
                      size: 10, color: Colors.white),
                  SizedBox(width: 4),
                  Text('LIVE',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          // 帧计数
          Positioned(
            bottom: 12,
            right: 12,
            child: Text(
              'Frame: $_frameIndex',
              style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withAlpha(150),
                  fontFamily: 'monospace'),
            ),
          ),
        ],
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_off,
              size: 48, color: AppColors.textDim.withAlpha(100)),
          const SizedBox(height: 12),
          const Text(
            '点击下方按钮启动实时检测',
            style: TextStyle(color: AppColors.textDim, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildUnsupported() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.desktop_windows,
                size: 64, color: AppColors.textDim.withAlpha(80)),
            const SizedBox(height: 16),
            const Text(
              'Windows 暂不支持实时摄像头',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text),
            ),
            const SizedBox(height: 8),
            Text(
              '请使用"上传"页面分析视频文件，\n或在 Android/iOS 设备上使用实时检测。',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: AppColors.textDim.withAlpha(180)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHud() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(160),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.secondary.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SHOT ANALYZER',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: AppColors.secondary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          ..._liveStats.entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  '${e.key}: ${e.value}',
                  style: TextStyle(
                    fontSize: 11,
                    color: e.key == '命中'
                        ? AppColors.success
                        : e.key == '投篮'
                            ? AppColors.secondary
                            : AppColors.text,
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
