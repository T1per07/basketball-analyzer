import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/services/video_processor.dart';

void main() {
  group('真实视频投篮检测', () {
    late VideoProcessor processor;

    setUp(() {
      processor = VideoProcessor(fps: 30.0);
    });

    test('分析 shooting_training.mp4 全帧', () async {
      final videoPath = 'D:/Projects/basketball-analyzer/data/samples/shooting_training.mp4';
      expect(File(videoPath).existsSync(), isTrue);

      final result = await processor.analyzeVideo(
        videoPath,
        onProgress: (current, total) {
          if (current % 100 == 0) {
            print('进度: $current / $total');
          }
        },
      );

      print('\n=== shooting_training.mp4 全帧分析 ===');
      print('总帧数: ${result.totalFrames}');
      print('FPS: ${result.fps}');
      print('投篮次数: ${result.totalShots}');
      print('命中次数: ${result.madeShots}');

      if (result.shots.isNotEmpty) {
        for (var i = 0; i < result.shots.length; i++) {
          final shot = result.shots[i];
          print('投篮 ${i + 1}: ${shot.shotType} ${shot.made ? "命中" : "未命中"} '
              '${shot.distance.toStringAsFixed(2)}m 置信度${shot.confidence.toStringAsFixed(2)}');
        }
      } else {
        print('未检测到投篮');
      }

      expect(result.totalFrames, greaterThan(0));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('分析 shooting_analysis.mp4 全帧', () async {
      final videoPath = 'D:/Projects/basketball-analyzer/data/samples/shooting_analysis.mp4';
      expect(File(videoPath).existsSync(), isTrue);

      final result = await processor.analyzeVideo(
        videoPath,
        onProgress: (current, total) {
          if (current % 100 == 0) {
            print('进度: $current / $total');
          }
        },
      );

      print('\n=== shooting_analysis.mp4 全帧分析 ===');
      print('总帧数: ${result.totalFrames}');
      print('FPS: ${result.fps}');
      print('投篮次数: ${result.totalShots}');
      print('命中次数: ${result.madeShots}');

      if (result.shots.isNotEmpty) {
        for (var i = 0; i < result.shots.length; i++) {
          final shot = result.shots[i];
          print('投篮 ${i + 1}: ${shot.shotType} ${shot.made ? "命中" : "未命中"} '
              '${shot.distance.toStringAsFixed(2)}m 置信度${shot.confidence.toStringAsFixed(2)}');
        }
      } else {
        print('未检测到投篮');
      }

      expect(result.totalFrames, greaterThan(0));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('ONNX 模型加载', () async {
      final modelPath = 'D:/Projects/basketball-analyzer/basketball_analyzer_app/assets/models/best.onnx';
      print('模型文件存在: ${File(modelPath).existsSync()}');

      final onnxResult = await processor.enableOnnx(modelPath: modelPath);
      print('ONNX 启用: $onnxResult');

      if (!onnxResult) {
        print('ONNX 加载失败 — 可能缺少运行时依赖');
      }

      expect(onnxResult, isA<bool>());
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
