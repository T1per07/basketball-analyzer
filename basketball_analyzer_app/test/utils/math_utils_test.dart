import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/utils/math_utils.dart';

void main() {
  group('polyfit', () {
    test('fits a constant line (degree 0)', () {
      final x = [1.0, 2.0, 3.0, 4.0, 5.0];
      final y = [5.0, 5.0, 5.0, 5.0, 5.0];
      final coeffs = polyfit(x, y, 0);
      expect(coeffs.length, 1);
      expect(coeffs[0], closeTo(5.0, 0.01));
    });

    test('fits a linear function (degree 1)', () {
      final x = [0.0, 1.0, 2.0, 3.0, 4.0];
      final y = [1.0, 3.0, 5.0, 7.0, 9.0]; // y = 2x + 1
      final coeffs = polyfit(x, y, 1);
      expect(coeffs.length, 2);
      expect(coeffs[0], closeTo(1.0, 0.01)); // intercept
      expect(coeffs[1], closeTo(2.0, 0.01)); // slope
    });

    test('fits a quadratic function (degree 2)', () {
      final x = [-2.0, -1.0, 0.0, 1.0, 2.0];
      final y = [4.0, 1.0, 0.0, 1.0, 4.0]; // y = x^2
      final coeffs = polyfit(x, y, 2);
      expect(coeffs.length, 3);
      expect(coeffs[0], closeTo(0.0, 0.01)); // c
      expect(coeffs[1], closeTo(0.0, 0.01)); // b
      expect(coeffs[2], closeTo(1.0, 0.01)); // a
    });

    test('throws on insufficient points', () {
      final x = [1.0, 2.0];
      final y = [3.0, 4.0];
      expect(() => polyfit(x, y, 2), throwsException);
    });

    test('fits noisy data approximately', () {
      final rng = Random(42);
      final x = List.generate(20, (i) => i.toDouble());
      // y = 2x + 3 + noise
      final y = x.map((xi) => 2 * xi + 3 + rng.nextDouble() * 0.5 - 0.25).toList();
      final coeffs = polyfit(x, y, 1);
      expect(coeffs[0], closeTo(3.0, 0.5)); // intercept ~3
      expect(coeffs[1], closeTo(2.0, 0.1)); // slope ~2
    });
  });
}
