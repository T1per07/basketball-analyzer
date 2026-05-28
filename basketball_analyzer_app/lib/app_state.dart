import 'package:flutter/foundation.dart';
import 'models/models.dart';

/// 全局应用状态 — 通过 Provider 在页面间共享分析结果
class AppState extends ChangeNotifier {
  AnalysisResult? _result;
  bool _isAnalyzing = false;
  double _progress = 0.0;
  String? _error;

  AnalysisResult? get result => _result;
  bool get isAnalyzing => _isAnalyzing;
  double get progress => _progress;
  String? get error => _error;

  void setAnalyzing(bool value) {
    _isAnalyzing = value;
    if (value) {
      _error = null;
    }
    notifyListeners();
  }

  void setProgress(double value) {
    _progress = value;
    notifyListeners();
  }

  void setResult(AnalysisResult result) {
    _result = result;
    _isAnalyzing = false;
    _progress = 1.0;
    _error = null;
    notifyListeners();
  }

  void setError(String error) {
    _error = error;
    _isAnalyzing = false;
    notifyListeners();
  }

  void clear() {
    _result = null;
    _isAnalyzing = false;
    _progress = 0.0;
    _error = null;
    notifyListeners();
  }
}
