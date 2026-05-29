import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/models/ball_track.dart';

void main() {
  group('BallTrack', () {
    test('starts empty', () {
      final track = BallTrack(trackId: 0);
      expect(track.length, 0);
      expect(track.positions, isEmpty);
      expect(track.frameIndices, isEmpty);
    });

    test('addPoint increases length and stores data', () {
      final track = BallTrack(trackId: 1);
      track.addPoint(0, 100.0, 200.0, confidence: 0.9, ballArea: 400);
      track.addPoint(1, 102.0, 198.0, confidence: 0.85, ballArea: 380);

      expect(track.length, 2);
      expect(track.positions, [(100.0, 200.0), (102.0, 198.0)]);
      expect(track.frameIndices, [0, 1]);
    });

    test('getCenterAt returns correct position for existing frame', () {
      final track = BallTrack(trackId: 0);
      track.addPoint(5, 150.0, 250.0);
      track.addPoint(10, 160.0, 240.0);

      expect(track.getCenterAt(5), (150.0, 250.0));
      expect(track.getCenterAt(10), (160.0, 240.0));
    });

    test('getCenterAt returns null for missing frame', () {
      final track = BallTrack(trackId: 0);
      track.addPoint(5, 150.0, 250.0);
      expect(track.getCenterAt(99), isNull);
    });

    test('predictPosition returns null when uninitialized', () {
      final track = BallTrack(trackId: 0);
      expect(track.predictPosition(10), isNull);
    });

    test('predictPosition returns null for same or past frame', () {
      final track = BallTrack(trackId: 0);
      track.addPoint(5, 100.0, 200.0);
      expect(track.predictPosition(5), isNull);
      expect(track.predictPosition(3), isNull);
    });

    test('predictPosition returns null for too-far frame', () {
      final track = BallTrack(trackId: 0);
      track.addPoint(5, 100.0, 200.0);
      expect(track.predictPosition(20), isNull); // 15 frames lost > 10
    });

    test('predictPosition extrapolates velocity', () {
      final track = BallTrack(trackId: 0);
      track.addPoint(0, 100.0, 200.0);
      track.addPoint(1, 105.0, 195.0); // vx=5, vy=-5

      final pred = track.predictPosition(3);
      expect(pred, isNotNull);
      // After 2 more frames from last real: x = 105 + 5*2 = 115, y = 195 + (-5)*2 = 185
      expect(pred!.$1, closeTo(115.0, 0.01));
      expect(pred.$2, closeTo(185.0, 0.01));
    });

    test('addPredictedPoint adds with low confidence', () {
      final track = BallTrack(trackId: 0);
      track.addPoint(0, 100.0, 200.0);
      track.addPredictedPoint(1, 105.0, 195.0);

      expect(track.length, 2);
      expect(track.points[1].predicted, isTrue);
      expect(track.points[1].confidence, 0.3);
    });
  });
}
