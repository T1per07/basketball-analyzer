import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'screens/upload_screen.dart';
import 'screens/analysis_screen.dart';
import 'screens/live_screen.dart';
import 'widgets/widgets.dart';

/// 应用主题色
class AppColors {
  static const primary = Color(0xFFFF6B2B);    // 橙色
  static const primaryLight = Color(0xFFFF9800);
  static const secondary = Color(0xFF00E5FF);   // 青色
  static const surface = Color(0xFF1A1A2E);     // 深蓝黑
  static const surfaceLight = Color(0xFF16213E);
  static const background = Color(0xFF0A0A1A);
  static const backgroundDeep = Color(0xFF050510);
  static const text = Color(0xFFEAEAEA);
  static const textDim = Color(0xFF8892B0);
  static const textMuted = Color(0xFF4A5568);
  static const success = Color(0xFF39FF14);
  static const error = Color(0xFFFF3C3C);
  static const glass = Color(0x1A1A2EB3);
  static const glassBorder = Color(0x0FFFFFFF);
}

class BasketballAnalyzerApp extends StatelessWidget {
  const BasketballAnalyzerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
      title: 'BASANS',
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
    return ParticleBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
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
      ),
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
        color: AppColors.surface.withOpacity(0.9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.06),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Logo with glow
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.sports_basketball,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const GradientText(
            'BASANS',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 3,
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
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withOpacity(0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: isSelected
                        ? Border.all(
                            color: AppColors.primary.withOpacity(0.5),
                            width: 1)
                        : null,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
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
                      const SizedBox(width: 6),
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
                          letterSpacing: 1,
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
        color: AppColors.surface.withOpacity(0.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.06),
            width: 1,
          ),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textDim,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.normal,
          fontSize: 11,
        ),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.upload_file),
            activeIcon: Icon(Icons.upload_file, size: 28),
            label: 'Upload',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            activeIcon: Icon(Icons.bar_chart, size: 28),
            label: 'Stats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.videocam),
            activeIcon: Icon(Icons.videocam, size: 28),
            label: 'Live',
          ),
        ],
      ),
    );
  }
}
