// lib/features/wallet/presentation/screens/link_bancolombia_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../providers/wallet_provider.dart';

class LinkBancolombiaScreen extends ConsumerStatefulWidget {
  const LinkBancolombiaScreen({super.key});

  @override
  ConsumerState<LinkBancolombiaScreen> createState() => _LinkBancolombiaScreenState();
}

class _LinkBancolombiaScreenState extends ConsumerState<LinkBancolombiaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _docNumberController = TextEditingController();
  final _holderNameController = TextEditingController();
  final _emailController = TextEditingController();

  String _selectedDocType = 'CC';
  bool _isLoading = false;

  final List<String> _docTypes = ['CC', 'NIT', 'CE', 'PPN', 'TI'];

  @override
  void dispose() {
    _docNumberController.dispose();
    _holderNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleLinkBancolombia() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final success = await ref.read(walletProvider.notifier).linkBancolombia(
          docType: _selectedDocType,
          docNumber: _docNumberController.text.trim(),
          holderName: _holderNameController.text.trim().isNotEmpty
              ? _holderNameController.text.trim()
              : 'Cliente Bancolombia',
          email: _emailController.text.trim(),
        );

    setState(() => _isLoading = false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text('🏦 ¡Cuenta Bancolombia / PSE vinculada con éxito!'),
                ),
              ],
            ),
            backgroundColor: Color(0xFF009EE3),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No fue posible vincular Bancolombia. Intenta de nuevo.'),
            backgroundColor: Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.close_rounded,
            color: isDark ? Colors.white : Colors.black87,
            size: 26,
          ),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header con logo de Bancolombia / PSE
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDDA24),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.account_balance_rounded, color: Colors.black, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'Botón Bancolombia',
                      style: TextStyle(
                        fontFamily: AppTypography.displayFamily,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF1C1C1C),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Subtítulo
                Text(
                  'Ingresa tus datos para vincular tu cuenta:',
                  style: TextStyle(
                    fontFamily: AppTypography.bodyFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textLight : Colors.black87,
                  ),
                ),
                const SizedBox(height: 20),

                // 1. Tipo y Número de Documento (en fila)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tipo Documento
                    Container(
                      width: 95,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF261D17) : const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedDocType,
                          isExpanded: true,
                          dropdownColor: isDark ? const Color(0xFF261D17) : Colors.white,
                          items: _docTypes.map((t) {
                            return DropdownMenuItem(
                              value: t,
                              child: Text(
                                t,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _selectedDocType = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Número Documento
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF261D17) : const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
                          ),
                        ),
                        child: TextFormField(
                          controller: _docNumberController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                            fontFamily: AppTypography.bodyFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          validator: (v) =>
                              (v == null || v.trim().length < 5) ? 'Ingresa documento válido' : null,
                          decoration: InputDecoration(
                            labelText: 'Número de documento',
                            labelStyle: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 2. Nombre del Titular
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF261D17) : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
                    ),
                  ),
                  child: TextFormField(
                    controller: _holderNameController,
                    style: TextStyle(
                      fontFamily: AppTypography.bodyFamily,
                      fontSize: 14.5,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Ingresa el nombre del titular' : null,
                    decoration: InputDecoration(
                      labelText: 'Nombre completo del titular',
                      prefixIcon: const Icon(Icons.person_outline_rounded, color: Color(0xFF009EE3)),
                      labelStyle: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 3. Email para notificación
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF261D17) : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
                    ),
                  ),
                  child: TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(
                      fontFamily: AppTypography.bodyFamily,
                      fontSize: 14.5,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    validator: (v) =>
                        (v == null || !v.contains('@')) ? 'Ingresa un correo válido' : null,
                    decoration: InputDecoration(
                      labelText: 'Correo electrónico registrado en tu banco',
                      prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF009EE3)),
                      labelStyle: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Términos y condiciones
                Center(
                  child: Text(
                    'Al vincular tu cuenta, aceptas nuestros Términos de Servicio y la Política de Privacidad de Transferencias Bancolombia / PSE.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTypography.bodyFamily,
                      fontSize: 11.5,
                      color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Botón Vincular Bancolombia
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLinkBancolombia,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E1E1E),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade400,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Vincular Botón Bancolombia',
                                style: TextStyle(
                                  fontFamily: AppTypography.bodyFamily,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded, size: 18),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 24),

                // Footer de seguridad
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_rounded, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      'Transacción protegida por PSE y ACH Colombia',
                      style: TextStyle(
                        fontFamily: AppTypography.bodyFamily,
                        fontSize: 11,
                        color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
