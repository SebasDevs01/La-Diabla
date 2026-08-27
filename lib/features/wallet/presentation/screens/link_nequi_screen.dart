// lib/features/wallet/presentation/screens/link_nequi_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../providers/wallet_provider.dart';

class LinkNequiScreen extends ConsumerStatefulWidget {
  const LinkNequiScreen({super.key});

  @override
  ConsumerState<LinkNequiScreen> createState() => _LinkNequiScreenState();
}

class _LinkNequiScreenState extends ConsumerState<LinkNequiScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _docNumberController = TextEditingController();

  String _selectedDocType = 'C.C.';
  bool _acceptedTerms = false;
  bool _isLoading = false;

  final List<String> _docTypes = ['C.C.', 'C.E.', 'Pasaporte', 'P.P.N.', 'T.I.'];

  @override
  void dispose() {
    _phoneController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _docNumberController.dispose();
    super.dispose();
  }

  Future<void> _handleLinkNequi() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes aceptar los Términos y Condiciones para vincular tu Nequi'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final fullName = '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}';
    final success = await ref.read(walletProvider.notifier).linkNequi(
          phone: _phoneController.text.trim(),
          holderName: fullName,
          email: _emailController.text.trim(),
          docType: _selectedDocType,
          docNumber: _docNumberController.text.trim(),
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
                  child: Text('🟣 ¡Cuenta Nequi vinculada exitosamente a tu billetera!'),
                ),
              ],
            ),
            backgroundColor: Color(0xFF7800FF),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No fue posible vincular tu cuenta Nequi. Intenta nuevamente.'),
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
      backgroundColor: isDark ? AppColors.surfaceDark : const Color(0xFFFAF7F2),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Título
                Text(
                  'Vincular cuenta Nequi',
                  style: TextStyle(
                    fontFamily: AppTypography.displayFamily,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1C1C1C),
                  ),
                ),
                const SizedBox(height: 20),

                // Banner de aviso de 15 minutos (estilo Rappi)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFDBA74), width: 1),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, color: Color(0xFFEA580C), size: 22),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Recuerda que debes aprobar tu cuenta en la App de Nequi durante los próximos 15 minutos.',
                          style: TextStyle(
                            fontFamily: AppTypography.bodyFamily,
                            fontSize: 13,
                            color: Color(0xFF9A3412),
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 1. Número de celular asociado a Nequi
                _buildInputField(
                  controller: _phoneController,
                  label: 'Número de celular asociado a Nequi',
                  icon: Icons.phone_android_rounded,
                  keyboardType: TextInputType.phone,
                  isDark: isDark,
                  validator: (v) {
                    if (v == null || v.trim().length < 10) {
                      return 'Ingresa un número de celular válido de 10 dígitos';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 2. Nombre y Apellido
                Row(
                  children: [
                    Expanded(
                      child: _buildInputField(
                        controller: _firstNameController,
                        label: 'Nombre',
                        icon: Icons.person_outline_rounded,
                        isDark: isDark,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInputField(
                        controller: _lastNameController,
                        label: 'Apellido',
                        icon: Icons.person_outline_rounded,
                        isDark: isDark,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 3. Email asociado a Nequi
                _buildInputField(
                  controller: _emailController,
                  label: 'Email asociado a Nequi',
                  icon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                  isDark: isDark,
                  validator: (v) {
                    if (v == null || !v.contains('@')) {
                      return 'Ingresa un correo electrónico válido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 4. Tipo de documento
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF261D17) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedDocType,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      dropdownColor: isDark ? const Color(0xFF261D17) : Colors.white,
                      items: _docTypes.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Row(
                            children: [
                              const Icon(Icons.badge_outlined, size: 20, color: Color(0xFF7800FF)),
                              const SizedBox(width: 12),
                              Text(
                                'Tipo: $type',
                                style: TextStyle(
                                  fontFamily: AppTypography.bodyFamily,
                                  fontSize: 14,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedDocType = v);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 5. Número de identificación
                _buildInputField(
                  controller: _docNumberController,
                  label: 'Número de identificación',
                  icon: Icons.pin_outlined,
                  keyboardType: TextInputType.number,
                  isDark: isDark,
                  validator: (v) => (v == null || v.trim().length < 5) ? 'Ingresa tu documento' : null,
                ),
                const SizedBox(height: 20),

                // 6. Checkbox Términos y Condiciones
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: _acceptedTerms,
                      activeColor: const Color(0xFF7800FF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
                    ),
                    const Expanded(
                      child: Text(
                        'Debes aceptar Términos y Condiciones',
                        style: TextStyle(
                          fontFamily: AppTypography.bodyFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Botón Vincular cuenta
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLinkNequi,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7800FF),
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
                        : const Text(
                            'Vincular cuenta',
                            style: TextStyle(
                              fontFamily: AppTypography.bodyFamily,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF261D17) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
        ),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        style: TextStyle(
          fontFamily: AppTypography.bodyFamily,
          fontSize: 14.5,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            fontSize: 13,
            color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
          ),
          prefixIcon: Icon(icon, color: const Color(0xFF7800FF), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}
