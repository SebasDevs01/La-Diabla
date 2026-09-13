// lib/core/widgets/navigation_app_picker.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../services/maps_service.dart';

class NavigationAppPicker extends StatelessWidget {
  const NavigationAppPicker({
    super.key,
    required this.latitude,
    required this.longitude,
    this.destinationName = 'Dirección de Entrega',
    this.addressText,
  });

  final double latitude;
  final double longitude;
  final String destinationName;
  final String? addressText;

  /// Intenta abrir Waze directamente. Si no está instalado, muestra el picker.
  static Future<void> show(
    BuildContext context, {
    required double latitude,
    required double longitude,
    String destinationName = 'Dirección de Entrega',
    String? addressText,
  }) async {
    // Intentar abrir Waze directo (prioridad máxima para repartidores)
    final wazeUri = Uri.parse('waze://?ll=$latitude,$longitude&navigate=yes');
    try {
      final canWaze = await canLaunchUrl(wazeUri);
      if (canWaze) {
        await launchUrl(wazeUri, mode: LaunchMode.externalApplication);
        return; // Waze abierto, no mostrar picker
      }
    } catch (_) {}

    // Waze no instalado → mostrar picker (Waze primero, Google Maps segundo)
    if (context.mounted) {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => NavigationAppPicker(
          latitude: latitude,
          longitude: longitude,
          destinationName: destinationName,
          addressText: addressText,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1712) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 80 : 30),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Barra de arrastre
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Título
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.navigation_rounded,
                  color: Color(0xFFDC2626),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Iniciar Navegación GPS',
                      style: TextStyle(
                        fontFamily: AppTypography.displayFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF1C1C1C),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Waze no está instalado — elige una app:',
                      style: TextStyle(
                        fontFamily: AppTypography.bodyFamily,
                        fontSize: 13,
                        color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (addressText != null && addressText!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF140E0A) : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_rounded, color: Color(0xFFDC2626), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      addressText!,
                      style: TextStyle(
                        fontFamily: AppTypography.bodyFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.textLight : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // ── Botón 1: Waze (PRIORIDAD) ──────────────────────────────────────
          _buildAppButton(
            context: context,
            title: 'Waze',
            subtitle: 'Recomendado · Alertas de tráfico, policía y cámaras',
            isRecommended: true,
            iconWidget: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF33CCFF).withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Image.network(
                  'https://upload.wikimedia.org/wikipedia/commons/thumb/7/7b/Waze_icon.svg/120px-Waze_icon.svg.png',
                  width: 28,
                  height: 28,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.directions_car_rounded,
                    color: Color(0xFF00A3DA),
                    size: 26,
                  ),
                ),
              ),
            ),
            isDark: isDark,
            onTap: () async {
              Navigator.of(context).pop();
              await MapsService.openInWaze(latitude, longitude);
            },
          ),

          const SizedBox(height: 12),

          // ── Botón 2: Google Maps ────────────────────────────────────────────
          _buildAppButton(
            context: context,
            title: 'Google Maps',
            subtitle: 'Ruta en tiempo real y vista satelital',
            iconWidget: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF4285F4).withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.map_rounded, color: Color(0xFF4285F4), size: 26),
              ),
            ),
            isDark: isDark,
            onTap: () async {
              Navigator.of(context).pop();
              await MapsService.openInGoogleMaps(
                latitude,
                longitude,
                label: destinationName,
              );
            },
          ),

          const SizedBox(height: 8),

          // Nota de instalación de Waze
          Center(
            child: TextButton.icon(
              onPressed: () async {
                final uri = Uri.parse('market://details?id=com.waze');
                final webUri = Uri.parse('https://play.google.com/store/apps/details?id=com.waze');
                try {
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    await launchUrl(webUri, mode: LaunchMode.externalApplication);
                  }
                } catch (_) {}
              },
              icon: const Icon(Icons.download_rounded, size: 16, color: Color(0xFF00A3DA)),
              label: const Text(
                'Instalar Waze gratis',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF00A3DA),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppButton({
    required BuildContext context,
    required String title,
    required String subtitle,
    required Widget iconWidget,
    required bool isDark,
    required VoidCallback onTap,
    bool isRecommended = false,
  }) {
    return Material(
      color: isRecommended
          ? (isDark ? const Color(0xFF0D2B1F) : const Color(0xFFECFDF5))
          : (isDark ? const Color(0xFF261D17) : const Color(0xFFF4F6F9)),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: isRecommended
                ? Border.all(color: const Color(0xFF16A34A).withAlpha(80), width: 1.5)
                : null,
          ),
          child: Row(
            children: [
              iconWidget,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: AppTypography.bodyFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF1C1C1C),
                          ),
                        ),
                        if (isRecommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF16A34A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'RECOMENDADO',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
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
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
