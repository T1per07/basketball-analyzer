import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/services/color_ball_detector.dart';
import 'package:basketball_analyzer/services/hoop_detector.dart';
import 'package:basketball_analyzer/services/shot_analyzer.dart';
import 'package:basketball_analyzer/models/models.dart';

Uint8List _loadFrame(String name) {
  final file = File('test/fixtures/$name');
  if (!file.existsSync()) {
    fail('文件不存在: ${file.path}');
  }
  return file.readAsBytesSync();
}

List<Uint8List> _loadSegment(String prefix, int count) {
  return List.generate(count, (i) => _loadFrame('${prefix}_${i.toString().padLeft(2, '0')}.bgr'));
}

void main() {
  group('Real Video Segment 1: 开头 (帧 30-59)', () {
    late List<Uint8List> frames;
    setUpAll(() => frames = _loadSegment('seg1', 30));

    test('HoopDetector 校准', () {
      final detector = HoopDetector();
      int detected = 0;
      for (int i = 0; i < frames.length; i++) {
        final pos = detector.detect(frames[i], 640, 480);
        if (pos != null) detected++;
      }
      print('Seg1: $detected/30 帧检测到篮筐, 校准=${detector.isCalibrated}');
      if (detector.hoopBox != null) {
        final (x, y, w, h) = detector.hoopBox!;
        print('  篮筐位置: ($x, $y) 大小: ${w}x$h');
      }
    });

    test('ColorBallDetector 球检测统计', () {
      final detector = ColorBallDetector();
      int totalDets = 0;
      for (int i = 0; i < frames.length; i++) {
        final dets = detector.detect(frames[i], 640, 480);
        totalDets += dets.length;
      }
      print('Seg1: $totalDets 个球候选 (30帧)');
    });

    test('ShotAnalyzer 完整流水线', () {
      final analyzer = ShotAnalyzer(fps: 30);
      for (int i = 0; i < frames.length; i++) {
        analyzer.processFrame(frames[i], 640, 480, i);
      }
      final result = analyzer.buildResult(30, 30.0);
      print('Seg1: ${result.totalShots} 投篮, ${result.madeShots} 命中');
      for (final s in result.shots) {
        print('  #${s.shotId}: ${s.made ? "命中" : "未中"} ${s.shotType} '
            '${s.distance.toStringAsFixed(1)}m conf=${s.confidence.toStringAsFixed(2)}');
      }
    });
  });

  group('Real Video Segment 2: 中间 (帧 4500-4529)', () {
    late List<Uint8List> frames;
    setUpAll(() => frames = _loadSegment('seg2', 30));

    test('HoopDetector 校准', () {
      final detector = HoopDetector();
      int detected = 0;
      for (int i = 0; i < frames.length; i++) {
        final pos = detector.detect(frames[i], 640, 480);
        if (pos != null) detected++;
      }
      print('Seg2: $detected/30 帧检测到篮筐, 校准=${detector.isCalibrated}');
      if (detector.hoopBox != null) {
        final (x, y, w, h) = detector.hoopBox!;
        print('  篮筐位置: ($x, $y) 大小: ${w}x$h');
      }
    });

    test('ColorBallDetector 球检测统计', () {
      final detector = ColorBallDetector();
      int totalDets = 0;
      for (int i = 0; i < frames.length; i++) {
        final dets = detector.detect(frames[i], 640, 480);
        totalDets += dets.length;
      }
      print('Seg2: $totalDets 个球候选 (30帧)');
    });

    test('ShotAnalyzer 完整流水线', () {
      final analyzer = ShotAnalyzer(fps: 30);
      for (int i = 0; i < frames.length; i++) {
        analyzer.processFrame(frames[i], 640, 480, i);
      }
      final result = analyzer.buildResult(30, 30.0);
      print('Seg2: ${result.totalShots} 投篮, ${result.madeShots} 命中');
      for (final s in result.shots) {
        print('  #${s.shotId}: ${s.made ? "命中" : "未中"} ${s.shotType} '
            '${s.distance.toStringAsFixed(1)}m conf=${s.confidence.toStringAsFixed(2)}');
      }
    });
  });

  group('Real Video Segment 3: 结尾 (帧 8000-8029)', () {
    late List<Uint8List> frames;
    setUpAll(() => frames = _loadSegment('seg3', 30));

    test('HoopDetector 校准', () {
      final detector = HoopDetector();
      int detected = 0;
      for (int i = 0; i < frames.length; i++) {
        final pos = detector.detect(frames[i], 640, 480);
        if (pos != null) detected++;
      }
      print('Seg3: $detected/30 帧检测到篮筐, 校准=${detector.isCalibrated}');
      if (detector.hoopBox != null) {
        final (x, y, w, h) = detector.hoopBox!;
        print('  篮筐位置: ($x, $y) 大小: ${w}x$h');
      }
    });

    test('ColorBallDetector 球检测统计', () {
      final detector = ColorBallDetector();
      int totalDets = 0;
      for (int i = 0; i < frames.length; i++) {
        final dets = detector.detect(frames[i], 640, 480);
        totalDets += dets.length;
      }
      print('Seg3: $totalDets 个球候选 (30帧)');
    });

    test('ShotAnalyzer 完整流水线', () {
      final analyzer = ShotAnalyzer(fps: 30);
      for (int i = 0; i < frames.length; i++) {
        analyzer.processFrame(frames[i], 640, 480, i);
      }
      final result = analyzer.buildResult(30, 30.0);
      print('Seg3: ${result.totalShots} 投篮, ${result.madeShots} 命中');
      for (final s in result.shots) {
        print('  #${s.shotId}: ${s.made ? "命中" : "未中"} ${s.shotType} '
            '${s.distance.toStringAsFixed(1)}m conf=${s.confidence.toStringAsFixed(2)}');
      }
    });
  });

  group('跨片段对比', () {
    test('3 个片段的检测一致性', () {
      final results = <String, int>{};
      for (final prefix in ['seg1', 'seg2', 'seg3']) {
        final frames = _loadSegment(prefix, 30);
        final analyzer = ShotAnalyzer(fps: 30);
        for (int i = 0; i < frames.length; i++) {
          analyzer.processFrame(frames[i], 640, 480, i);
        }
        final result = analyzer.buildResult(30, 30.0);
        results[prefix] = result.totalShots;
      }
      print('跨片段投篮检测:');
      for (final e in results.entries) {
        print('  ${e.key}: ${e.value} 次投篮');
      }
    });
  });
}
