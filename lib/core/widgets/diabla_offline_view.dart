// lib/core/widgets/diabla_offline_view.dart
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';

class DiablaOfflineView extends StatelessWidget {
  const DiablaOfflineView({
    super.key,
    this.title = 'Ups, algo salió mal.',
    this.subtitle = 'Estamos en ello para resolverlo cuanto antes. Comprueba tu conexión a internet.',
    this.onRetry,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Círculo gris suave con icono de desconexión estilo Rappi
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1712) : const Color(0xFFF3F0EC),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  Icons.signal_wifi_connected_no_internet_4_rounded,
                  size: 64,
                  color: isDark ? Colors.white38 : const Color(0xFF9E9289),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Título
            Text(
              title,
              style: TextStyle(
                fontFamily: AppTypography.displayFamily,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: isDark ? Colors.white : const Color(0xFF1A120D),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Subtítulo
            Text(
              subtitle,
              style: TextStyle(
                fontFamily: AppTypography.bodyFamily,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.textMutedDark : const Color(0xFF756A63),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Botón Reintentar
            if (onRetry != null)
              SizedBox(
                width: 160,
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF2C221B) : const Color(0xFFEBE6DF),
                    foregroundColor: isDark ? Colors.white : const Color(0xFF2C1B14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  onPressed: onRetry,
                  child: const Text(
                    'Reintentar',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
