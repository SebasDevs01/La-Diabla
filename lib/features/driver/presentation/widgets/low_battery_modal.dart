// lib/features/driver/presentation/widgets/low_battery_modal.dart
import 'package:flutter/material.dart';
import '../../../../app/theme/app_typography.dart';

/// Modal de alerta cuando la batería del teléfono cae por debajo del 10%.
class LowBatteryModal extends StatelessWidget {
  final int batteryLevel;
  final VoidCallback onDismiss;

  const LowBatteryModal({
    super.key,
    required this.batteryLevel,
    required this.onDismiss,
  });

  static DateTime? _lastShownTime;
  static int? _lastShownLevel;

  /// Muestra el modal protegiendo contra spam repetitivo.
  static Future<void> showIfNeeded(BuildContext context, int batteryLevel) async {
    final now = DateTime.now();
    // Si ya se mostró hace menos de 3 minutos con el mismo nivel o superior, no repetir
    if (_lastShownTime != null &&
        now.difference(_lastShownTime!).inMinutes < 3 &&
        _lastShownLevel == batteryLevel) {
      return;
    }

    _lastShownTime = now;
    _lastShownLevel = batteryLevel;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => LowBatteryModal(
        batteryLevel: batteryLevel,
        onDismiss: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 12,
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icono destacado de batería baja
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.battery_alert_rounded,
                    size: 48,
                    color: Color(0xFFDC2626),
                  ),
                  Positioned(
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$batteryLevel%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Título destacado
            const Text(
              '⚠️ ¡Cuidado, carga tu celular!',
              style: TextStyle(
                fontFamily: AppTypography.displayFamily,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C1B14),
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Mensaje explicativo
            Text(
              'Tienes menos del 10% de batería ($batteryLevel%). No recibirás más pedidos hasta que cargues tu celular.\n\nSi tienes un pedido en curso, puedes terminar de entregarlo sin problema.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),

            // Botón Entendido
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: onDismiss,
                child: const Text(
                  'Entendido',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
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
