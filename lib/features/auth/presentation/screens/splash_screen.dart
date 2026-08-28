// lib/features/auth/presentation/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/theme/app_colors.dart';
import '../../providers/auth_notifier.dart';
import '../../providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnimation = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 1400), () async {
      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      final isDelivery = prefs.getBool('is_delivery_mode') ?? false;

      // Firebase Auth es la fuente de verdad para la sesión.
      // SharedPreferences sólo se usa para el rol/modo (driver, admin).
      final authState = ref.read(authNotifierProvider);
      final repo = ref.read(authRepositoryProvider);
      final currentUser = repo.currentUser;

      // Considerar sesión activa solo si Firebase tiene usuario o AuthNotifier lo tiene listo
      final effectiveUser = authState.user ?? currentUser;
      final hasSession = effectiveUser != null;

      if (!mounted) return;

      if (hasSession) {
        if (effectiveUser.isAdmin) {
          context.go('/admin');
        } else if (isDelivery || effectiveUser.isDriver) {
          context.go('/driver');
        } else {
          context.go('/home');
        }
      } else {
        // Sin sesión → pantalla de login
        context.go('/auth');
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? AppColors.backgroundDark : Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  width: 220,
                  height: 220,
                  fit: BoxFit.contain,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
