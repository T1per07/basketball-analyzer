import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/models/trajectory_params.dart';

void main() {
  group('TrajectoryParams', () {
    test('stores all required fields', () {
      const params = TrajectoryParams(
        apexX: 320.0,
        apexY: 80.0,
        releaseAngle: 48.5,
        entryAngle: 42.0,
        apexHeight: 80.0,
        fitRSquared: 0.95,
        parabolaA: 0.005,
        parabolaB: -3.2,
        parabolaC: 600.0,
        estimatedDistance: 5.2,
        flightTime: 0.85,
        shotSpeed: 8.5,
        arcHeight: 1.2,
      );

      expect(params.apexX, 320.0);
      expect(params.apexY, 80.0);
      expect(params.releaseAngle, 48.5);
      expect(params.entryAngle, 42.0);
      expect(params.fitRSquared, 0.95);
      expect(params.parabolaA, 0.005);
      expect(params.parabolaB, -3.2);
      expect(params.parabolaC, 600.0);
      expect(params.estimatedDistance, 5.2);
      expect(params.flightTime, 0.85);
      expect(params.shotSpeed, 8.5);
      expect(params.arcHeight, 1.2);
    });

    test('kinematic fields default to 0', () {
      const params = TrajectoryParams(
        apexX: 0, apexY: 0, releaseAngle: 0, entryAngle: 0,
        apexHeight: 0, fitRSquared: 0, parabolaA: 0, parabolaB: 0,
        parabolaC: 0, estimatedDistance: 0,
      );
      expect(params.flightTime, 0.0);
      expect(params.shotSpeed, 0.0);
      expect(params.arcHeight, 0.0);
    });
  });
}
