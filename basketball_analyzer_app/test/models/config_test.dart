import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/models/config.dart';

void main() {
  group('CourtDimensions — FIBA standard values', () {
    test('court length is 28.0m', () {
      expect(CourtDimensions.length, 28.0);
    });

    test('court width is 15.0m', () {
      expect(CourtDimensions.width, 15.0);
    });

    test('three-point line is 6.75m from basket center', () {
      expect(CourtDimensions.threePointLine, 6.75);
    });

    test('free-throw line is 5.8m from backboard', () {
      expect(CourtDimensions.freeThrowLine, 5.8);
    });

    test('rim height is 3.05m', () {
      expect(CourtDimensions.rimHeight, 3.05);
    });

    test('rim diameter is 0.45m', () {
      expect(CourtDimensions.rimDiameter, 0.45);
    });

    test('backboard width is 1.8m', () {
      expect(CourtDimensions.backboardWidth, 1.8);
    });

    test('restricted area radius is 1.25m', () {
      expect(CourtDimensions.restrictedArea, 1.25);
    });
  });

  group('BallProperties', () {
    test('realDiameter is 0.241m (size 7 basketball)', () {
      expect(BallProperties.realDiameter, 0.241);
    });

    test('realCircumference is 0.756m', () {
      expect(BallProperties.realCircumference, 0.756);
    });

    test('circumference is consistent with diameter (C = pi * d)', () {
      final expectedCircumference = pi * BallProperties.realDiameter;
      expect(BallProperties.realCircumference,
          closeTo(expectedCircumference, 0.002));
    });
  });

  group('ShotType.fromValue roundtrip', () {
    test('three_point roundtrips correctly', () {
      expect(ShotType.fromValue('three_point'), ShotType.threePoint);
      expect(ShotType.threePoint.value, 'three_point');
    });

    test('mid_range roundtrips correctly', () {
      expect(ShotType.fromValue('mid_range'), ShotType.midRange);
      expect(ShotType.midRange.value, 'mid_range');
    });

    test('layup roundtrips correctly', () {
      expect(ShotType.fromValue('layup'), ShotType.layup);
      expect(ShotType.layup.value, 'layup');
    });

    test('dunk roundtrips correctly', () {
      expect(ShotType.fromValue('dunk'), ShotType.dunk);
      expect(ShotType.dunk.value, 'dunk');
    });

    test('free_throw roundtrips correctly', () {
      expect(ShotType.fromValue('free_throw'), ShotType.freeThrow);
      expect(ShotType.freeThrow.value, 'free_throw');
    });

    test('unknown value falls back to midRange', () {
      expect(ShotType.fromValue('unknown_type'), ShotType.midRange);
    });
  });

  group('AppConfig — default config singletons', () {
    test('detection config has reasonable defaults', () {
      expect(AppConfig.detection.ballConfidenceThreshold, 0.45);
      expect(AppConfig.detection.maxBallsPerFrame, 3);
    });

    test('trajectory config layup threshold < mid-range threshold', () {
      expect(AppConfig.trajectory.layupMaxDistance,
          lessThan(AppConfig.trajectory.midRangeMaxDistance));
    });

    test('trajectory config mid-range threshold = three-point minimum', () {
      expect(AppConfig.trajectory.midRangeMaxDistance,
          AppConfig.trajectory.threePointMinDistance);
    });

    test('shot detection R-squared threshold is reasonable', () {
      expect(AppConfig.shot.trajectoryRSquaredThreshold, greaterThan(0));
      expect(AppConfig.shot.trajectoryRSquaredThreshold, lessThan(1));
    });
  });
}
