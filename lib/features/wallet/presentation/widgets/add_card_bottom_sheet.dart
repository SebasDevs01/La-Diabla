// lib/features/wallet/presentation/widgets/add_card_bottom_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../providers/wallet_provider.dart';

class AddCardBottomSheet extends ConsumerStatefulWidget {
  const AddCardBottomSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const AddCardBottomSheet(),
    );
  }

  @override
  ConsumerState<AddCardBottomSheet> createState() => _AddCardBottomSheetState();
}

class _AddCardBottomSheetState extends ConsumerState<AddCardBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _cardNumberCtrl = TextEditingController();
  final _holderNameCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();
  String _cardType = 'Débito';
  bool _isLoading = false;

  @override
  void dispose() {
    _cardNumberCtrl.dispose();
    _holderNameCtrl.dispose();
    _expiryCtrl.dispose();
    _cvvCtrl.dispose();
    super.dispose();
  }

  String _detectBrand(String number) {
    final clean = number.replaceAll(RegExp(r'\s+'), '');
    if (clean.startsWith('4')) return 'visa';
    if (clean.startsWith('5') || clean.startsWith('2')) return 'mastercard';
    if (clean.startsWith('3')) return 'amex';
    return 'visa';
  }

  Future<void> _submitCard() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final success = await ref.read(walletProvider.notifier).addCard(
          cardNumber: _cardNumberCtrl.text,
          holderName: _holderNameCtrl.text,
          expiryDate: _expiryCtrl.text,
          cvv: _cvvCtrl.text,
          cardType: _cardType,
        );

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 ¡Tarjeta vinculada exitosamente a tu billetera!'),
            backgroundColor: Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brand = _detectBrand(_cardNumberCtrl.text);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1410) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Título
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'AGREGAR TARJETA',
                    style: TextStyle(
                      fontFamily: AppTypography.displayFamily,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ─── VISTA PREVIA VISUAL DE LA TARJETA ────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: brand == 'visa'
                        ? [const Color(0xFF1A1F71), const Color(0xFF005691)]
                        : brand == 'mastercard'
                            ? [const Color(0xFFEB001B), const Color(0xFFF79E1B)]
                            : [const Color(0xFF1C2C4C), const Color(0xFF2C3E50)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(isDark ? 60 : 30),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _cardType.toUpperCase(),
                          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          brand.toUpperCase(),
                          style: const TextStyle(
                            fontFamily: AppTypography.displayFamily,
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _cardNumberCtrl.text.isEmpty
                          ? '•••• •••• •••• ••••'
                          : _cardNumberCtrl.text,
                      style: const TextStyle(
                        fontFamily: AppTypography.displayFamily,
                        color: Colors.white,
                        fontSize: 19,
                        letterSpacing: 2.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('TITULAR', style: TextStyle(color: Colors.white60, fontSize: 9.5)),
                            Text(
                              _holderNameCtrl.text.isEmpty ? 'NOMBRE EN LA TARJETA' : _holderNameCtrl.text.toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('EXPIRA', style: TextStyle(color: Colors.white60, fontSize: 9.5)),
                            Text(
                              _expiryCtrl.text.isEmpty ? 'MM/YY' : _expiryCtrl.text,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Selector Débito / Crédito
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Tarjeta Débito')),
                      selected: _cardType == 'Débito',
                      onSelected: (val) => setState(() => _cardType = 'Débito'),
                      selectedColor: const Color(0xFFDC2626),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _cardType == 'Débito' ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Tarjeta Crédito')),
                      selected: _cardType == 'Crédito',
                      onSelected: (val) => setState(() => _cardType = 'Crédito'),
                      selectedColor: const Color(0xFFDC2626),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _cardType == 'Crédito' ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Número de tarjeta
              TextFormField(
                controller: _cardNumberCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Número de tarjeta',
                  hintText: '4000 1234 5678 9010',
                  prefixIcon: const Icon(Icons.credit_card_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF261C16) : Colors.grey.shade50,
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) => (v == null || v.replaceAll(' ', '').length < 13) ? 'Ingresa un número válido' : null,
              ),
              const SizedBox(height: 12),

              // Nombre del titular
              TextFormField(
                controller: _holderNameCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Nombre del titular',
                  hintText: 'Como aparece en la tarjeta',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF261C16) : Colors.grey.shade50,
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa el nombre del titular' : null,
              ),
              const SizedBox(height: 12),

              // Vencimiento y CVV
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _expiryCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Vencimiento',
                        hintText: 'MM/YY',
                        prefixIcon: const Icon(Icons.calendar_today_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF261C16) : Colors.grey.shade50,
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) => (v == null || v.length < 4) ? 'MM/YY' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _cvvCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'CVV',
                        hintText: '123',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF261C16) : Colors.grey.shade50,
                      ),
                      validator: (v) => (v == null || v.length < 3) ? 'CVV' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Botón Guardar
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 2,
                  ),
                  onPressed: _isLoading ? null : _submitCard,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'GUARDAR Y VINCULAR TARJETA 💳',
                          style: TextStyle(
                            fontFamily: AppTypography.displayFamily,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
