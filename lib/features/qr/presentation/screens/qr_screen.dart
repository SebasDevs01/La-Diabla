// lib/features/qr/presentation/screens/qr_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/services/deep_link_service.dart';
import '../../../../core/widgets/diabla_button.dart';
import '../../../../core/widgets/diabla_card.dart';

class QrScreen extends StatefulWidget {
  const QrScreen({super.key});

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  final _deepLinkService = DeepLinkService();
  final _urlController = TextEditingController(text: 'https://ladiabla.app/go?type=product&id=tacos_pastor');

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _handleSimulatedScan(String url) {
    final result = _deepLinkService.resolveUrl(url);
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Navegando a: ${result.path}')),
      );
      context.push(result.path);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Código QR o URL no válida de La Diabla')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ESCANEAR QR 📷')),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Visor simulado de escáner QR
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: AppColors.backgroundDark,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.primary, width: 3),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_scanner_rounded, size: 64, color: AppColors.primary),
                    SizedBox(height: 12),
                    Text(
                      'Apunta a un código QR de La Diabla',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Encuéntralos en empaques, flyers o promociones',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // Explicación y prueba de Deep Links
            DiablaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Prueba de QR / Deep Link',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Esta función permite que los clientes escaneen un código QR físico para abrir un producto o canjear una promo automáticamente.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'URL del QR escaneado',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DiablaButton(
                    text: 'Procesar QR / Link 🔗',
                    onPressed: () => _handleSimulatedScan(_urlController.text),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
