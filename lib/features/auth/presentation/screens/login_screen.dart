// lib/features/auth/presentation/screens/login_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_responsive.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/diabla_text_field.dart';
import '../../providers/auth_notifier.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // ─── Modo de acceso: usuario o repartidor ─────────────────────────────────
  bool _isDeliveryMode = false;
  // Iniciar Sesión Email Controllers
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _emailFocusNode = FocusNode();

  // Registrarse Email Controllers
  final _regNameController = TextEditingController();
  final _regEmailController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regConfirmPasswordController = TextEditingController();

  // Invitado Controllers
  final _guestNameController = TextEditingController();
  final _guestPhoneController = TextEditingController();
  final _guestAddressController = TextEditingController();
  bool _hasNavigated = false;

  @override
  void dispose() {
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _emailFocusNode.dispose();
    _regNameController.dispose();
    _regEmailController.dispose();
    _regPasswordController.dispose();
    _regConfirmPasswordController.dispose();
    _guestNameController.dispose();
    _guestPhoneController.dispose();
    _guestAddressController.dispose();
    super.dispose();
  }

  Future<void> _navigateAfterLogin([GoRouter? router, bool? isAdmin]) async {
    if (!mounted || _hasNavigated) return;
    _hasNavigated = true;
    final r = router ?? GoRouter.of(context);
    final prefs = await SharedPreferences.getInstance();
    // Use the explicitly set state — avoids timing issues with stream updates
    final user = ref.read(authNotifierProvider).user;
    final admin = isAdmin ?? (user?.isAdmin ?? false);
    if (admin) {
      await prefs.setBool('is_logged_in', true);
      r.go('/admin');
      return;
    }
    await prefs.setBool('is_delivery_mode', _isDeliveryMode);
    if (_isDeliveryMode || (user?.isDriver ?? false)) {
      r.go('/driver');
    } else {
      r.go('/home');
    }
  }

  // ─── GOOGLE AUTH ───────────────────────────────────────────────────────────
  Future<void> _handleGoogleAuth() async {
    _hasNavigated = false;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final notifier = ref.read(authNotifierProvider.notifier);

    final success = await notifier.signInWithGoogle(
      isDeliveryMode: _isDeliveryMode,
    );
    if (!mounted) return;
    if (success) {
      _navigateAfterLogin(router);
    } else {
      final err = ref.read(authNotifierProvider).errorMessage;
      if (err != null &&
          !err.toLowerCase().contains('cancelado') &&
          !err.toLowerCase().contains('cancelled') &&
          !err.toLowerCase().contains('canceled')) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  // ─── DIRECT EMAIL LOGIN & FORGOT PASSWORD ──────────────────────────────────
  Future<void> _handleDirectEmailLogin() async {
    _hasNavigated = false;
    final email = _loginEmailController.text.trim();
    final password = _loginPasswordController.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    if (email.isEmpty || password.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Por favor completa tu correo y contraseña'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final success = await ref.read(authNotifierProvider.notifier).signInWithEmail(
      email,
      password,
      isDeliveryMode: _isDeliveryMode,
    );
    if (!mounted) return;
    if (success) {
      _navigateAfterLogin(router);
    } else {
      final err = ref.read(authNotifierProvider).errorMessage;
      messenger.showSnackBar(
        SnackBar(
          content: Text(err ?? 'Error al iniciar sesión'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _showForgotPasswordDialog() {
    final emailController = TextEditingController(text: _loginEmailController.text);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
        title: Text(
          'Recuperar Contraseña 🔑',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontFamily: AppTypography.displayFamily,
            fontSize: 20,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingresa tu correo para recibir un enlace de restablecimiento:',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontFamily: AppTypography.bodyFamily,
              ),
            ),
            const SizedBox(height: 16),
            DiablaTextField(
              controller: emailController,
              label: 'Correo electrónico',
              keyboardType: TextInputType.emailAddress,
              prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFFDC2626)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              'Cancelar',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Por favor ingresa tu correo')),
                );
                return;
              }
              Navigator.pop(dialogCtx);
              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Correo de restablecimiento enviado a $email ✉️'),
                      backgroundColor: AppColors.secondary,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  // ─── EMAIL AUTH - SIGNUP ───────────────────────────────────────────────────
  Future<void> _handleEmailSignup(BuildContext sheetContext) async {
    final name = _regNameController.text.trim();
    final email = _regEmailController.text.trim();
    final password = _regPasswordController.text.trim();
    final confirm = _regConfirmPasswordController.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    if (name.isEmpty || email.isEmpty || password.isEmpty || confirm.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Por favor completa todos los campos'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (password != confirm) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Las contraseñas no coinciden 🔒'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.pop(sheetContext);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_registered_name', name);

    final success = await ref.read(authNotifierProvider.notifier).signUpWithEmail(
      email,
      password,
      isDeliveryMode: _isDeliveryMode,
    );
    if (!mounted) return;
    if (success) {
      _navigateAfterLogin(router);
    } else {
      final err = ref.read(authNotifierProvider).errorMessage;
      messenger.showSnackBar(
        SnackBar(
          content: Text(err ?? 'Error al registrar cuenta'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ─── GUEST LOGIN ───────────────────────────────────────────────────────────
  Future<void> _handleGuestLogin(BuildContext sheetContext) async {
    final name = _guestNameController.text.trim();
    final phone = _guestPhoneController.text.trim();
    final address = _guestAddressController.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    if (name.isEmpty || phone.isEmpty || address.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Por favor ingresa tu nombre, celular y dirección para tus pedidos'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.pop(sheetContext);

    final success = await ref.read(authNotifierProvider.notifier).signInAsGuest(
          name: name,
          phone: phone,
          address: address,
        );

    if (!mounted) return;
    if (success) {
      _navigateAfterLogin(router);
    } else {
      final err = ref.read(authNotifierProvider).errorMessage;
      messenger.showSnackBar(
        SnackBar(
          content: Text(err ?? 'Error al ingresar como invitado'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }


  // ─── MODAL SHEETS GENERATORS ───────────────────────────────────────────────

  /// Bottom sheet para pedir como Invitado
  void _showGuestBottomSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final redColor = isDark ? const Color(0xFFEF4444) : const Color(0xFFDC2626);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Row(
                children: [
                  Text(
                    'PEDIR COMO INVITADO',
                    style: TextStyle(
                      fontFamily: AppTypography.displayFamily,
                      fontSize: 24,
                      color: redColor,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('🛵', style: TextStyle(fontSize: 22)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Sin contraseña ni registros. Solo tus datos para llevarte tu comida caliente.',
                style: TextStyle(
                  fontFamily: AppTypography.bodyFamily,
                  fontSize: 12.5,
                  color: isDark ? AppColors.textMutedDark : Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 18),
              DiablaTextField(
                key: const ValueKey('guest_name_field'),
                controller: _guestNameController,
                label: 'Tu Nombre Completo',
                keyboardType: TextInputType.name,
                textInputAction: TextInputAction.next,
                prefixIcon: Icon(Icons.person_outline_rounded, color: redColor),
              ),
              const SizedBox(height: 12),
              DiablaTextField(
                key: const ValueKey('guest_phone_field'),
                controller: _guestPhoneController,
                label: 'Número de Celular (Para el repartidor)',
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                prefixIcon: Icon(Icons.phone_iphone_rounded, color: redColor),
              ),
              const SizedBox(height: 12),
              DiablaTextField(
                key: const ValueKey('guest_address_field'),
                controller: _guestAddressController,
                label: 'Dirección de Entrega (Ej: Calle 45 #23-67)',
                keyboardType: TextInputType.streetAddress,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _handleGuestLogin(sheetCtx),
                prefixIcon: Icon(Icons.location_on_outlined, color: redColor),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  onPressed: () => _handleGuestLogin(sheetCtx),
                  child: const Text(
                    '¡ENTRAR Y PEDIR YA!',
                    style: TextStyle(
                      fontFamily: AppTypography.displayFamily,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Bottom sheet de opciones alternativas de inicio
  void _showLoginOptionsSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final redColor = isDark ? const Color(0xFFEF4444) : const Color(0xFFDC2626);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Text(
                'MÁS OPCIONES DE ACCESO',
                style: TextStyle(
                  fontFamily: AppTypography.displayFamily,
                  fontSize: 24,
                  color: redColor,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Elige cómo deseas realizar tus pedidos',
                style: TextStyle(
                  fontFamily: AppTypography.bodyFamily,
                  fontSize: 13,
                  color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 20),

              // Opción Invitado (Sin Cuenta) — solo para clientes, no para repartidores
              if (!_isDeliveryMode) ...[
                _buildLoginOption(
                  icon: const Icon(Icons.delivery_dining_rounded, color: Color(0xFFDC2626), size: 28),
                  label: 'Pedir como Invitado 🛵',
                  subtitle: 'Sin contraseñas, solo tu nombre y dirección',
                  isDark: isDark,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showGuestBottomSheet();
                  },
                ),
                const SizedBox(height: 10),
              ],

              // Opción Google
              _buildLoginOption(
                icon: Image.network(
                  'https://cdn1.iconfinder.com/data/icons/google_jfk_icons_by_verekia/512/google.png',
                  width: 26, height: 26,
                  errorBuilder: (_, _, _) => const Icon(Icons.g_mobiledata, color: Colors.blue, size: 28),
                ),
                label: 'Continuar con Google',
                subtitle: 'Ingresa con tu cuenta de Gmail',
                isDark: isDark,
                onTap: () {
                  Navigator.pop(ctx);
                  _handleGoogleAuth();
                },
              ),

              // Opción Correo
              _buildLoginOption(
                icon: Icon(Icons.email_outlined, color: redColor, size: 26),
                label: 'Ingresar con Correo',
                subtitle: 'Escribe tu correo y contraseña arriba',
                isDark: isDark,
                onTap: () {
                  Navigator.pop(ctx);
                  _emailFocusNode.requestFocus();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoginOption({
    required Widget icon,
    required String label,
    required String subtitle,
    required bool isDark,
    required VoidCallback onTap,
    Color? iconBg,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: iconBg != null
                  ? BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8))
                  : null,
              child: Center(child: icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: AppTypography.bodyFamily,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: isDark ? AppColors.textLight : const Color(0xFF1E1E1E),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: AppTypography.bodyFamily,
                      fontSize: 12,
                      color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? AppColors.textMutedDark : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  void _showSignupSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final redColor = isDark ? const Color(0xFFEF4444) : const Color(0xFFDC2626);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Text(
                'CREAR CUENTA',
                style: TextStyle(
                  fontFamily: AppTypography.displayFamily,
                  fontSize: 26,
                  color: redColor,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              DiablaTextField(
                key: const ValueKey('signup_name_field'),
                controller: _regNameController,
                label: 'Tu nombre',
                keyboardType: TextInputType.name,
                textInputAction: TextInputAction.next,
                prefixIcon: Icon(Icons.badge_outlined, color: redColor),
              ),
              const SizedBox(height: 12),
              DiablaTextField(
                key: const ValueKey('signup_email_field'),
                controller: _regEmailController,
                label: 'Correo electrónico',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                prefixIcon: Icon(Icons.alternate_email_rounded, color: redColor),
              ),
              const SizedBox(height: 12),
              DiablaTextField(
                key: const ValueKey('signup_password_field'),
                controller: _regPasswordController,
                label: 'Contraseña',
                obscureText: true,
                textInputAction: TextInputAction.next,
                prefixIcon: Icon(Icons.lock_outline_rounded, color: redColor),
              ),
              const SizedBox(height: 12),
              DiablaTextField(
                key: const ValueKey('signup_confirm_field'),
                controller: _regConfirmPasswordController,
                label: 'Confirmar contraseña',
                obscureText: true,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _handleEmailSignup(sheetCtx),
                prefixIcon: Icon(Icons.lock_person_outlined, color: redColor),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  onPressed: () => _handleEmailSignup(sheetCtx),
                  child: const Text(
                    'REGISTRARME',
                    style: TextStyle(
                      fontFamily: AppTypography.displayFamily,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(authNotifierProvider);
    final themeTextColor = isDark ? Colors.white70 : Colors.black87;
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 750;
    final logoHeight = isCompact ? 120.0 : 160.0;
    final gapSmall = isCompact ? 8.0 : 12.0;
    final gapMedium = isCompact ? 14.0 : 20.0;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E1712) : const Color(0xFFFAF7F2),
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ─── FONDO ESTÁTICO FIJO (100% PANTALLA INMÓVIL) ────────────────
          Positioned.fill(
            child: Image.asset(
              isDark ? 'assets/images/fondonegro2.png' : 'assets/images/fondoclaro2.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),

          // Overlay oscuro sutil
          if (isDark)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
              ),
            ),

          // ─── CONTENIDO RESPONSIVO Y SCROLLEABLE EN CUALQUIER PANTALLA ───
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: AppResponsive.maxContentWidth),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      AppResponsive.screenPaddingH(context),
                      isCompact ? 12 : 24,
                      AppResponsive.screenPaddingH(context),
                      28,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                    SizedBox(height: isCompact ? 6 : 12),

                    // Logo adaptable según la altura de la pantalla
                    Image.asset(
                      'assets/images/logo.png',
                      height: logoHeight,
                      fit: BoxFit.contain,
                    ),

                    SizedBox(height: gapSmall),

                    // TÍTULOS
                    Text(
                      '¡BIENVENIDO A LA DIABLA!',
                      style: TextStyle(
                        fontFamily: AppTypography.displayFamily,
                        fontSize: isCompact ? 22 : 26,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFFF5252) : const Color(0xFFC62828),
                        letterSpacing: 1.5,
                        height: 1.1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Auténtico Sabor Mexicano 🌶️🔥',
                      style: TextStyle(
                        fontFamily: AppTypography.bodyFamily,
                        fontSize: isCompact ? 13 : 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.textMutedDark : const Color(0xFF6D4C41),
                      ),
                      textAlign: TextAlign.center,
                    ),

                    SizedBox(height: gapMedium),

                    // CARGANDO INDICATOR
                    if (authState.isLoading) ...[
                      const CircularProgressIndicator(color: Color(0xFFDC2626)),
                      const SizedBox(height: 16),
                    ],

                    // Campos directos de correo y contraseña
                    DiablaTextField(
                      key: const ValueKey('screen_login_email_field'),
                      controller: _loginEmailController,
                      focusNode: _emailFocusNode,
                      label: 'Correo electrónico',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      prefixIcon: const Icon(Icons.alternate_email_rounded, color: Color(0xFFDC2626)),
                    ),
                    SizedBox(height: gapSmall),
                    DiablaTextField(
                      key: const ValueKey('screen_login_password_field'),
                      controller: _loginPasswordController,
                      label: 'Contraseña',
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _handleDirectEmailLogin(),
                      prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFFDC2626)),
                    ),
                    const SizedBox(height: 8),

                    // Enlace de restablecer contraseña
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: _showForgotPasswordDialog,
                        child: Text(
                          '¿Olvidaste tu contraseña?',
                          style: TextStyle(
                            fontFamily: AppTypography.bodyFamily,
                            color: isDark ? const Color(0xFFFF5252) : const Color(0xFFDC2626),
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: gapSmall + 4),

                    // ─── SELECTOR USUARIO / REPARTIDOR ──────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.cardDark : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(isDark ? 20 : 8),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Opción: Soy Cliente
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _isDeliveryMode = false),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: !_isDeliveryMode
                                      ? const Color(0xFFDC2626)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.person_rounded,
                                      size: 18,
                                      color: !_isDeliveryMode ? Colors.white : Colors.grey,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Soy Cliente',
                                      style: TextStyle(
                                        fontFamily: AppTypography.bodyFamily,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: !_isDeliveryMode ? Colors.white : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Divisor
                          Container(
                            width: 1,
                            height: 36,
                            color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
                          ),
                          // Opción: Soy Repartidor
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _isDeliveryMode = true),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: _isDeliveryMode
                                      ? const Color(0xFFDC2626)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.two_wheeler_rounded,
                                      size: 18,
                                      color: _isDeliveryMode ? Colors.white : Colors.grey,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Soy Repartidor',
                                      style: TextStyle(
                                        fontFamily: AppTypography.bodyFamily,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: _isDeliveryMode ? Colors.white : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: gapMedium),

                    // Botón Iniciar Sesión Principal
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        onPressed: authState.isLoading
                            ? null
                            : () => _handleDirectEmailLogin(),
                        child: const Text(
                          'INICIAR SESIÓN',
                          style: TextStyle(
                            fontFamily: AppTypography.displayFamily,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ─── BOTÓN CONTINUAR COMO INVITADO — solo para clientes ────
                    if (!_isDeliveryMode) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                            backgroundColor: isDark ? const Color(0xFF2C1E14) : const Color(0xFFFFF8E7),
                            foregroundColor: const Color(0xFFDC2626),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          onPressed: authState.isLoading ? null : _showGuestBottomSheet,
                          icon: const Icon(Icons.delivery_dining_rounded, size: 22, color: Color(0xFFDC2626)),
                          label: const Text(
                            'PEDIR COMO INVITADO (SIN REGISTRO)',
                            style: TextStyle(
                              fontFamily: AppTypography.bodyFamily,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    const SizedBox(height: 8),

                    // ─── SECCIÓN REGÍSTRATE Y 3 PUNTOS ─────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '¿No tienes cuenta? ',
                          style: TextStyle(
                            fontFamily: AppTypography.bodyFamily,
                            color: themeTextColor,
                            fontSize: 14,
                          ),
                        ),
                        GestureDetector(
                          onTap: authState.isLoading ? null : _showSignupSheet,
                          child: const Text(
                            'Regístrate',
                            style: TextStyle(
                              fontFamily: AppTypography.bodyFamily,
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Botón 3 puntos -> bottom sheet de otras opciones
                        GestureDetector(
                          onTap: authState.isLoading ? null : _showLoginOptionsSheet,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.cardDark : Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(isDark ? 30 : 10),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                )
                              ],
                            ),
                            child: Icon(
                              Icons.more_horiz_rounded,
                              color: isDark ? AppColors.textLight : AppColors.textDark,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
          ),
        ),
      ],
    ),
  );
  }
}
