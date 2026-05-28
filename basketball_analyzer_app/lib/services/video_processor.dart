import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import '../models/models.dart';
import 'shot_analyzer.dart';

/// 视频信息
class VideoInfo {
  final String path;
  final int width;
  final int height;
  final double fps;
  final int totalFrames;
  final double duration;

  const VideoInfo({
    required this.path,
    required this.width,
    required this.height,
    required this.fps,
    required this.totalFrames,
    required this.duration,
  });
}

/// 帧数据
class FrameData {
  final int index;
  final Uint8List bgrBytes;
  final int width;
  final int height;

  const FrameData({
    required this.index,
    required this.bgrBytes,
    required this.width,
    required this.height,
  });
}

/// 视频处理服务 — 读帧 + 逐帧分析
/// 对应 Python services/video_processor.py
///
/// 使用 ffmpeg 子进程读帧（跨平台方案），
/// 后续可替换为 opencv_dart FFI 以获得更好性能。
class VideoProcessor {
  final ShotAnalyzer analyzer;
  VideoInfo? _videoInfo;
  bool _onnxEnabled = false;

  // Pre-allocated accumulation buffer for ffmpeg stdout chunks.
  // Replaces BytesBuilder to avoid repeated toBytes() copies of the
  // entire accumulated buffer on every frame extraction.
  Uint8List _accumBuffer = Uint8List(0);
  int _bufferPos = 0;

  VideoProcessor({double fps = 30.0}) : analyzer = ShotAnalyzer(fps: fps);

  /// 启用 ONNX 模型检测
  Future<bool> enableOnnx({String? modelPath}) async {
    try {
      await analyzer.onnxDetector.init(modelPath: modelPath);
      analyzer.enableOnnx();
      _onnxEnabled = analyzer.onnxDetector.isInitialized;
      return _onnxEnabled;
    } catch (_) {
      _onnxEnabled = false;
      return false;
    }
  }

  VideoInfo? get videoInfo => _videoInfo;

  /// 获取视频信息（通过 ffprobe）
  Future<VideoInfo> getVideoInfo(String videoPath) async {
    final result = await Process.run('ffprobe', [
      '-v', 'quiet',
      '-print_format', 'json',
      '-show_format',
      '-show_streams',
      videoPath,
    ]);

    if (result.exitCode != 0) {
      throw Exception('ffprobe failed: ${result.stderr}');
    }

    // 简化解析 — 用正则提取关键信息
    final output = result.stdout as String;
    final width = _extractInt(output, r'"width"\s*:\s*(\d+)') ?? 854;
    final height = _extractInt(output, r'"height"\s*:\s*(\d+)') ?? 480;
    final fps = _extractDouble(output, r'"r_frame_rate"\s*:\s*"(\d+)/(\d+)"') ??
        _extractDouble(output, r'"avg_frame_rate"\s*:\s*"(\d+)/(\d+)"') ??
        30.0;
    final duration =
        _extractDouble(output, r'"duration"\s*:\s*"([\d.]+)"') ?? 0.0;
    final totalFrames =
        _extractInt(output, r'"nb_frames"\s*:\s*"(\d+)"') ??
            (duration * fps).round();

    _videoInfo = VideoInfo(
      path: videoPath,
      width: width,
      height: height,
      fps: fps,
      totalFrames: totalFrames,
      duration: duration,
    );
    return _videoInfo!;
  }

