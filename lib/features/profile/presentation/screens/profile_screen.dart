import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/theme/theme_provider.dart';
import '../../../auth/providers/auth_notifier.dart';
import '../../../favorites/presentation/widgets/favorites_sheet.dart';
import '../../../orders/providers/orders_provider.dart';
import '../widgets/privacy_policy_sheet.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  // Lista de avatares oficiales de La Diabla
  static const List<Map<String, String>> _availableAvatars = [
    {
      'name': 'Diablo Taco & Fuego',
      'path': 'assets/images/diabloperfil.png',
    },
    {
      'name': 'Diablo Máscara',
      'path': 'assets/images/diablopartedearriba.png',
    },
    {
      'name': 'Emblema La Diabla',
      'path': 'assets/images/logo.png',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final authState = ref.watch(authNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = authState.user;
    final ordersAsync = ref.watch(userOrdersStreamProvider);
    final completedOrdersCount = ordersAsync.value?.length ?? 0;

    final displayName = (user?.displayName != null && user!.displayName.isNotEmpty)
        ? user.displayName
        : (user?.isGuest == true ? 'Invitado Diabla' : 'Cliente Diabla');

    final email = (user?.email != null && user!.email.isNotEmpty && !user.email.contains('guest'))
        ? user.email
        : (user?.isGuest == true ? 'invitado@ladiabla.app' : 'Sin correo registrado');

    final phone = (user?.phone != null && user!.phone!.isNotEmpty && user.phone != '3000000000')
        ? user.phone!
        : 'Sin celular (Toca para agregar 📱)';

    final avatarPath = (user?.photoUrl != null && user!.photoUrl!.isNotEmpty)
        ? user.photoUrl!
        : (user?.isGuest == true ? 'assets/images/fotoperfilinvitados.png' : 'assets/images/diabloperfil.png');

    // Fecha de registro
    final registerDate = user?.createdAt ?? DateTime(2024, 5, 1);
    final months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    final memberSinceStr = '${months[registerDate.month - 1]} ${registerDate.year}';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF140E0A) : const Color(0xFFFAF7F2),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal, vertical: 12),
          children: [
            // ─── CABECERA CON ILUSTRACIÓN DIABLO Y NOTIFICACIONES ───────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MI PERFIL',
                        style: TextStyle(
                          fontFamily: AppTypography.displayFamily,
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFDC2626),
                          letterSpacing: 1.2,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '¡Qué bueno verte por aquí, diabli@! 🔥',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.textMutedDark : const Color(0xFF5C4A40),
                        ),
                      ),
                    ],
                  ),
                ),
                // Ilustración de Diablo en la parte superior derecha
                Container(
                  width: 90,
                  height: 90,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                  ),
                  child: Image.asset(
                    'assets/images/diabloperfil.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 8),
                // Botón de notificaciones con badge
                GestureDetector(
                  onTap: () => context.push('/notifications'),
                  child: Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF241A14) : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(isDark ? 50 : 15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Stack(
                      children: [
                        Icon(Icons.notifications_none_rounded, color: Color(0xFFDC2626), size: 24),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: CircleAvatar(
                            radius: 4.5,
                            backgroundColor: Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ─── TARJETA PRINCIPAL DEL USUARIO (EDITABLE) ────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1712) : const Color(0xFF1F1612),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFDC2626).withAlpha(40),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                  const BoxShadow(
                    color: Colors.black45,
                    blurRadius: 10,
                    offset: Offset(0, 6),
                  ),
                ],
                border: Border.all(
                  color: const Color(0xFFDC2626).withAlpha(120),
                  width: 1.2,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Avatar con botón de cámara para cambiar foto
                      GestureDetector(
                        onTap: _showAvatarPickerSheet,
                        child: Stack(
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFDC2626), width: 2),
                                color: const Color(0xFF2C1B14),
                              ),
                              child: ClipOval(
                                child: _buildAvatarImage(avatarPath),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFDC2626),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(color: Colors.black45, blurRadius: 4),
                                  ],
                                ),
                                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Datos de texto y botón editar perfil
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          displayName,
                                          style: const TextStyle(
                                            fontFamily: AppTypography.displayFamily,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Text('🔥', style: TextStyle(fontSize: 16)),
                                    ],
                                  ),
                                ),
                                // Botón Editar Perfil
                                GestureDetector(
                                  onTap: _showEditProfileDialog,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDC2626).withAlpha(30),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: const Color(0xFFDC2626).withAlpha(160)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.edit_rounded, color: Color(0xFFFF5252), size: 13),
                                        SizedBox(width: 4),
                                        Text(
                                          'Editar perfil',
                                          style: TextStyle(
                                            color: Color(0xFFFF5252),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              email,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              phone,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ─── ESTADÍSTICAS DEL CLIENTE (MÉTRICAS REALES) ───────────────────
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.shopping_bag_rounded,
                    iconColor: const Color(0xFFDC2626),
                    value: '$completedOrdersCount',
                    label: 'Pedidos\nrealizados',
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.star_rounded,
                    iconColor: const Color(0xFFFFB300),
                    value: '⭐ 5.0',
                    label: 'Calificación\npromedio',
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.military_tech_rounded,
                    iconColor: const Color(0xFFE53935),
                    value: 'Diabl@',
                    label: 'Miembro desde\n$memberSinceStr',
                    isDark: isDark,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // ─── LISTA DE OPCIONES DEL PERFIL (ESTILO REFERENCIA) ────────────
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1712) : Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 40 : 10),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(
                  color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
                ),
              ),
              child: Column(
                children: [
                  // 1. Mis Favoritos
                  _buildProfileOptionTile(
                    icon: Icons.favorite_rounded,
                    title: 'Mis favoritos ❤️',
                    subtitle: 'Tus platillos y antojos preferidos guardados',
                    isDark: isDark,
                    onTap: () => FavoritesSheet.show(context),
                  ),
                  const Divider(height: 1),

                  // 2. Cupones y Promociones
                  _buildProfileOptionTile(
                    icon: Icons.confirmation_num_rounded,
                    title: 'Cupones y promociones 🎟️',
                    subtitle: 'Activa descuentos y promociones exclusivas',
                    isDark: isDark,
                    onTap: () => _showCouponsSheet(context),
                  ),
                  const Divider(height: 1),

                  // 3. Direcciones Guardadas
                  _buildProfileOptionTile(
                    icon: Icons.location_on_rounded,
                    title: 'Direcciones guardadas 📍',
                    subtitle: 'Gestiona tus direcciones de entrega a domicilio',
                    isDark: isDark,
                    onTap: () => context.push('/addresses'),
                  ),
                  const Divider(height: 1),

                  // 4. Métodos de Pago
                  _buildProfileOptionTile(
                    icon: Icons.credit_card_rounded,
                    title: 'Métodos de pago 💳',
                    subtitle: 'Administra tus tarjetas, Nequi y PSE',
                    isDark: isDark,
                    onTap: () => context.push('/wallet'),
                  ),
                  const Divider(height: 1),

                  // 5. Ayuda y Soporte
                  _buildProfileOptionTile(
                    icon: Icons.headset_mic_rounded,
                    title: 'Ayuda y soporte 🎧',
                    subtitle: 'Preguntas frecuentes y contacto por WhatsApp',
                    isDark: isDark,
                    onTap: () => _contactSupport(context),
                  ),
                  const Divider(height: 1),

                  // 6. Configuración y Apariencia
                  _buildProfileOptionTile(
                    icon: Icons.settings_rounded,
                    title: 'Configuración y Apariencia ⚙️',
                    subtitle: themeMode == ThemeMode.light
                        ? 'Modo Claro ☀️ activado'
                        : (themeMode == ThemeMode.dark ? 'Modo Oscuro 🌙 activado' : 'Automático del sistema ⚙️'),
                    isDark: isDark,
                    onTap: () => _showThemeSelectorSheet(context),
                  ),
                  const Divider(height: 1),

                  // 7. Política de Privacidad y Términos (Google Play Store)
                  _buildProfileOptionTile(
                    icon: Icons.shield_rounded,
                    title: 'Privacidad y Términos 🔒',
                    subtitle: 'Tratamiento de datos y seguridad oficial',
                    isDark: isDark,
                    onTap: () => PrivacyPolicySheet.show(context),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ─── BOTÓN CERRAR SESIÓN ─────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                  foregroundColor: const Color(0xFFDC2626),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text(
                  'Cerrar sesión',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: () async {
                  await ref.read(authNotifierProvider.notifier).signOut();
                  if (context.mounted) {
                    context.go('/auth');
                  }
                },
              ),
            ),

            const SizedBox(height: 10),

            // ─── BOTÓN ELIMINAR CUENTA (PLAY STORE COMPLIANCE) ───────────────
            Center(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                icon: const Icon(Icons.delete_forever_rounded, size: 16, color: Colors.grey),
                label: const Text(
                  'Eliminar mi cuenta y datos personales',
                  style: TextStyle(
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                  ),
                ),
                onPressed: () => _confirmAccountDeletion(context),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarImage(String path) {
    if (path.startsWith('http')) {
      return Image.network(
        path,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Image.asset('assets/images/fotoperfilinvitados.png', width: double.infinity, height: double.infinity, fit: BoxFit.cover),
      );
    } else if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Image.asset('assets/images/fotoperfilinvitados.png', width: double.infinity, height: double.infinity, fit: BoxFit.cover),
      );
    }
    final file = File(path);
    if (file.existsSync()) {
      return Image.file(
        file,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Image.asset('assets/images/fotoperfilinvitados.png', width: double.infinity, height: double.infinity, fit: BoxFit.cover),
      );
    }
    return Image.asset('assets/images/fotoperfilinvitados.png', width: double.infinity, height: double.infinity, fit: BoxFit.cover);
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1712) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppTypography.displayFamily,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1E1712),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withAlpha(isDark ? 35 : 18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: const Color(0xFFDC2626), size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppTypography.bodyFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 14),
          ],
        ),
      ),
    );
  }

  // ─── MODAL SELECCIONAR AVATAR O CARGAR DE GALERÍA ───────────────────────
  void _showAvatarPickerSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1712) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle superior
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const Text(
                'Cambiar Foto de Perfil 📸',
                style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Sube una imagen de tu galería o elige un avatar oficial:',
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
              const SizedBox(height: 16),

              // Botones de Acción Rápida (Galería y Cámara)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.photo_library_rounded, size: 20),
                      label: const Text(
                        'Mi Galería 🖼️',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final picker = ImagePicker();
                        final picked = await picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 85,
                          maxWidth: 800,
                          maxHeight: 800,
                        );
                        if (picked != null) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          await ref.read(authNotifierProvider.notifier).updateUserProfile(
                                photoUrl: picked.path,
                              );
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('✅ Foto de perfil personalizada actualizada desde tu galería.'),
                                backgroundColor: Color(0xFF16A34A),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                        foregroundColor: const Color(0xFFDC2626),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.camera_alt_rounded, size: 20),
                      label: const Text(
                        'Cámara 📸',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final picker = ImagePicker();
                        final picked = await picker.pickImage(
                          source: ImageSource.camera,
                          imageQuality: 85,
                          maxWidth: 800,
                          maxHeight: 800,
                        );
                        if (picked != null) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          await ref.read(authNotifierProvider.notifier).updateUserProfile(
                                photoUrl: picked.path,
                              );
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('✅ Foto tomada y actualizada como perfil.'),
                                backgroundColor: Color(0xFF16A34A),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'O elige un avatar oficial',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 14),

              // Grid de Avatares Oficiales
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const _VerticalGridDelegate(),
                itemCount: _availableAvatars.length,
                itemBuilder: (context, index) {
                  final avatar = _availableAvatars[index];
                  return GestureDetector(
                    onTap: () async {
                      Navigator.pop(ctx);
                      final messenger = ScaffoldMessenger.of(context);
                      await ref.read(authNotifierProvider.notifier).updateUserProfile(
                            photoUrl: avatar['path'],
                          );
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Foto de perfil actualizada a "${avatar['name']}" 🔥'),
                            backgroundColor: const Color(0xFF16A34A),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    child: Column(
                      children: [
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFDC2626), width: 2),
                            color: const Color(0xFF2C1B14),
                          ),
                          child: ClipOval(
                            child: Image.asset(avatar['path']!, fit: BoxFit.cover),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          avatar['name']!,
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── DIÁLOGO EDITAR PERFIL COMPLETO ────────────────────────────────────────
  Future<void> _showEditProfileDialog() async {
    final user = ref.read(authNotifierProvider).user;
    final nameCtrl = TextEditingController(text: user?.name ?? '');
    final emailCtrl = TextEditingController(text: user?.email != null && !user!.email.contains('guest') ? user.email : '');
    final phoneCtrl = TextEditingController(text: user?.phone ?? '');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1712) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.edit_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 8),
            Text('Editar Mi Perfil 👤', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nombre Completo:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              const SizedBox(height: 6),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  hintText: 'Tu nombre',
                  filled: true,
                  fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              const Text('Correo Electrónico:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              const SizedBox(height: 6),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'ejemplo@gmail.com',
                  filled: true,
                  fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              const Text('Número de Teléfono / WhatsApp:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              const SizedBox(height: 6),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: '317 116 6497',
                  filled: true,
                  fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar Cambios'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (updated == true) {
      final messenger = ScaffoldMessenger.of(context);
      final success = await ref.read(authNotifierProvider.notifier).updateUserProfile(
            name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
            email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
            phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
          );

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(success ? '✅ Perfil actualizado con éxito.' : 'Error al actualizar perfil.'),
            backgroundColor: success ? const Color(0xFF16A34A) : AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ─── MODAL CUPONES Y PROMOCIONES ───────────────────────────────────────────
  void _showCouponsSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final coupons = [
      {'code': 'DIABLA10', 'desc': '10% de descuento en tu orden completa', 'min': 'Sin monto mínimo'},
      {'code': 'ENVIOGRATIS', 'desc': 'Domicilio 100% GRATIS en Bucaramanga', 'min': 'Min. \$25.000'},
      {'code': 'TACOLOVER', 'desc': '\$5.000 de descuento en Combos y Tacos', 'min': 'Min. \$30.000'},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1712) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.confirmation_num_rounded, color: Color(0xFFDC2626), size: 24),
                SizedBox(width: 8),
                Text(
                  'Cupones y Promociones 🎟️',
                  style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Toca un cupón para copiar el código y usarlo en el carrito:', style: TextStyle(fontSize: 12.5, color: Colors.grey)),
            const SizedBox(height: 14),
            ...coupons.map(
              (c) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C1B14) : const Color(0xFFFFF8E7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFDC2626).withAlpha(100)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        c['code']!,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c['desc']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                          Text(c['min']!, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, color: Color(0xFFDC2626), size: 20),
                      tooltip: 'Copiar cupón',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: c['code']!));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('¡Cupón ${c['code']} copiado al portapapeles! 📋'),
                            backgroundColor: const Color(0xFF16A34A),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── SOPORTE Y WHATSAPP ───────────────────────────────────────────────────
  Future<void> _contactSupport(BuildContext context) async {
    final uri = Uri.parse('https://wa.me/573171166497?text=Hola%20La%20Diabla%20🌶️,%20necesito%20soporte%20con%20mi%20cuenta%20o%20pedido.');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WhatsApp de soporte: +57 320 221 2856'),
            backgroundColor: Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ─── SELECTOR DE TEMA ──────────────────────────────────────────────────────
  void _showThemeSelectorSheet(BuildContext context) {
    final themeMode = ref.read(themeModeProvider);

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Selecciona el Tema de la App',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.light_mode, color: AppColors.accent),
              title: const Text('Modo Claro ☀️'),
              trailing: themeMode == ThemeMode.light ? const Icon(Icons.check, color: AppColors.primary) : null,
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.dark_mode, color: AppColors.primary),
              title: const Text('Modo Oscuro 🌙'),
              trailing: themeMode == ThemeMode.dark ? const Icon(Icons.check, color: AppColors.primary) : null,
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.brightness_auto, color: AppColors.secondary),
              title: const Text('Automático (Según el sistema) ⚙️'),
              trailing: themeMode == ThemeMode.system ? const Icon(Icons.check, color: AppColors.primary) : null,
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.system);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── ELIMINACIÓN DE CUENTA ─────────────────────────────────────────────────
  Future<void> _confirmAccountDeletion(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 28),
            SizedBox(width: 8),
            Text('¿Eliminar tu cuenta?'),
          ],
        ),
        content: const Text(
          'Esta acción es irreversible y permanente.\n\n'
          'Se eliminarán de forma definitiva:\n'
          '• Tu perfil y datos personales.\n'
          '• Tus direcciones guardadas.\n'
          '• Tu historial de pedidos y compras.\n\n'
          '¿Estás seguro de que deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, Eliminar Definitivamente'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final success = await ref.read(authNotifierProvider.notifier).deleteAccount();
      if (context.mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tu cuenta ha sido eliminada con éxito.'),
              backgroundColor: Color(0xFF16A34A),
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.go('/auth');
        } else {
          final err = ref.read(authNotifierProvider).errorMessage;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(err ?? 'Error al eliminar cuenta.'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }
}

class _VerticalGridDelegate extends SliverGridDelegateWithFixedCrossAxisCount {
  const _VerticalGridDelegate()
      : super(
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.75,
        );
}
