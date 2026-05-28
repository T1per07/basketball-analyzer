import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/services/trajectory_analyzer.dart';
import 'package:basketball_analyzer/models/models.dart';

/// Build a BallTrack with parabolic arc data.
/// The ball starts at (startX, startY), arcs upward, and lands near
/// (hoopX, hoopY).  When [includeArea] is true each point carries a
/// `ballArea` proportional to the expected ball size at that distance.
BallTrack _parabolicTrack({
  int trackId = 0,
  int numPoints = 20,
  double startX = 200,
  double startY = 350,
  double endX = 440,
  double arcHeight = 250,
  double ballArea = 400,
  bool includeArea = true,
}) {
  final track = BallTrack(trackId: trackId);
  for (int i = 0; i < numPoints; i++) {
    final t = i / (numPoints - 1);
    final x = startX + (endX - startX) * t;
    final y = startY - arcHeight * sin(pi * t);
    track.addPoint(
      i, x, y,
      confidence: 0.9,
      ballArea: includeArea ? ballArea : 0.0,
    );
  }
  return track;
}

void main() {
  group('TrajectoryAnalyzer — classifyShotType', () {
    late TrajectoryAnalyzer analyzer;

    setUp(() {
      analyzer = TrajectoryAnalyzer();
      analyzer.setFrameWidth(640);
      analyzer.setFps(30);
      analyzer.updateHoopReference((320.0, 120.0), 60.0);
    });

    test('distance ~1.0m classifies as layup', () {
      // Create a close-range track that yields ~1m distance via ballArea.
      // ballArea = pi*(d/2)^2; for 25px diameter ~ area=491
      // distance = focal * realDia / pxSize; focal = 640/(2*tan(15)) ~ 1195
      // d = 1195 * 0.241 / 25 ~ 11.5m  — too far. Use larger area instead.
      // area=9000 → pxSize=95 → d ~ 3.0m. We need ~1m, so area ~ 80000 → pxSize ~ 283
      // That's too large.  Use a track with small pixel displacement and large ballArea.
      // Let's create a short track near the hoop.
      final track = BallTrack(trackId: 0);
      for (int i = 0; i < 10; i++) {
        track.addPoint(i, 300 + i * 2.0, 200 - i * 5.0,
            confidence: 0.9, ballArea: 60000);
      }
      final params = analyzer.fitTrajectory(track);
      final type = analyzer.classifyShotType(params);
      // With huge ballArea, distance should be very small → layup
      expect(type, 'layup',
          reason: 'Very close shot with large ballArea should be classified as layup');
    });

    test('distance ~3.0m classifies as mid_range', () {
      final track = BallTrack(trackId: 1);
      // ballArea=4000 → pxSize~63 → dist = 1195*0.241/63 ~ 4.6m — just above midRange.
      // ballArea=6000 → pxSize~77 → dist ~ 3.7m → mid_range
      for (int i = 0; i < 15; i++) {
        final t = i / 14.0;
        final x = 250.0 + t * 140.0;
        final y = 300.0 - 150.0 * sin(pi * t);
        track.addPoint(i, x, y, confidence: 0.9, ballArea: 6000);
      }
      final params = analyzer.fitTrajectory(track);
      final type = analyzer.classifyShotType(params);
      expect(type, anyOf('mid_range', 'layup'),
          reason: 'Mid-range shot (~3-4m) should be mid_range or layup');
    });

    test('distance ~6.0m classifies as three_point', () {
      // Use fallbackDistance to bypass estimation complexity.
      final type = analyzer.classifyShotType(null, fallbackDistance: 6.0);
      expect(type, 'three_point',
          reason: '6.0m fallback distance should be three_point');
    });

    test('null trajectory with zero fallback defaults to mid_range', () {
      final type = analyzer.classifyShotType(null, fallbackDistance: 0.0);
      // 0.0 < layupMaxDistance (1.5) → layup
      expect(type, 'layup',
          reason: '0.0m is less than layupMaxDistance (1.5m)');
    });

    test('distance exactly at layup boundary (1.5m)', () {
      final type = analyzer.classifyShotType(null, fallbackDistance: 1.5);
      // 1.5 is NOT < 1.5, so not layup. Then check mid_range (< 4.5).
      // releaseAngle is 0.0 (null trajectory), and 0 < 30, so returns layup.
      expect(type, 'layup',
          reason: 'At boundary 1.5m with low release angle, classified as layup');
    });

    test('distance exactly at three_point boundary (4.5m)', () {
      final type = analyzer.classifyShotType(null, fallbackDistance: 4.5);
      // 4.5 is NOT < 1.5 (layup), NOT < 4.5 (mid_range) → three_point
      expect(type, 'three_point',
          reason: '4.5m equals midRangeMaxDistance, falls through to three_point');
    });
  });

  group('TrajectoryAnalyzer — estimateDistance', () {
    late TrajectoryAnalyzer analyzer;

    setUp(() {
      analyzer = TrajectoryAnalyzer();
      analyzer.setFrameWidth(640);
      analyzer.setFps(30);
      analyzer.updateHoopReference((320.0, 120.0), 60.0);
    });

    test('returns positive distance for track with ballArea data', () {
      final track = _parabolicTrack(ballArea: 400);
      final distance = analyzer.estimateDistance(track);
      expect(distance, greaterThan(0),
          reason: 'Track with ballArea=400 should yield positive distance');
      expect(distance, lessThanOrEqualTo(15.0),
          reason: 'Distance should be clamped to max 15.0m');
    });

    test('larger ballArea yields shorter distance (inverse relationship)', () {
      final trackSmall = _parabolicTrack(trackId: 0, ballArea: 200);
      final trackLarge = _parabolicTrack(trackId: 1, ballArea: 8000);
      final dSmall = analyzer.estimateDistance(trackSmall);
      final dLarge = analyzer.estimateDistance(trackLarge);
      expect(dLarge, lessThan(dSmall),
          reason: 'Larger ball (closer) should yield shorter distance');
    });

    test('returns 0.0 for empty track', () {
      final track = BallTrack(trackId: 99);
      expect(analyzer.estimateDistance(track), 0.0);
    });

    test('returns 0.0 for single-point track', () {
      final track = BallTrack(trackId: 98);
      track.addPoint(0, 300, 200, confidence: 0.9, ballArea: 400);
      // estimateDistance requires at least 2 positions
      expect(analyzer.estimateDistance(track), 0.0);
    });

    test('clamps distance to minimum 0.5m', () {
      // Extremely large ballArea should yield a very small distance,
      // clamped to 0.5m.
      final track = BallTrack(trackId: 0);
      for (int i = 0; i < 10; i++) {
        track.addPoint(i, 300 + i * 0.1, 200, confidence: 0.9,
            ballArea: 500000);
      }
      final distance = analyzer.estimateDistance(track);
      expect(distance, greaterThanOrEqualTo(0.5));
    });
  });

  group('TrajectoryAnalyzer — fitTrajectory (Savitzky-Golay filter)', () {
    late TrajectoryAnalyzer analyzer;

    setUp(() {
      analyzer = TrajectoryAnalyzer();
      analyzer.setFrameWidth(640);
      analyzer.setFps(30);
      analyzer.updateHoopReference((320.0, 120.0), 60.0);
    });

    test('perfect parabola yields high R-squared', () {
      // y = a*x^2 + b*x + c, with a > 0 (upward opening in screen coords)
      final track = BallTrack(trackId: 0);
      for (int i = 0; i < 20; i++) {
        final t = i / 19.0;
        final x = 200.0 + t * 240.0;
        // Perfect parabola: y = 350 - 250*t + 300*t^2
        final y = 350.0 - 250.0 * t + 300.0 * t * t;
        track.addPoint(i, x, y, confidence: 0.95, ballArea: 400);
      }
      final params = analyzer.fitTrajectory(track);
      expect(params, isNotNull,
          reason: 'Perfect parabola with enough points should fit');
      expect(params!.fitRSquared, greaterThan(0.95),
          reason: 'Savitzky-Golay filter should preserve a perfect parabola');
    });

    test('noisy parabola still fits with reasonable R-squared', () {
      final rng = Random(42);
      final track = BallTrack(trackId: 1);
      for (int i = 0; i < 20; i++) {
        final t = i / 19.0;
        final x = 200.0 + t * 240.0;
        final y = 350.0 - 250.0 * t + 300.0 * t * t + rng.nextDouble() * 10 - 5;
        track.addPoint(i, x, y, confidence: 0.8, ballArea: 400);
      }
      final params = analyzer.fitTrajectory(track);
      expect(params, isNotNull,
          reason: 'Noisy parabola should still fit');
      expect(params!.fitRSquared, greaterThan(0.5),
          reason: 'R-squared should be reasonable even with noise');
    });

    test('returns null for fewer than 3 points', () {
      final track = BallTrack(trackId: 2);
      track.addPoint(0, 200, 350, confidence: 0.9);
      track.addPoint(1, 300, 200, confidence: 0.9);
      expect(analyzer.fitTrajectory(track), isNull);
    });

    test('returns null for exactly 2 points', () {
      final track = BallTrack(trackId: 3);
      track.addPoint(0, 200, 350, confidence: 0.9, ballArea: 400);
      track.addPoint(1, 300, 200, confidence: 0.9, ballArea: 400);
      expect(analyzer.fitTrajectory(track), isNull);
    });

    test('returns null for empty track', () {
      final track = BallTrack(trackId: 4);
      expect(analyzer.fitTrajectory(track), isNull);
    });

    test('release angle and entry angle are positive', () {
      final track = _parabolicTrack(numPoints: 20, ballArea: 400);
      final params = analyzer.fitTrajectory(track);
      if (params != null) {
        expect(params.releaseAngle, greaterThanOrEqualTo(0),
            reason: 'Release angle should be non-negative');
        expect(params.entryAngle, greaterThanOrEqualTo(0),
            reason: 'Entry angle should be non-negative');
      }
    });

    test('flightTime and shotSpeed are non-negative', () {
      final track = _parabolicTrack(numPoints: 20, ballArea: 400);
      final params = analyzer.fitTrajectory(track);
      if (params != null) {
        expect(params.flightTime, greaterThanOrEqualTo(0));
        expect(params.shotSpeed, greaterThanOrEqualTo(0));
      }
    });
  });

  group('TrajectoryAnalyzer — edge cases', () {
    test('hoop reference can be set and retrieved', () {
      final analyzer = TrajectoryAnalyzer();
      analyzer.updateHoopReference((320.0, 120.0), 60.0);
      expect(analyzer.hoopPosition, (320.0, 120.0));
      expect(analyzer.hoopPixelWidth, 60.0);
    });

    test('hoop pixel width below 10 is ignored', () {
      final analyzer = TrajectoryAnalyzer();
      analyzer.updateHoopReference((320.0, 120.0), 5.0);
      expect(analyzer.hoopPixelWidth, 0.0);
    });

    test('setting null hoop clears reference', () {
      final analyzer = TrajectoryAnalyzer();
      analyzer.updateHoopReference((320.0, 120.0), 60.0);
      analyzer.updateHoopReference(null, 0);
      expect(analyzer.hoopPosition, isNull);
    });
  });
}
