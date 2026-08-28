import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/services/battery_service.dart';
import '../../../../core/services/floating_bubble_service.dart';
import '../../../../core/services/permission_service.dart';
import '../../providers/driver_operational_provider.dart';

class DriverPermissionsScreen extends ConsumerStatefulWidget {
  const DriverPermissionsScreen({super.key});

  @override
  ConsumerState<DriverPermissionsScreen> createState() =>
      _DriverPermissionsScreenState();
}

class _DriverPermissionsScreenState
    extends ConsumerState<DriverPermissionsScreen> with WidgetsBindingObserver {
  bool _fineLocationGranted = false;
  bool _backgroundLocationGranted = false;
  bool _notificationsGranted = false;
  bool _overlayGranted = false;
  int _batteryLevel = 100;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAllPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAllPermissions();
    }
  }

  Future<void> _checkAllPermissions() async {
    setState(() => _isLoading = true);

    try {
      final locPermission = await Geolocator.checkPermission();
      final fineLoc = locPermission == LocationPermission.always ||
          locPermission == LocationPermission.whileInUse;
      final bgLoc = locPermission == LocationPermission.always;
      final overlay = await FloatingBubbleService.instance.hasOverlayPermission();
      final battery = await BatteryService.instance.getBatteryLevel();

      final notifSettings = await FirebaseMessaging.instance.getNotificationSettings();
      final notifGranted = notifSettings.authorizationStatus == AuthorizationStatus.authorized ||
          notifSettings.authorizationStatus == AuthorizationStatus.provisional;

      if (mounted) {
        setState(() {
          _fineLocationGranted = fineLoc;
          _backgroundLocationGranted = bgLoc;
          _notificationsGranted = notifGranted;
          _overlayGranted = overlay;
          _batteryLevel = battery;
          _isLoading = false;
        });
      }

      ref.read(driverOperationalProvider.notifier).checkLocationStatus();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final opState = ref.watch(driverOperationalProvider);
    final allReady = _fineLocationGranted &&
        _backgroundLocationGranted &&
        !opState.isBatteryLow;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1E1712) : const Color(0xFFFAF7F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFDC2626),
        foregroundColor: Colors.white,
        title: const Text(
          'Configuración de Permisos',
          style: TextStyle(
            fontFamily: AppTypography.displayFamily,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
            onPressed: _checkAllPermissions,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFDC2626)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Banner Resumen de Estado
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: allReady
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: (allReady
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFDC2626))
                            .withAlpha(60),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        allReady
                            ? Icons.verified_user_rounded
                            : Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              allReady
                                  ? 'DISPOSITIVO 100% OPERATIVO'
                                  : 'PERMISOS REQUERIDOS',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              allReady
                                  ? 'Cumples con todas las condiciones para recibir pedidos de La Diabla 🔥'
                                  : 'Para recibir pedidos necesitas activar los permisos marcados en rojo.',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  'PERMISOS Y ESTADO DEL DISPOSITIVO',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(height: 12),

                // 1. Ubicación precisa
                _buildPermissionCard(
                  isDark: isDark,
                  icon: Icons.location_on_rounded,
                  title: 'Ubicación precisa',
                  description:
                      'Necesaria para calcular rutas, asignar pedidos cercanos y mostrarte en el mapa.',
                  isGranted: _fineLocationGranted,
                  onAction: () async {
                    await PermissionService.requestLocationPermission();
                    _checkAllPermissions();
                  },
                ),

                // 2. Ubicación en segundo plano
                _buildPermissionCard(
                  isDark: isDark,
                  icon: Icons.share_location_rounded,
                  title: 'Ubicación en segundo plano',
                  description:
                      'Permite transmitir tu posición GPS mientras usas Waze o tienes el teléfono bloqueado ("Permitir todo el tiempo").',
                  isGranted: _backgroundLocationGranted,
                  onAction: () async {
                    await PermissionService.showBackgroundLocationRationaleDialog(
                        context);
                    await Geolocator.openAppSettings();
                    _checkAllPermissions();
                  },
                ),

                // 3. Notificación permanente y alertas
                _buildPermissionCard(
                  isDark: isDark,
                  icon: Icons.notifications_active_rounded,
                  title: 'Notificaciones y Alertas',
                  description:
                      'Para recibir avisos instantáneos de nuevos pedidos y actualizaciones de ruta.',
                  isGranted: _notificationsGranted,
                  onAction: () async {
                    await PermissionService.requestNotificationPermission();
                    _checkAllPermissions();
                  },
                ),

                // 4. Mostrar sobre otras aplicaciones (Overlay Flotante)
                _buildPermissionCard(
                  isDark: isDark,
                  icon: Icons.open_in_browser_rounded,
                  title: 'Mostrar sobre otras aplicaciones',
                  description:
                      'Acceso rápido flotante de La Diabla para volver rápidamente a la app mientras navegas con Waze o Google Maps.',
                  isGranted: _overlayGranted,
                  buttonText: 'Activar acceso rápido',
                  onAction: () async {
                    await _showOverlayRationaleAndRequest();
                  },
                ),

                // 5. Estado de Batería
                _buildStatusCard(
                  isDark: isDark,
                  icon: Icons.battery_charging_full_rounded,
                  title: 'Nivel de Batería',
                  description: _batteryLevel < 10
                      ? '⚠️ Batería crítica ($_batteryLevel%). Conecta el cargador para poder recibir pedidos.'
                      : 'Nivel óptimo ($_batteryLevel%). Puedes recibir pedidos normalmente.',
                  isSuccess: _batteryLevel >= 10,
                  statusLabel: '$_batteryLevel%',
                ),

                // 6. Llamadas telefónicas
                _buildStatusCard(
                  isDark: isDark,
                  icon: Icons.phone_in_talk_rounded,
                  title: 'Llamadas a clientes',
                  description:
                      'Marcación directa por llamada o WhatsApp respetando el principio de mínimo privilegio.',
                  isSuccess: true,
                  statusLabel: 'Listo',
                ),

                const SizedBox(height: 20),

                // Botón abrir Ajustes del Sistema
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(
                        color: isDark ? Colors.white30 : Colors.grey.shade400),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.settings_rounded, size: 20),
                  label: const Text(
                    'Abrir Ajustes de la Aplicación en Android',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => Geolocator.openAppSettings(),
                ),
                const SizedBox(height: 30),
              ],
            ),
    );
  }

  Future<void> _showOverlayRationaleAndRequest() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.open_in_browser_rounded,
                color: Color(0xFFDC2626), size: 26),
            SizedBox(width: 8),
            Text('Acceso Rápido Flotante'),
          ],
        ),
        content: const Text(
          'Activa este permiso para mostrar el acceso rápido de La Diabla sobre otras aplicaciones mientras trabajas y navegas en la ruta.',
          style: TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text('Ahora no', style: TextStyle(color: Colors.grey.shade500)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Activar acceso rápido'),
          ),
        ],
      ),
    );

    if (result == true) {
      await FloatingBubbleService.instance.requestOverlayPermission();
      _checkAllPermissions();
    }
  }

  Widget _buildPermissionCard({
    required bool isDark,
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    String? buttonText,
    required VoidCallback onAction,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C1B14) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isGranted
              ? (isDark ? const Color(0xFF166534) : const Color(0xFFBBF7D0))
              : const Color(0xFFDC2626).withAlpha(80),
          width: 1.2,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isGranted
                      ? const Color(0xFF16A34A).withAlpha(20)
                      : const Color(0xFFDC2626).withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: isGranted
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14.5),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isGranted
                      ? const Color(0xFF16A34A).withAlpha(20)
                      : const Color(0xFFDC2626).withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isGranted
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      color: isGranted
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFDC2626),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isGranted ? 'Activado' : 'Desactivado',
                      style: TextStyle(
                        color: isGranted
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
              height: 1.35,
            ),
          ),
          if (!isGranted) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: onAction,
                child: Text(
                  buttonText ?? 'Activar permiso',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusCard({
    required bool isDark,
    required IconData icon,
    required String title,
    required String description,
    required bool isSuccess,
    required String statusLabel,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C1B14) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSuccess
              ? (isDark ? const Color(0xFF166534) : const Color(0xFFBBF7D0))
              : const Color(0xFFDC2626).withAlpha(80),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSuccess
                  ? const Color(0xFF16A34A).withAlpha(20)
                  : const Color(0xFFDC2626).withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isSuccess
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFDC2626),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14.5),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11.5,
                    color:
                        isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isSuccess
                  ? const Color(0xFF16A34A).withAlpha(20)
                  : const Color(0xFFDC2626).withAlpha(20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: isSuccess
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
