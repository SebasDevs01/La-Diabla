// lib/features/driver/presentation/screens/driver_support_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../domain/entities/order_entity.dart';
import '../../../auth/providers/auth_notifier.dart';
import '../../providers/driver_operational_provider.dart';

class DriverSupportScreen extends ConsumerStatefulWidget {
  final OrderEntity? activeOrder;

  const DriverSupportScreen({super.key, this.activeOrder});

  @override
  ConsumerState<DriverSupportScreen> createState() => _DriverSupportScreenState();
}

class _DriverSupportScreenState extends ConsumerState<DriverSupportScreen> {
  static const String _supportWhatsApp = '+573177894561'; // Línea directa de operaciones La Diabla

  Future<void> _openWhatsAppSupport(String category, {String? subtopic}) async {
    final user = ref.read(authNotifierProvider).user;
    final opState = ref.read(driverOperationalProvider);
    final order = widget.activeOrder;

    Position? pos;
    try {
      pos = await Geolocator.getLastKnownPosition();
    } catch (_) {}

    final gpsStr = pos != null ? '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}' : 'No disponible';
    final orderStr = order != null ? '#${order.id.length > 6 ? order.id.substring(order.id.length - 6).toUpperCase() : order.id} (${order.status.name})' : 'Ninguno';

    final message = '''
🆘 *SOLICITUD DE SOPORTE REPARTIDOR — LA DIABLA*
━━━━━━━━━━━━━━━━━━━━
📌 *Categoría:* $category ${subtopic != null ? '($subtopic)' : ''}
👤 *Repartidor:* ${user?.name ?? 'Repartidor Diabla'} (${user?.phone ?? 'Sin teléfono'})
📦 *Pedido Activo:* $orderStr
📍 *Ubicación GPS:* $gpsStr
🛵 *Vehículo:* ${opState.preferences.vehicleType.displayName}
⚡ *Modo:* ${opState.preferences.activeWorkModeId}
🔋 *Batería Celular:* ${opState.batteryLevel}%
🕒 *Hora:* ${DateTime.now().toLocal().toString().substring(0, 16)}
━━━━━━━━━━━━━━━━━━━━
Hola equipo de operaciones, requiero asistencia con lo siguiente:
''';

    final encoded = Uri.encodeComponent(message);
    final whatsappUri = Uri.parse('https://wa.me/$_supportWhatsApp?text=$encoded');

    try {
      await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir WhatsApp: $e')),
        );
      }
    }
  }

  void _showCategoryDetails(String title, String emoji, List<String> subtopics) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1F120C) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 14),
              ...subtopics.map((topic) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFFDC2626)),
                    title: Text(topic, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openWhatsAppSupport(title, subtopic: topic);
                    },
                  )),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.chat_rounded),
                  label: const Text('Hablar con Asesor Humano en WhatsApp', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openWhatsAppSupport(title);
                  },
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
    final order = widget.activeOrder;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'CENTRO DE AYUDA Y SOPORTE 🆘',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        backgroundColor: isDark ? const Color(0xFF1F120C) : Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Banner de contexto si tiene pedido activo
          if (order != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withAlpha(15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFDC2626), width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.two_wheeler_rounded, color: Color(0xFFDC2626), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PEDIDO ACTIVO #${order.id.length > 6 ? order.id.substring(order.id.length - 6).toUpperCase() : order.id}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFDC2626)),
                        ),
                        Text(
                          'Destino: ${order.address?.formattedAddress ?? 'Dirección del cliente'}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          const Text(
            '¿CON QUÉ NECESITAS AYUDA HOY?',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey),
          ),
          const SizedBox(height: 12),

          _buildCategoryCard(
            title: 'Problema con pedido en curso',
            emoji: '📦',
            description: 'Dirección errónea, empaque dañado o cancelaciones',
            subtopics: [
              'El cliente no responde la llamada ni mensajes',
              'La dirección de entrega es inaccesible o incorrecta',
              'El paquete se derramó o sufrió daños en el camino',
              'El cliente desea cancelar o cambiar el pedido',
            ],
          ),
          _buildCategoryCard(
            title: 'Problemas de pago o liquidación',
            emoji: '💰',
            description: 'Efectivo, datáfono o tarifas de entrega',
            subtopics: [
              'El cliente no tiene efectivo completo ni cambio',
              'Error con el datáfono al procesar la tarjeta',
              'La tarifa de envío calculada no coincide',
            ],
          ),
          _buildCategoryCard(
            title: 'Problemas en Cocina Central',
            emoji: '🏪',
            description: 'Tiempos de espera, entrega de pedido en sede',
            subtopics: [
              'El pedido está demorado en cocina más de 20 min',
              'Faltan salsas, bebidas o complementos en el empaque',
            ],
          ),
          _buildCategoryCard(
            title: 'Problemas con la App o GPS',
            emoji: '⚙️',
            description: 'Ubicación, cierre inesperado, batería',
            subtopics: [
              'El mapa no actualiza la ruta en tiempo real',
              'No puedo marcar el pedido como entregado',
              'La app se cierra sola o está lenta',
            ],
          ),

          const SizedBox(height: 16),

          // Botón directo Asesor Humano
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF16A34A), Color(0xFF15803D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF16A34A).withAlpha(80),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                const Row(
                  children: [
                    Icon(Icons.support_agent_rounded, color: Colors.white, size: 32),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '¿NECESITAS ATENCIÓN PRIORITARIA? 👨‍💻',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                          Text(
                            'Habla en vivo con nuestro equipo de despacho por WhatsApp',
                            style: TextStyle(color: Colors.white70, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF15803D),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.chat_rounded, size: 18),
                    label: const Text('HABLAR CON ASESOR HUMANO', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
                    onPressed: () => _openWhatsAppSupport('Asistencia General Prioritaria'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCategoryCard({
    required String title,
    required String emoji,
    required String description,
    required List<String> subtopics,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C1B14) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? AppColors.dividerDark : Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626).withAlpha(15),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 22)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
        subtitle: Text(description, style: const TextStyle(fontSize: 11.5)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
        onTap: () => _showCategoryDetails(title, emoji, subtopics),
      ),
    );
  }
}
