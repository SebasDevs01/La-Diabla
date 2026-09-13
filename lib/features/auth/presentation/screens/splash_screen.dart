import 'package:firebase_auth/firebase_auth.dart';
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

      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      final savedId = prefs.getString('saved_user_id');
      final isDelivery = prefs.getBool('is_delivery_mode') ?? false;
      final savedRole = prefs.getString('saved_user_role');
      final savedEmail = prefs.getString('saved_user_email') ?? '';

      final authState = ref.read(authNotifierProvider);
      final repo = ref.read(authRepositoryProvider);
      final currentUser = repo.currentUser;
      final fbUser = FirebaseAuth.instance.currentUser;

      final isGuest = prefs.getBool('is_guest_user') ?? false;
      final isGuestId = savedId != null && (savedId.startsWith('guest_') || savedId == 'guest');
      final isGuestEmail = savedEmail.contains('@invitado.ladiabla.app') || savedEmail.contains('guest');

      // Si SharedPreferences o el estado contiene cualquier rastro de usuario invitado,
      // DEBE ser purgado de inmediato. Los invitados nunca tienen sesión persistente al abrir la app.
      if (isGuest || isGuestId || isGuestEmail) {
        await prefs.clear();
        if (fbUser != null) {
          try {
            await FirebaseAuth.instance.signOut();
          } catch (_) {}
        }
        if (!mounted) return;
        context.go('/auth');
        return;
      }

      // Un usuario anónimo de Firebase NO cuenta como sesión válida.
      final isRealFirebaseUser = fbUser != null && !fbUser.isAnonymous;

      // Sesión válida ÚNICAMENTE si hay un usuario real autenticado guardado
      final hasSession = isRealFirebaseUser &&
          isLoggedIn &&
          savedId != null &&
          savedId.isNotEmpty;

      // Si no hay sesión válida pero hay usuario huérfano anónimo, lo cerramos
      if (!hasSession && fbUser != null) {
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
      }

      if (!mounted) return;

      if (hasSession) {
        final isAdmin = savedEmail == 'admin@ladiabla.app' ||
            savedEmail == 'appladiabla@gmail.com' ||
            savedRole == 'admin' ||
            (authState.user?.isAdmin ?? false) ||
            (currentUser?.isAdmin ?? false);

        final isDriver = isDelivery ||
            savedRole == 'driver' ||
            savedEmail == 'repartidor@ladiabla.app' ||
            (authState.user?.isDriver ?? false) ||
            (currentUser?.isDriver ?? false);

        if (isAdmin) {
          context.go('/admin');
        } else if (isDriver) {
          context.go('/driver');
        } else {
          context.go('/home');
        }
      } else {
        // Sin sesión activa → pantalla de login
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