  /// 分析视频 — 逐帧处理
  /// [maxFrames] 限制最大处理帧数（用于测试或预览）
  Future<AnalysisResult> analyzeVideo(
    String videoPath, {
    void Function(int current, int total)? onProgress,
    int? maxFrames,
  }) async {
    final info = await getVideoInfo(videoPath);
    analyzer.trajectoryAnalyzer.setFrameWidth(info.width);
    analyzer.trajectoryAnalyzer.setFps(info.fps);
    analyzer.shotDetector.setFps(info.fps);

    final skip = (info.fps / AppConfig.video.targetProcessFps).round().clamp(1, 10);
    final effectiveTotal = maxFrames != null
        ? min(maxFrames, info.totalFrames)
        : info.totalFrames;

    // 使用 ffmpeg 提取帧
    final ffmpegArgs = <String>[
      '-loglevel', 'error',
      '-i', videoPath,
      '-vf', 'scale=${info.width}:${info.height}',
      '-f', 'rawvideo',
      '-pix_fmt', 'bgr24',
    ];
    if (maxFrames != null) {
      ffmpegArgs.addAll(['-frames:v', '$maxFrames']);
    }
    ffmpegArgs.add('-');

    final process = await Process.start('ffmpeg', ffmpegArgs);
    // 消费 stderr 防止缓冲区阻塞
    process.stderr.drain();

    final frameSize = info.width * info.height * 3;
    _accumBuffer = Uint8List(frameSize * 4);
    _bufferPos = 0;
    int frameIndex = 0;

    await for (final chunk in process.stdout) {
      // Ensure accumulation buffer has room for the incoming chunk
      if (_bufferPos + chunk.length > _accumBuffer.length) {
        final newBuf = Uint8List((_bufferPos + chunk.length) * 2);
        newBuf.setRange(0, _bufferPos, _accumBuffer);
        _accumBuffer = newBuf;
      }
      _accumBuffer.setRange(_bufferPos, _bufferPos + chunk.length, chunk);
      _bufferPos += chunk.length;

      while (_bufferPos >= frameSize) {
        // Copy only the frame portion out (one allocation, no full-buffer copy)
        final frameBytes = Uint8List(frameSize);
        frameBytes.setRange(0, frameSize, _accumBuffer);

        // Shift remaining bytes to front in-place (avoids allocating
        // a second copy for the tail like the old BytesBuilder approach)
        final remaining = _bufferPos - frameSize;
        if (remaining > 0) {
          _accumBuffer.setRange(0, remaining, _accumBuffer, frameSize);
        }
        _bufferPos = remaining;

        if (frameIndex % skip == 0) {
          if (_onnxEnabled) {
            await analyzer.processFrameOnnxAsync(
              frameBytes, info.width, info.height, frameIndex,
            );
          } else {
            analyzer.processFrame(
              frameBytes, info.width, info.height, frameIndex,
            );
          }
        }

        frameIndex++;
        if (onProgress != null && frameIndex % 30 == 0) {
          onProgress(frameIndex, effectiveTotal);
        }
      }
    }

    await process.exitCode;
    return analyzer.buildResult(frameIndex, info.fps);
  }

  /// 分析单帧（同步，颜色检测）
  void processSingleFrame(Uint8List bgrBytes, int width, int height, int frameIndex) {
    analyzer.processFrame(bgrBytes, width, height, frameIndex);
  }

  /// 分析单帧（异步，ONNX 检测）
  Future<void> processSingleFrameAsync(
    Uint8List bgrBytes, int width, int height, int frameIndex,
  ) async {
    if (_onnxEnabled) {
      await analyzer.processFrameOnnxAsync(bgrBytes, width, height, frameIndex);
    } else {
      analyzer.processFrame(bgrBytes, width, height, frameIndex);
    }
  }

  Map<String, String> getCurrentStats() => analyzer.getCurrentStats();

  void reset() => analyzer.reset();

  int? _extractInt(String json, String pattern) {
    final match = RegExp(pattern).firstMatch(json);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  double? _extractDouble(String json, String pattern) {
    final match = RegExp(pattern).firstMatch(json);
    if (match == null) return null;
    final g1 = match.group(1)!;
    if (match.groupCount >= 2) {
      final g2 = match.group(2);
      if (g2 != null) {
        return int.parse(g1) / int.parse(g2);
      }
    }
    return double.tryParse(g1);
  }
}
