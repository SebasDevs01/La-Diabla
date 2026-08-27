// lib/features/profile/presentation/widgets/privacy_policy_sheet.dart
import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';

class PrivacyPolicySheet extends StatelessWidget {
  const PrivacyPolicySheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const PrivacyPolicySheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: screenH * 0.88),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1712) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20)],
      ),
      child: Column(
        children: [
          // Handle superior
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Color(0xFFDC2626), size: 26),
                    SizedBox(width: 10),
                    Text(
                      'Privacidad y Términos 🔒',
                      style: TextStyle(
                        fontFamily: AppTypography.displayFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Contenido con Scroll
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildSection(
                  title: '1. Información que recopilamos',
                  body:
                      'En La Diabla App recopilamos los datos estrictamente necesarios para procesar tus pedidos de comida y realizar la entrega a tu puerta:\n'
                      '• Nombre y datos de contacto (correo electrónico y número de teléfono).\n'
                      '• Ubicación geográfica precisa (GPS) y dirección de entrega, utilizada únicamente mientras la app está activa o durante el despacho de un pedido en curso.\n'
                      '• Historial de pedidos y preferencias de platillos.',
                  isDark: isDark,
                ),
                _buildSection(
                  title: '2. Uso de la Información y Geolocalización',
                  body:
                      'La información recolectada se utiliza exclusivamente para:\n'
                      '• Asignar y despachar tu pedido al restaurante y al repartidor más cercano.\n'
                      '• Proporcionar seguimiento en tiempo real en el mapa interactivo de entrega.\n'
                      '• Enviar notificaciones sobre el estado de tu comida (preparando, en camino, entregado).\n'
                      '• Soporte al cliente directo vía WhatsApp y llamadas.',
                  isDark: isDark,
                ),
                _buildSection(
                  title: '3. Seguridad en Pagos y Pasarelas',
                  body:
                      'La Diabla App NO almacena contraseñas bancarias, tokens ni números completos de tarjetas de crédito o débito.\n'
                      'Todas las transacciones digitales (Tarjeta, PSE, Nequi y Daviplata) son procesadas de forma segura y encriptada a través de Mercado Pago Colombia bajo los estándares internacionales PCI-DSS.',
                  isDark: isDark,
                ),
                _buildSection(
                  title: '4. Eliminación de Datos y Derechos del Usuario',
                  body:
                      'De conformidad con las normativas de protección de datos (Habeas Data y políticas de Google Play Store), tienes derecho a:\n'
                      '• Acceder, actualizar o corregir tu información personal en cualquier momento.\n'
                      '• Solicitar la eliminación total y permanente de tu cuenta y datos asociados directamente desde el botón "Eliminar mi Cuenta" en la sección de Perfil.',
                  isDark: isDark,
                ),
                _buildSection(
                  title: '5. Contacto del Responsable de Datos',
                  body:
                      'La Diabla Comida Mexicana — Bucaramanga, Santander, Colombia.\n'
                      'WhatsApp Oficial de Soporte: +57 320 221 2856\n'
                      'Correo: soporte@ladiabla.app',
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    'Última actualización: Agosto 2026 • Versión 1.0.0',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.textMutedDark : Colors.grey.shade500,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),

          // Botón Entendido
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C1B14) : Colors.grey.shade50,
              border: Border(top: BorderSide(color: isDark ? AppColors.dividerDark : Colors.grey.shade200)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('ENTENDIDO Y ACEPTAR ✅', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required String body, required bool isDark}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13.5,
              color: isDark ? Colors.white : const Color(0xFF1E1712),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: isDark ? AppColors.textMutedDark : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
