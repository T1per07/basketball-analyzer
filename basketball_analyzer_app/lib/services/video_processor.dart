import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'shot_analyzer.dart';

// 条件导入 ffmpeg_kit（Android/iOS）
import 'package:ffmpeg_kit_flutter_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_full/return_code.dart';

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
/// Android/iOS 使用 ffmpeg_kit，桌面端使用系统 ffmpeg
class VideoProcessor {
  final ShotAnalyzer analyzer;
  VideoInfo? _videoInfo;
  bool _onnxEnabled = false;

  // Pre-allocated accumulation buffer for ffmpeg stdout chunks.
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
    if (Platform.isAndroid || Platform.isIOS) {
      return _getVideoInfoMobile(videoPath);
    }
    return _getVideoInfoDesktop(videoPath);
  }

  /// 移动端获取视频信息（通过 ffmpeg_kit）
  Future<VideoInfo> _getVideoInfoMobile(String videoPath) async {
    final session = await FFprobeKit.getMediaInformation(videoPath);
    final info = session.getMediaInformation();

    if (info == null) {
      throw Exception('ffprobe failed: 无法获取视频信息');
    }

    final streams = info.getStreams();
    int width = 854;
    int height = 480;
    double fps = 30.0;

    for (final stream in streams) {
      final w = stream.getWidth();
      final h = stream.getHeight();
      if (w != null && h != null && w > 0 && h > 0) {
        width = w;
        height = h;
        break;
      }
    }

    // 提取帧率
    final frameRate = info.getStreams().isNotEmpty
        ? info.getStreams().first.getRealFrameRate()
        : null;
    if (frameRate != null && frameRate.contains('/')) {
      final parts = frameRate.split('/');
      if (parts.length == 2) {
        final num = int.tryParse(parts[0]) ?? 30;
        final den = int.tryParse(parts[1]) ?? 1;
        if (den > 0) fps = num / den;
      }
    } else {
      fps = double.tryParse(frameRate ?? '30') ?? 30.0;
    }

    final duration = double.tryParse(info.getDuration() ?? '0') ?? 0.0;
    final totalFrames = (duration * fps).round();

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

  /// 桌面端获取视频信息（通过系统 ffprobe）
  Future<VideoInfo> _getVideoInfoDesktop(String videoPath) async {
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
  Future<AnalysisResult> analyzeVideo(
    String videoPath, {
    void Function(int current, int total)? onProgress,
    int? maxFrames,
  }) async {
    final info = await getVideoInfo(videoPath);
    analyzer.trajectoryAnalyzer.setFrameWidth(info.width);
    analyzer.trajectoryAnalyzer.setFps(info.fps);
    analyzer.shotDetector.setFps(info.fps);

    if (Platform.isAndroid || Platform.isIOS) {
      return _analyzeVideoMobile(info, onProgress: onProgress, maxFrames: maxFrames);
    }
    return _analyzeVideoDesktop(info, onProgress: onProgress, maxFrames: maxFrames);
  }

  /// 移动端视频分析（通过 ffmpeg_kit 提取帧到临时文件，再逐帧读取）
  Future<AnalysisResult> _analyzeVideoMobile(
    VideoInfo info, {
    void Function(int current, int total)? onProgress,
    int? maxFrames,
  }) async {
    final videoPath = info.path;
    final skip = (info.fps / AppConfig.video.targetProcessFps).round().clamp(1, 10);
    final effectiveTotal = maxFrames != null
        ? min(maxFrames, info.totalFrames)
        : info.totalFrames;

    // 使用 ffmpeg_kit 提取帧为 rawvideo 格式
    // 先将视频转为 raw BGR 数据写入临时文件
    final tempDir = Directory.systemTemp;
    final tempFile = '${tempDir.path}/basans_frames_${DateTime.now().millisecondsSinceEpoch}.raw';

    final framesArg = maxFrames != null ? '-frames:v $maxFrames' : '';
    final cmd = '-y -i "$videoPath" -vf scale=${info.width}:${info.height} '
        '-f rawvideo -pix_fmt bgr24 $framesArg "$tempFile"';

    final session = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      throw Exception('ffmpeg 帧提取失败');
    }

    // 读取 raw 文件并逐帧处理
    final file = File(tempFile);
    if (!await file.exists()) {
      throw Exception('帧提取文件不存在');
    }

    final rawBytes = await file.readAsBytes();
    final frameSize = info.width * info.height * 3;
    int frameIndex = 0;
    int offset = 0;

    while (offset + frameSize <= rawBytes.length) {
      if (frameIndex % skip == 0) {
        final frameBytes = Uint8List(frameSize);
        frameBytes.setRange(0, frameSize, rawBytes, offset);

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

      offset += frameSize;
      frameIndex++;
      if (onProgress != null && frameIndex % 30 == 0) {
        onProgress(frameIndex, effectiveTotal);
      }
    }

    // 清理临时文件
    try { await file.delete(); } catch (_) {}

    return analyzer.buildResult(frameIndex, info.fps);
  }

  /// 桌面端视频分析（通过系统 ffmpeg 管道）
  Future<AnalysisResult> _analyzeVideoDesktop(
    VideoInfo info, {
    void Function(int current, int total)? onProgress,
    int? maxFrames,
  }) async {
    final videoPath = info.path;
    final skip = (info.fps / AppConfig.video.targetProcessFps).round().clamp(1, 10);
    final effectiveTotal = maxFrames != null
        ? min(maxFrames, info.totalFrames)
        : info.totalFrames;

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
    process.stderr.drain();

    final frameSize = info.width * info.height * 3;
    _accumBuffer = Uint8List(frameSize * 4);
    _bufferPos = 0;
    int frameIndex = 0;

    await for (final chunk in process.stdout) {
      if (_bufferPos + chunk.length > _accumBuffer.length) {
        final newBuf = Uint8List((_bufferPos + chunk.length) * 2);
        newBuf.setRange(0, _bufferPos, _accumBuffer);
        _accumBuffer = newBuf;
      }
      _accumBuffer.setRange(_bufferPos, _bufferPos + chunk.length, chunk);
      _bufferPos += chunk.length;

      while (_bufferPos >= frameSize) {
        final frameBytes = Uint8List(frameSize);
        frameBytes.setRange(0, frameSize, _accumBuffer);

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
