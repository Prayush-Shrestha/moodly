import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/logo_mark.dart';
import '../shell/app_shell.dart';

/// Launch screen: brand lockup on a soft lavender gradient, shown while the
/// local database opens. Deliberately brief so it never delays the app.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.initialization,
    this.minDisplay = const Duration(milliseconds: 650),
  });

  /// Completes when the app is ready (database opened, etc.).
  final Future<void> initialization;

  /// Minimum time the splash stays visible.
  final Duration minDisplay;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateWhenReady();
  }

  Future<void> _navigateWhenReady() async {
    await Future.wait<void>([
      widget.initialization,
      Future<void>.delayed(widget.minDisplay),
    ]);
    if (!mounted) return;
    final navigator = Navigator.of(context);
    navigator.pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const AppShell(),
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.92, end: 1),
                    duration: const Duration(milliseconds: 520),
                    curve: Curves.easeOutBack,
                    builder: (context, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: const BrandLockup(
                      markSize: 92,
                      textColor: Colors.white,
                      taglineColor: Color(0xFFD9CFFA),
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 36),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.mint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
