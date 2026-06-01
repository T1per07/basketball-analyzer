import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// ONNX 检测器 — 使用 best.onnx 模型检测篮球和篮筐
/// 模型输出: [1, 6, N] — [cx, cy, w, h, conf, class_id]
/// class 0 = Basketball, class 1 = Basketball Hoop
class OnnxDetector {
  OrtSession? _session;
  bool _initialized = false;

  // 模型输入尺寸（自动检测）
  int _inputSize = 640;

  // 预分配缓冲区
  late Float32List _inputBuffer;

  // 检测阈值
  final double confThreshold;
  final double nmsThreshold;

  // 类别常量
  static const int classBasketball = 0;
  static const int classHoop = 1;

  OnnxDetector({
    this.confThreshold = 0.45,
    this.nmsThreshold = 0.45,
    int inputSize = 640,
  })  : _inputSize = inputSize,
        _inputBuffer = Float32List(3 * inputSize * inputSize);

  int get inputSize => _inputSize;

  bool get isInitialized => _initialized;

  /// 初始化模型（从 assets 或文件路径）
  Future<void> init({String? modelPath}) async {
    if (_initialized) return;

    try {
      final ort = OnnxRuntime();
      final options = OrtSessionOptions(
        intraOpNumThreads: 4,
        interOpNumThreads: 1,
      );

      if (modelPath != null) {
        _session = await ort.createSession(modelPath, options: options);
      } else {
        _session =
            await ort.createSessionFromAsset('assets/models/best.onnx',
                options: options);
      }

      // 获取输入信息
      final inputInfo = await _session!.getInputInfo();
      if (inputInfo.isNotEmpty) {
        final shape = inputInfo.first['shape'] as List<dynamic>?;
        if (shape != null && shape.length >= 4) {
          final h = shape[shape.length - 2];
          final w = shape[shape.length - 1];
          if (h is int && h > 0) _inputSize = h;
          if (w is int && w > 0) _inputSize = w;
        }
      }

      _inputBuffer = Float32List(1 * 3 * _inputSize * _inputSize);
      _initialized = true;
    } catch (e) {
      _initialized = false;
      rethrow;
    }
  }

  /// 预处理：BGR 帧 → 归一化 CHW 张量
  Float32List preprocess(Uint8List frameBgr, int width, int height) {
    final buf = _inputBuffer;
    final size = _inputSize;

    // 双线性插值 resize + BGR→RGB + HWC→CHW + /255
    final xRatio = width / size;
    final yRatio = height / size;

    for (int y = 0; y < size; y++) {
      final srcY = (y * yRatio).clamp(0, height - 1).toInt();
      for (int x = 0; x < size; x++) {
        final srcX = (x * xRatio).clamp(0, width - 1).toInt();
        final srcIdx = (srcY * width + srcX) * 3;

        // BGR → RGB，归一化到 [0, 1]
        final r = frameBgr[srcIdx + 2] / 255.0;
        final g = frameBgr[srcIdx + 1] / 255.0;
        final b = frameBgr[srcIdx] / 255.0;

        // CHW 布局
        final pixelIdx = y * size + x;
        buf[pixelIdx] = r; // R channel
        buf[size * size + pixelIdx] = g; // G channel
        buf[2 * size * size + pixelIdx] = b; // B channel
      }
    }

    return buf;
  }

  /// 运行检测，返回 (boxes, confidences, classIds)
  /// boxes: List of (x1, y1, x2, y2) in original image coordinates
  /// confidences: List of confidence scores
  /// classIds: List of class IDs (0=basketball, 1=hoop)
  Future<(List<(double, double, double, double)>, List<double>,
      List<int>)> detect(
    Uint8List frameBgr,
    int width,
    int height,
  ) async {
    if (!_initialized || _session == null) {
      return (<(double, double, double, double)>[], <double>[], <int>[]);
    }

    try {
      // 预处理
      final inputData = preprocess(frameBgr, width, height);

      // 创建输入 tensor
      final inputOrt = await OrtValue.fromList(
        inputData,
        [1, 3, _inputSize, _inputSize],
      );

      // 获取输入名称
      final inputName = _session!.inputNames.first;
      final inputs = {inputName: inputOrt};

      // 推理
      final outputs = await _session!.run(inputs);

      // 释放输入
      await inputOrt.dispose();

      // 获取输出
      final outputName = _session!.outputNames.first;
      final outputOrt = outputs[outputName];
      if (outputOrt == null) {
        return (<(double, double, double, double)>[], <double>[], <int>[]);
      }

      final outputData = await outputOrt.asFlattenedList();
      final outputShape = outputOrt.shape;

      await outputOrt.dispose();

      // 后处理
      return postprocess(outputData, outputShape, width, height);
    } catch (_) {
      return (<(double, double, double, double)>[], <double>[], <int>[]);
    }
  }

