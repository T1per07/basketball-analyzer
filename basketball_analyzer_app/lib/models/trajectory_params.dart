/// 轨迹参数
/// 对应 Python models/trajectory.py TrajectoryParams
class TrajectoryParams {
  final double apexX;
  final double apexY;
  final double releaseAngle;
  final double entryAngle;
  final double apexHeight;
  final double fitRSquared;
  final double parabolaA;
  final double parabolaB;
  final double parabolaC;
  final double estimatedDistance;
  final double flightTime;
  final double shotSpeed;
  final double arcHeight;

  const TrajectoryParams({
    required this.apexX,
    required this.apexY,
    required this.releaseAngle,
    required this.entryAngle,
    required this.apexHeight,
    required this.fitRSquared,
    required this.parabolaA,
    required this.parabolaB,
    required this.parabolaC,
    required this.estimatedDistance,
    this.flightTime = 0.0,
    this.shotSpeed = 0.0,
    this.arcHeight = 0.0,
  });
}
