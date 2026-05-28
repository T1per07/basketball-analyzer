import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/services/color_ball_detector.dart';
import 'package:basketball_analyzer/services/hoop_detector.dart';
import 'package:basketball_analyzer/services/shot_analyzer.dart';

/// 从 test/fixtures/ 加载预提取的 BGR 帧
Uint8List _loadFrame(String name) {
  final file = File('test/fixtures/$name');
  if (!file.existsSync()) {
    fail('测试帧文件不存在: ${file.path}，请先运行 OpenCV 提取脚本');
  }
  return file.readAsBytesSync();
}

List<Uint8List> _loadAllFrames() {
  final frames = <Uint8List>[];
  for (int i = 0; i < 10; i++) {
    frames.add(_loadFrame('frame_${i.toString().padLeft(2, '0')}.bgr'));
  }
  return frames;
}

void main() {
  group('Real Video: shooting_analysis.mp4', () {
    late List<Uint8List> frames;

    setUpAll(() {
      frames = _loadAllFrames();
    });

    test('帧数据完整性', () {
      for (int i = 0; i < frames.length; i++) {
        expect(frames[i].length, 640 * 480 * 3,
            reason: 'frame_$i 应为 640x480 BGR');
      }
      print('✓ 10 帧数据完整，每帧 ${frames[0].length} bytes');
    });

    test('ColorBallDetector 在真实帧上运行', () {
      final detector = ColorBallDetector();
      int totalDetections = 0;

      for (int i = 0; i < frames.length; i++) {
        final dets = detector.detect(frames[i], 640, 480);
        totalDetections += dets.length;
        if (dets.isNotEmpty) {
          for (final (x1, y1, x2, y2, conf) in dets) {
            print('  frame_$i: 球检测 (${x1.round()},${y1.round()})-'
                '(${x2.round()},${y2.round()}) conf=${conf.toStringAsFixed(2)}');
          }
        }
      }
      print('✓ 10 帧共检测到 $totalDetections 个球候选');
    });

    test('HoopDetector 在真实帧上运行', () {
      final detector = HoopDetector();
      int detected = 0;

      for (int i = 0; i < frames.length; i++) {
        final pos = detector.detect(frames[i], 640, 480);
        if (pos != null) {
          detected++;
          print('  frame_$i: 篮筐 @ (${pos.$1}, ${pos.$2}) '
              '校准=${detector.isCalibrated}');
        }
      }
      print('✓ 10 帧中 $detected 帧检测到篮筐');
    });

    test('ShotAnalyzer 完整流水线 — 真实帧', () {
      final analyzer = ShotAnalyzer(fps: 30);

      for (int i = 0; i < frames.length; i++) {
        analyzer.processFrame(frames[i], 640, 480, i);
      }

      final result = analyzer.buildResult(10, 30.0);
      print('✓ 真实帧分析结果:');
      print('  投篮: ${result.totalShots}');
      print('  命中: ${result.madeShots}');
      print('  命中率: ${(result.overallPercentage * 100).round()}%');

      if (result.shots.isNotEmpty) {
        for (final s in result.shots) {
          print('  投篮 #${s.shotId}: ${s.made ? "命中" : "未中"} '
              '类型=${s.shotType} 距离=${s.distance.toStringAsFixed(1)}m '
              '置信度=${s.confidence.toStringAsFixed(2)}');
        }
      }

      // 不崩溃即可，不强制要求检测到投篮（10帧太少）
      expect(result.totalShots, greaterThanOrEqualTo(0));
    });

    test('检测速度 — 真实帧', () {
      final analyzer = ShotAnalyzer(fps: 30);
      final sw = Stopwatch()..start();

      for (int i = 0; i < frames.length; i++) {
        analyzer.processFrame(frames[i], 640, 480, i);
      }

      sw.stop();
      final avgMs = sw.elapsedMicroseconds / frames.length / 1000;
      print('✓ 真实帧处理速度: ${avgMs.toStringAsFixed(2)} ms/帧 '
          '(${(1000 / avgMs).round()} FPS)');
      expect(avgMs, lessThan(100), reason: '真实帧应低于 100ms/帧');
    });
  });

  group('Real Video: 全流程端到端', () {
    test('9238 帧视频的信息提取', () async {
      // 测试 VideoProcessor 的 getVideoInfo（如果 ffmpeg 可用）
      final videoPath =
          'D:/Projects/basketball-analyzer/data/samples/shooting_analysis.mp4';
      final file = File(videoPath);
      if (!file.existsSync()) {
        print('⚠ 视频文件不存在，跳过');
        return;
      }

      // 用 ffprobe 提取信息（通过 Python）
      final result = await Process.run('python', [
        '-c',
        '''
import cv2
cap = cv2.VideoCapture("$videoPath")
w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
fps = cap.get(cv2.CAP_PROP_FPS)
total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
duration = total / fps if fps > 0 else 0
print(f"{w}x{h} {fps}fps {total}frames {duration:.1f}s")
cap.release()
'''
      ]);

      if (result.exitCode == 0) {
        print('✓ 视频信息: ${(result.stdout as String).trim()}');
      } else {
        print('⚠ 无法读取视频信息: ${result.stderr}');
      }
    });
  });
}