  /// 后处理：解析模型输出，NMS 过滤
  (List<(double, double, double, double)>, List<double>, List<int>) postprocess(
    List<dynamic> outputData,
    List<int> outputShape,
    int origWidth,
    int origHeight,
  ) {
    // output shape: [1, 6, N]
    if (outputShape.length < 3) {
      return (<(double, double, double, double)>[], <double>[], <int>[]);
    }

    final numDetections = outputShape[2];
    final numCols = outputShape[1]; // should be 6

    if (numCols < 6 || numDetections == 0) {
      return (<(double, double, double, double)>[], <double>[], <int>[]);
    }

    // 解析检测结果
    final boxes = <(double, double, double, double)>[];
    final confidences = <double>[];
    final classIds = <int>[];

    final scaleX = origWidth / _inputSize;
    final scaleY = origHeight / _inputSize;

    for (int i = 0; i < numDetections; i++) {
      // 数据布局: [cx, cy, w, h, conf, class_id] 按列优先
      // outputData 是 1D: index = col * numDetections + i
      final cx = (outputData[0 * numDetections + i] as num).toDouble();
      final cy = (outputData[1 * numDetections + i] as num).toDouble();
      final w = (outputData[2 * numDetections + i] as num).toDouble();
      final h = (outputData[3 * numDetections + i] as num).toDouble();
      final conf = (outputData[4 * numDetections + i] as num).toDouble();
      final classId = (outputData[5 * numDetections + i] as num).toInt();

      if (conf < confThreshold) continue;

      // xywh → xyxy，缩放回原始尺寸
      final x1 = (cx - w / 2) * scaleX;
      final y1 = (cy - h / 2) * scaleY;
      final x2 = (cx + w / 2) * scaleX;
      final y2 = (cy + h / 2) * scaleY;

      boxes.add((x1, y1, x2, y2));
      confidences.add(conf);
      classIds.add(classId);
    }

    if (boxes.isEmpty) {
      return (<(double, double, double, double)>[], <double>[], <int>[]);
    }

    // NMS
    return _nms(boxes, confidences, classIds);
  }

  /// 非极大值抑制
  (List<(double, double, double, double)>, List<double>, List<int>) _nms(
    List<(double, double, double, double)> boxes,
    List<double> confidences,
    List<int> classIds,
  ) {
    // 按置信度降序排序
    final indices = List.generate(boxes.length, (i) => i);
    indices.sort((a, b) => confidences[b].compareTo(confidences[a]));

    final keep = <int>[];
    final suppressed = List.filled(boxes.length, false);

    for (int i = 0; i < indices.length; i++) {
      final idx = indices[i];
      if (suppressed[idx]) continue;

      keep.add(idx);

      // 抑制重叠的同类框
      for (int j = i + 1; j < indices.length; j++) {
        final jdx = indices[j];
        if (suppressed[jdx]) continue;
        if (classIds[idx] != classIds[jdx]) continue;

        final iou = computeIoU(boxes[idx], boxes[jdx]);
        if (iou > nmsThreshold) {
          suppressed[jdx] = true;
        }
      }
    }

    return (
      keep.map((i) => boxes[i]).toList(),
      keep.map((i) => confidences[i]).toList(),
      keep.map((i) => classIds[i]).toList(),
    );
  }

  /// 计算 IoU
  double computeIoU(
    (double, double, double, double) a,
    (double, double, double, double) b,
  ) {
    final x1 = max(a.$1, b.$1);
    final y1 = max(a.$2, b.$2);
    final x2 = min(a.$3, b.$3);
    final y2 = min(a.$4, b.$4);

    final inter = max(0, x2 - x1) * max(0, y2 - y1);
    final areaA = (a.$3 - a.$1) * (a.$4 - a.$2);
    final areaB = (b.$3 - b.$1) * (b.$4 - b.$2);
    final union = areaA + areaB - inter;

    return union > 0 ? inter / union : 0;
  }

  void dispose() {
    _session?.close();
    _session = null;
    _initialized = false;
  }
}
