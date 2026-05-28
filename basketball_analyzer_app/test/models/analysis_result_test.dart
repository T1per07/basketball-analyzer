import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/models/models.dart';

void main() {
  group('AnalysisResult — getStatsByType()', () {
    test('returns correct groupings for mixed shot types', () {
      final result = AnalysisResult(
        totalFrames: 200,
        fps: 30.0,
        shots: [
          const ShotEvent(
            shotId: 1, frameStart: 0, frameEnd: 10,
            shotType: 'three_point', made: true, distance: 6.0,
            confidence: 0.8,
          ),
          const ShotEvent(
            shotId: 2, frameStart: 20, frameEnd: 30,
            shotType: 'three_point', made: false, distance: 5.5,
            confidence: 0.7,
          ),
          const ShotEvent(
            shotId: 3, frameStart: 40, frameEnd: 50,
            shotType: 'mid_range', made: true, distance: 3.0,
            confidence: 0.9,
          ),
          const ShotEvent(
            shotId: 4, frameStart: 60, frameEnd: 70,
            shotType: 'layup', made: true, distance: 1.0,
            confidence: 0.85,
          ),
          const ShotEvent(
            shotId: 5, frameStart: 80, frameEnd: 90,
            shotType: 'layup', made: false, distance: 1.5,
            confidence: 0.6,
          ),
        ],
      );

      final byType = result.getStatsByType();

      // three_point: 2 attempts, 1 made, 50%
      expect(byType['three_point']!['attempts'], 2);
      expect(byType['three_point']!['made'], 1);
      expect(byType['three_point']!['percentage'], closeTo(0.5, 0.01));
      expect(byType['three_point']!['avg_distance'], closeTo(5.75, 0.01));

      // layup: 2 attempts, 1 made, 50%
      expect(byType['layup']!['attempts'], 2);
      expect(byType['layup']!['made'], 1);
      expect(byType['layup']!['percentage'], closeTo(0.5, 0.01));
      expect(byType['layup']!['avg_distance'], closeTo(1.25, 0.01));

      // mid_range: 1 attempt, 1 made, 100%
      expect(byType['mid_range']!['attempts'], 1);
      expect(byType['mid_range']!['made'], 1);
      expect(byType['mid_range']!['percentage'], 1.0);

      // dunk and free_throw have no shots — should not appear
      expect(byType.containsKey('dunk'), isFalse);
      expect(byType.containsKey('free_throw'), isFalse);
    });

    test('returns empty map when no shots', () {
      final result = AnalysisResult(
        totalFrames: 100,
        fps: 30.0,
        shots: const [],
      );
      expect(result.getStatsByType(), isEmpty);
    });

    test('single shot type yields one entry', () {
      final result = AnalysisResult(
        totalFrames: 100,
        fps: 30.0,
        shots: [
          const ShotEvent(
            shotId: 1, frameStart: 0, frameEnd: 10,
            shotType: 'layup', made: true, distance: 1.2,
            confidence: 0.9,
          ),
        ],
      );
      final byType = result.getStatsByType();
      expect(byType.length, 1);
      expect(byType.containsKey('layup'), isTrue);
      expect(byType['layup']!['percentage'], 1.0);
    });
  });

  group('AnalysisResult — averageDistance', () {
    test('excludes zero-distance shots from average', () {
      final result = AnalysisResult(
        totalFrames: 100,
        fps: 30.0,
        shots: [
          const ShotEvent(
            shotId: 1, frameStart: 0, frameEnd: 10,
            shotType: 'three_point', made: true, distance: 6.0,
            confidence: 0.8,
          ),
          const ShotEvent(
            shotId: 2, frameStart: 20, frameEnd: 30,
            shotType: 'layup', made: true, distance: 0.0, // excluded
            confidence: 0.5,
          ),
          const ShotEvent(
            shotId: 3, frameStart: 40, frameEnd: 50,
            shotType: 'mid_range', made: false, distance: 4.0,
            confidence: 0.7,
          ),
        ],
      );
      // Only shots with distance > 0 contribute: (6.0 + 4.0) / 2 = 5.0
      expect(result.averageDistance, closeTo(5.0, 0.01));
    });

    test('returns 0.0 when all distances are zero', () {
      final result = AnalysisResult(
        totalFrames: 100,
        fps: 30.0,
        shots: [
          const ShotEvent(
            shotId: 1, frameStart: 0, frameEnd: 10,
            shotType: 'layup', made: true, distance: 0.0,
            confidence: 0.5,
          ),
        ],
      );
      expect(result.averageDistance, 0.0);
    });

    test('returns 0.0 when no shots', () {
      final result = AnalysisResult(
        totalFrames: 100,
        fps: 30.0,
        shots: const [],
      );
      expect(result.averageDistance, 0.0);
    });
  });

  group('AnalysisResult — overallPercentage', () {
    test('returns 0.0 with zero shots', () {
      final result = AnalysisResult(
        totalFrames: 100,
        fps: 30.0,
        shots: const [],
      );
      expect(result.overallPercentage, 0.0);
    });

    test('returns 1.0 when all shots made', () {
      final result = AnalysisResult(
        totalFrames: 100,
        fps: 30.0,
        shots: [
          const ShotEvent(
            shotId: 1, frameStart: 0, frameEnd: 10,
            shotType: 'layup', made: true, distance: 1.0,
            confidence: 0.9,
          ),
          const ShotEvent(
            shotId: 2, frameStart: 20, frameEnd: 30,
            shotType: 'mid_range', made: true, distance: 3.0,
            confidence: 0.8,
          ),
        ],
      );
      expect(result.overallPercentage, 1.0);
    });

    test('returns 0.0 when no shots made', () {
      final result = AnalysisResult(
        totalFrames: 100,
        fps: 30.0,
        shots: [
          const ShotEvent(
            shotId: 1, frameStart: 0, frameEnd: 10,
            shotType: 'layup', made: false, distance: 1.0,
            confidence: 0.5,
          ),
        ],
      );
      expect(result.overallPercentage, 0.0);
    });
  });

  group('AnalysisResult — totalShots and madeShots', () {
    test('counts correctly', () {
      final result = AnalysisResult(
        totalFrames: 100,
        fps: 30.0,
        shots: [
          const ShotEvent(
            shotId: 1, frameStart: 0, frameEnd: 10,
            shotType: 'layup', made: true, distance: 1.0,
            confidence: 0.9,
          ),
          const ShotEvent(
            shotId: 2, frameStart: 20, frameEnd: 30,
            shotType: 'three_point', made: false, distance: 6.0,
            confidence: 0.7,
          ),
          const ShotEvent(
            shotId: 3, frameStart: 40, frameEnd: 50,
            shotType: 'mid_range', made: true, distance: 3.5,
            confidence: 0.8,
          ),
        ],
      );
      expect(result.totalShots, 3);
      expect(result.madeShots, 2);
    });
  });
}
