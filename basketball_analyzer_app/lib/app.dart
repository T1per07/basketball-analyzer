import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'screens/upload_screen.dart';
import 'screens/analysis_screen.dart';
import 'screens/live_screen.dart';

/// 应用主题色
class AppColors {
  static const primary = Color(0xFFFF6B2B);    // 橙色
  static const secondary = Color(0xFF00E5FF);   // 青色
  static const surface = Color(0xFF1A1A2E);     // 深蓝黑
  static const surfaceLight = Color(0xFF16213E);
  static const background = Color(0xFF0F0F23);
  static const text = Color(0xFFEAEAEA);
  static const textDim = Color(0xFF8892B0);
  static const success = Color(0xFF39FF14);
  static const error = Color(0xFFFF3C3C);
}

class BasketballAnalyzerApp extends StatelessWidget {
  const BasketballAnalyzerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
      title: 'Basketball Analyzer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.surface,
        ),
        fontFamily: 'Inter',
        useMaterial3: true,
      ),
      home: const MainNavigation(),
    ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final _screens = const [
    UploadScreen(),
    AnalysisScreen(),
    LiveScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 顶部导航栏
          _buildHeader(),
          // 页面内容
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, Color(0xFFFF9800)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.sports_basketball,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Text(
            'SHOT ANALYZER',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.secondary,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          // 页签
          ...List.generate(3, (i) {
            final labels = ['UPLOAD', 'STATS', 'LIVE'];
            final icons = [
              Icons.upload_file,
              Icons.bar_chart,
              Icons.videocam,
            ];
            final isSelected = _currentIndex == i;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => setState(() => _currentIndex = i),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withAlpha(40)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: isSelected
                        ? Border.all(color: AppColors.primary, width: 1)
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icons[i],
                          size: 16,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textDim),
                      const SizedBox(width: 4),
                      Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textDim,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.upload_file),
            label: 'Upload',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Stats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.videocam),
            label: 'Live',
          ),
        ],
      ),
    );
  }
}
