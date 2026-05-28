import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/services/video_processor.dart';

void main() {
  test('VideoProcessor 端到端: ffprobe + ffmpeg 帧提取 + 分析', () async {
    final videoPath = 'D:/Projects/basketball-analyzer/data/samples/shooting_analysis.mp4';
    if (!File(videoPath).existsSync()) {
      print('测试视频不存在: $videoPath，跳过');
      return;
    }

    final processor = VideoProcessor(fps: 30);

    // 1. 获取视频信息
    print('\n1. 获取视频信息...');
    final info = await processor.getVideoInfo(videoPath);
    print('   分辨率: ${info.width}x${info.height}');
    print('   帧率: ${info.fps}');
    print('   总帧数: ${info.totalFrames}');
    print('   时长: ${info.duration.toStringAsFixed(2)}s');

    expect(info.width, greaterThan(0));
    expect(info.height, greaterThan(0));
    expect(info.fps, greaterThan(0));

    // 2. 分析视频 (限制 300 帧)
    print('\n2. 分析视频 (maxFrames=300)...');
    final result = await processor.analyzeVideo(
      videoPath,
      maxFrames: 300,
      onProgress: (current, total) {
        if (current % 100 == 0) print('   帧 $current/$total');
      },
    );

    print('\n3. 分析结果:');
    print('   总帧数: ${result.totalFrames}');
    print('   检测到投篮: ${result.totalShots}');
    print('   命中: ${result.madeShots}');

    for (final shot in result.shots) {
      print('   投篮 #${shot.shotId}: ${shot.shotType} '
          '${shot.made ? "命中" : "未中"} '
          '距离=${shot.distance.toStringAsFixed(1)}m '
          '置信度=${shot.confidence.toStringAsFixed(2)}');
    }

    expect(result.totalFrames, greaterThan(0));
    print('\n=== VideoProcessor 端到端测试通过! ===');
  }, timeout: Timeout(Duration(seconds: 120)));
}
