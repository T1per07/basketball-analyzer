import 'dart:math';

/// 多项式拟合（带部分主元高斯消元）
/// 从 x/y 数据点拟合 degree 阶多项式，返回系数列表 [c0, c1, ..., cN]
/// 使得 y ≈ c0 + c1*x + c2*x² + ... + cN*x^N
List<double> polyfit(List<double> x, List<double> y, int degree) {
  final n = x.length;
  if (n < degree + 1) throw Exception('Not enough points');

  final cols = degree + 1;
  final ata = List.generate(cols, (_) => List.filled(cols, 0.0));
  final aty = List.filled(cols, 0.0);

  for (int i = 0; i < n; i++) {
    for (int j = 0; j < cols; j++) {
      for (int k = 0; k < cols; k++) {
        ata[j][k] += pow(x[i], j + k).toDouble();
      }
      aty[j] += pow(x[i], j).toDouble() * y[i];
    }
  }

  for (int i = 0; i < cols; i++) {
    int maxRow = i;
    for (int k = i + 1; k < cols; k++) {
      if (ata[k][i].abs() > ata[maxRow][i].abs()) maxRow = k;
    }
    final tmp = ata[i];
    ata[i] = ata[maxRow];
    ata[maxRow] = tmp;
    final tmpY = aty[i];
    aty[i] = aty[maxRow];
    aty[maxRow] = tmpY;

    if (ata[i][i].abs() < 1e-12) throw Exception('Singular matrix');

    for (int k = i + 1; k < cols; k++) {
      final factor = ata[k][i] / ata[i][i];
      for (int j = i; j < cols; j++) {
        ata[k][j] -= factor * ata[i][j];
      }
      aty[k] -= factor * aty[i];
    }
  }

  final result = List.filled(cols, 0.0);
  for (int i = cols - 1; i >= 0; i--) {
    result[i] = aty[i];
    for (int j = i + 1; j < cols; j++) {
      result[i] -= ata[i][j] * result[j];
    }
    result[i] /= ata[i][i];
  }

  return result;
}
