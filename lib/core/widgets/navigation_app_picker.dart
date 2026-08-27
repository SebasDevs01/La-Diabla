// lib/core/widgets/navigation_app_picker.dart
import 'package:flutter/material.dart';
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

  static Future<void> show(
    BuildContext context, {
    required double latitude,
    required double longitude,
    String destinationName = 'Dirección de Entrega',
    String? addressText,
  }) {
    return showModalBottomSheet<void>(
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
          // Barra superior de arrastre
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
                      destinationName,
                      style: TextStyle(
                        fontFamily: AppTypography.bodyFamily,
                        fontSize: 13,
                        color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

          // Botón 1: Google Maps
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
              final success = await MapsService.openInGoogleMaps(
                latitude,
                longitude,
                label: destinationName,
              );
              if (!success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No fue posible abrir Google Maps en este dispositivo'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),

          const SizedBox(height: 12),

          // Botón 2: Waze
          _buildAppButton(
            context: context,
            title: 'Waze',
            subtitle: 'Alertas de tráfico, cámaras y policía',
            iconWidget: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF33CCFF).withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.directions_car_rounded, color: Color(0xFF00A3DA), size: 26),
              ),
            ),
            isDark: isDark,
            onTap: () async {
              Navigator.of(context).pop();
              final success = await MapsService.openInWaze(latitude, longitude);
              if (!success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No fue posible abrir Waze en este dispositivo'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
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
  }) {
    return Material(
      color: isDark ? const Color(0xFF261D17) : const Color(0xFFF4F6F9),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              iconWidget,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
