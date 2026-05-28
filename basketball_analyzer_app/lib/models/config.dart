/// 项目配置 — 所有魔法数字、阈值、倍率集中管理
/// 对应 Python config/settings.py
library;

enum ShotType {
  threePoint('three_point'),
  midRange('mid_range'),
  layup('layup'),
  dunk('dunk'),
  freeThrow('free_throw');

  final String value;
  const ShotType(this.value);

  static ShotType fromValue(String v) {
    return ShotType.values.firstWhere(
      (t) => t.value == v,
      orElse: () => ShotType.midRange,
    );
  }
}

/// FIBA 标准球场尺寸（米）
abstract class CourtDimensions {
  static const double length = 28.0;
  static const double width = 15.0;
  static const double threePointLine = 6.75;
  static const double freeThrowLine = 5.8;
  static const double rimHeight = 3.05;
  static const double rimDiameter = 0.45;
  static const double backboardWidth = 1.8;
  static const double restrictedArea = 1.25;
}

/// 篮球物理属性
abstract class BallProperties {
  static const double realDiameter = 0.241;
  static const double realCircumference = 0.756;
}

/// 检测配置
class DetectionConfig {
  final double ballConfidenceThreshold;
  final double hoopConfidenceThreshold;
  final double playerConfidenceThreshold;
  final int inputWidth;
  final int yoloInterval;
  final int colorDetectTargetWidth;
  final int maxBallsPerFrame;
  final double nmsThreshold;
  final double motionThreshold;

  const DetectionConfig({
    this.ballConfidenceThreshold = 0.1,
    this.hoopConfidenceThreshold = 0.2,
    this.playerConfidenceThreshold = 0.3,
    this.inputWidth = 416,
    this.yoloInterval = 10,
    this.colorDetectTargetWidth = 320,
    this.maxBallsPerFrame = 3,
    this.nmsThreshold = 0.3,
    this.motionThreshold = 20.0,
  });
}

/// 跟踪配置
class TrackingConfig {
  final double trackThresh;
  final int trackBuffer;
  final double matchThresh;
  final int minHits;
  final int kalmanMaxLostFrames;

  const TrackingConfig({
    this.trackThresh = 0.15,
    this.trackBuffer = 60,
    this.matchThresh = 0.7,
    this.minHits = 2,
    this.kalmanMaxLostFrames = 10,
  });
}

/// 投篮检测配置
class ShotDetectionConfig {
  final int minShotFrames;
  final int maxShotFrames;
  final int shotCooldownFrames;
  final double trajectoryRSquaredThreshold;
  final double cooldownFpsRatio;
  final int cooldownMinFrames;
  final double confidenceHigh;
  final double confidenceLow;

  const ShotDetectionConfig({
    this.minShotFrames = 2,
    this.maxShotFrames = 120,
    this.shotCooldownFrames = 10,
    this.trajectoryRSquaredThreshold = 0.20,
    this.cooldownFpsRatio = 0.3,
    this.cooldownMinFrames = 5,
    this.confidenceHigh = 0.45,
    this.confidenceLow = 0.25,
  });
}

/// 视频处理配置
class VideoProcessingConfig {
  final int targetProcessFps;
  final double outputFps;
  final int flashFrames;
  final double upZoneWidthMult;
  final double upZoneHeightMult;
  final double upZoneYOffset;
  final double downZoneWidthMult;
  final double downZoneHeightMult;
  final double downZoneYOffset;

  const VideoProcessingConfig({
    this.targetProcessFps = 30,
    this.outputFps = 60.0,
    this.flashFrames = 25,
    this.upZoneWidthMult = 3.5,
    this.upZoneHeightMult = 2.5,
    this.upZoneYOffset = 0.3,
    this.downZoneWidthMult = 2.5,
    this.downZoneHeightMult = 3.0,
    this.downZoneYOffset = 0.2,
  });
}

/// 轨迹分析配置
class TrajectoryConfig {
  final int defaultFrameWidth;
  final double cameraFovDegrees;
  final int savgolWindow;
  final int savgolPolyorder;
  final double pixelToMeterFallback;
  final double ballDiameterReal;
  final double layupMaxDistance;
  final double midRangeMaxDistance;
  final double threePointMinDistance;
  final double threePointMaxDistance;

  const TrajectoryConfig({
    this.defaultFrameWidth = 852,
    this.cameraFovDegrees = 30.0,
    this.savgolWindow = 9,
    this.savgolPolyorder = 2,
    this.pixelToMeterFallback = 0.01,
    this.ballDiameterReal = 0.241,
    this.layupMaxDistance = 1.5,
    this.midRangeMaxDistance = 4.5,
    this.threePointMinDistance = 4.5,
    this.threePointMaxDistance = 6.5,
  });
}

/// 应用全局配置
class AppConfig {
  static const detection = DetectionConfig();
  static const tracking = TrackingConfig();
  static const shot = ShotDetectionConfig();
  static const video = VideoProcessingConfig();
  static const trajectory = TrajectoryConfig();
}
