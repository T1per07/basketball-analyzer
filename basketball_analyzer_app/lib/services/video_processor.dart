import 'dart:async';
import 'dart:io';
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

  VideoProcessor({double fps = 30.0}) : analyzer = ShotAnalyzer(fps: fps);

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
  Future<AnalysisResult> analyzeVideo(
    String videoPath, {
    void Function(int current, int total)? onProgress,
  }) async {
    final info = await getVideoInfo(videoPath);
    analyzer.trajectoryAnalyzer.setFrameWidth(info.width);
    analyzer.trajectoryAnalyzer.setFps(info.fps);
    analyzer.shotDetector.setFps(info.fps);

    final skip = (info.fps / AppConfig.video.targetProcessFps).round().clamp(1, 10);

    // 使用 ffmpeg 提取帧
    final process = await Process.start('ffmpeg', [
      '-i', videoPath,
      '-vf', 'scale=${info.width}:${info.height}',
      '-f', 'rawvideo',
      '-pix_fmt', 'bgr24',
      '-',
    ]);

    final frameSize = info.width * info.height * 3;
    final buffer = BytesBuilder();
    int frameIndex = 0;

    await for (final chunk in process.stdout) {
      buffer.add(chunk);

      while (buffer.length >= frameSize) {
        final bytes = buffer.toBytes();
        final frameBytes = Uint8List.fromList(bytes.sublist(0, frameSize));
        final remaining = Uint8List.fromList(bytes.sublist(frameSize));
        buffer.clear();
        buffer.add(remaining);

        if (frameIndex % skip == 0) {
          analyzer.processFrame(
            frameBytes, info.width, info.height, frameIndex,
          );
        }

        frameIndex++;
        if (onProgress != null && frameIndex % 30 == 0) {
          onProgress(frameIndex, info.totalFrames);
        }
      }
    }

    await process.exitCode;
    return analyzer.buildResult(frameIndex, info.fps);
  }

  /// 分析单帧（用于实时模式）
  void processSingleFrame(Uint8List bgrBytes, int width, int height, int frameIndex) {
    analyzer.processFrame(bgrBytes, width, height, frameIndex);
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
    final g2 = match.group(2);
    if (g2 != null) {
      return int.parse(g1) / int.parse(g2);
    }
    return double.tryParse(g1);
  }
}
