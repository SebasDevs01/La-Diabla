// lib/features/menu/presentation/screens/product_detail_screen.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/router/app_router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/price_formatter.dart';
import '../../../../core/widgets/cart_popup_helper.dart';
import '../../../../core/widgets/diabla_button.dart';
import '../../../../mock/mock_products.dart';
import '../../../cart/providers/cart_notifier.dart';
import '../../../favorites/providers/favorites_provider.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  int _quantity = 1;
  final Set<String> _selectedExtraIds = {};
  final Set<String> _removedIngredients = {};
  final Map<String, String> _selectedOptions = {};
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Opciones por defecto para platillos especiales
    if (widget.productId == 'pina_colada') {
      _selectedOptions['Licor'] = 'Sin Licor (Virgen) 🥥';
    } else if (widget.productId == 'taco_salad') {
      _selectedOptions['Proteína'] = 'Pechuga de Pollo 🍗';
    } else if (widget.productId.contains('postobon_manzana') || widget.productId.contains('colombiana')) {
      _selectedOptions['Tamaño'] = 'Personal (400 ml) 🥤';
    } else if (widget.productId == 'jugo_del_valle') {
      _selectedOptions['Sabor'] = 'Mora 🫐';
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  double _calculateVariantExtraPrice() {
    double extra = 0.0;
    if (_selectedOptions['Licor'] == 'Con Ron Bacardí 🍹 (+ \$3.000)') {
      extra += 3000.0;
    }
    if (_selectedOptions['Proteína'] == 'Camarón Salteado 🍤 (+ \$4.000)') {
      extra += 4000.0;
    } else if (_selectedOptions['Proteína'] == 'Carne Asada 🥩 (+ \$3.000)') {
      extra += 3000.0;
    }
    if (_selectedOptions['Tamaño'] == '1.5 Litros 🍾 (+ \$4.000)') {
      extra += 4000.0;
    }
    return extra;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final product = mockProducts.firstWhere(
      (p) => p.id == widget.productId,
      orElse: () => mockProducts.first,
    );

    final selectedExtrasList = product.extras
        .where((extra) => _selectedExtraIds.contains(extra.id))
        .toList();

    double extrasTotal = 0.0;
    for (final extra in selectedExtrasList) {
      extrasTotal += extra.price;
    }
    final variantExtra = _calculateVariantExtraPrice();
    final unitPrice = product.price + extrasTotal + variantExtra;
    final totalPrice = unitPrice * _quantity;

    return Scaffold(
      backgroundColor: isDark ? AppColors.surfaceDark : const Color(0xFFFAF7F2),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: const Color(0xFFDC2626),
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: isDark ? Colors.black54 : Colors.white,
                child: IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : Colors.black87),
                  onPressed: () => context.pop(),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: CircleAvatar(
                  backgroundColor: isDark ? Colors.black54 : Colors.white,
                  child: IconButton(
                    icon: Icon(
                      ref.watch(favoritesProvider).isFavorite(product.id)
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: const Color(0xFFDC2626),
                    ),
                    onPressed: () {
                      ref.read(favoritesProvider.notifier).toggleFavorite(product.id);
                    },
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: CachedNetworkImage(
                imageUrl: product.imageUrl,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => Container(
                  color: const Color(0xFF1E1E1E),
                  child: const Center(child: Icon(Icons.fastfood_rounded, size: 80, color: Colors.orange)),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Título y Badge de Picante
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          style: TextStyle(
                            fontFamily: AppTypography.displayFamily,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFFFF5252) : const Color(0xFFC62828),
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      if (product.spicyLevel > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: product.spicyLevel == 3 ? const Color(0xFFDC2626) : const Color(0xFFFF9800),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            product.spicyLevel == 3 ? '🔥 DIABLA' : '🌶️ Nivel ${product.spicyLevel}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Precio Base
                  Text(
                    PriceFormatter.formatSmart(product.price),
                    style: TextStyle(
                      fontFamily: AppTypography.displayFamily,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: isDark ? AppColors.textLight : const Color(0xFF1E1E1E),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Descripción
                  Text(
                    product.description,
                    style: TextStyle(
                      fontFamily: AppTypography.bodyFamily,
                      fontSize: 13.5,
                      color: isDark ? AppColors.textMutedDark : const Color(0xFF5D4037),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ─── 1. OPCIONES ESPECIALES DE PRODUCTO (SI APLICA) ─────────
                  if (product.id == 'pina_colada') ...[
                    _buildSectionHeader('¿Cómo deseas tu Piña Colada? 🍍', isDark),
                    const SizedBox(height: 8),
                    _buildOptionSelector(
                      key: 'Licor',
                      options: [
                        'Sin Licor (Virgen) 🥥',
                        'Con Ron Bacardí 🍹 (+ \$3.000)',
                      ],
                      isDark: isDark,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  if (product.id == 'taco_salad') ...[
                    _buildSectionHeader('Elige tu Proteína Principal 🥩🍗🍤', isDark),
                    const SizedBox(height: 8),
                    _buildOptionSelector(
                      key: 'Proteína',
                      options: [
                        'Pechuga de Pollo 🍗',
                        'Carne Asada 🥩 (+ \$3.000)',
                        'Camarón Salteado 🍤 (+ \$4.000)',
                      ],
                      isDark: isDark,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  if (product.id.contains('postobon_manzana') || product.id.contains('colombiana')) ...[
                    _buildSectionHeader('Elige la Presentación 🍾', isDark),
                    const SizedBox(height: 8),
                    _buildOptionSelector(
                      key: 'Tamaño',
                      options: [
                        'Personal (400 ml) 🥤',
                        '1.5 Litros 🍾 (+ \$4.000)',
                      ],
                      isDark: isDark,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  if (product.id == 'jugo_del_valle') ...[
                    _buildSectionHeader('Elige el Sabor del Jugo 🧃', isDark),
                    const SizedBox(height: 8),
                    _buildOptionSelector(
                      key: 'Sabor',
                      options: [
                        'Mora 🫐',
                        'Mango 🥭',
                        'Naranja 🍊',
                        'Guayaba 🍈',
                        'Durazno 🍑',
                      ],
                      isDark: isDark,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  // ─── 2. PERSONALIZACIÓN DE INGREDIENTES BASE ────────────────
                  if (product.ingredients.isNotEmpty) ...[
                    _buildSectionHeader('Personaliza tus Ingredientes 🥗✂️', isDark),
                    const SizedBox(height: 4),
                    Text(
                      'Desmarca la casilla si deseas quitar algún ingrediente:',
                      style: TextStyle(
                        fontFamily: AppTypography.bodyFamily,
                        fontSize: 12.5,
                        color: isDark ? AppColors.textMutedDark : Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...product.ingredients.map((ing) {
                      final isRemoved = _removedIngredients.contains(ing);
                      final isIncluded = !isRemoved;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.cardDark : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isIncluded
                                ? (isDark ? AppColors.dividerDark : Colors.grey.shade300)
                                : const Color(0xFFEF5350),
                            width: 1.2,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            setState(() {
                              if (isIncluded) {
                                _removedIngredients.add(ing);
                              } else {
                                _removedIngredients.remove(ing);
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                // Cajita cuadrada de checkbox
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: isIncluded ? const Color(0xFFDC2626) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isIncluded ? const Color(0xFFDC2626) : Colors.grey.shade400,
                                      width: 2,
                                    ),
                                  ),
                                  child: isIncluded
                                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                                      : null,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isRemoved ? 'Sin $ing' : ing,
                                        style: TextStyle(
                                          fontFamily: AppTypography.bodyFamily,
                                          fontSize: 14,
                                          fontWeight: isIncluded ? FontWeight.w700 : FontWeight.w600,
                                          decoration: isRemoved ? TextDecoration.lineThrough : null,
                                          decorationColor: const Color(0xFFDC2626),
                                          decorationThickness: 2,
                                          color: isRemoved
                                              ? const Color(0xFFDC2626)
                                              : (isDark ? AppColors.textLight : const Color(0xFF1E1E1E)),
                                        ),
                                      ),
                                      Text(
                                        isIncluded ? 'Incluido en la preparación' : '❌ No incluir en esta orden',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isRemoved
                                              ? const Color(0xFFEF5350)
                                              : (isDark ? AppColors.textMutedDark : Colors.grey.shade600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  // ─── 3. EXTRAS OPCIONALES ───────────────────────────────────
                  if (product.extras.isNotEmpty) ...[
                    _buildSectionHeader('Agrega Extras Deliciosos 🧀🥑', isDark),
                    const SizedBox(height: 8),
                    ...product.extras.map((extra) {
                      final isSelected = _selectedExtraIds.contains(extra.id);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.cardDark : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFDC2626)
                                : (isDark ? AppColors.dividerDark : Colors.grey.shade200),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: CheckboxListTile(
                          value: isSelected,
                          title: Text(
                            extra.name,
                            style: TextStyle(
                              fontFamily: AppTypography.bodyFamily,
                              fontSize: 13.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '+ ${PriceFormatter.formatSmart(extra.price)}',
                            style: const TextStyle(
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          activeColor: const Color(0xFFDC2626),
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedExtraIds.add(extra.id);
                              } else {
                                _selectedExtraIds.remove(extra.id);
                              }
                            });
                          },
                        ),
                      );
                    }),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  // ─── 4. NOTAS ESPECIALES ───────────────────────────────────
                  _buildSectionHeader('Instrucciones Especiales 📝', isDark),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Ej. Salsa aparte, bien caliente, etc...',
                      hintStyle: TextStyle(
                        fontFamily: AppTypography.bodyFamily,
                        fontSize: 13,
                        color: isDark ? AppColors.textMutedDark : Colors.grey,
                      ),
                      filled: true,
                      fillColor: isDark ? AppColors.cardDark : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 50 : 20),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              // Contador de Cantidad
              Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.cardDark : Colors.grey.shade100,
                  border: Border.all(color: isDark ? AppColors.dividerDark : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_rounded, color: Color(0xFFDC2626)),
                      onPressed: () {
                        if (_quantity > 1) setState(() => _quantity--);
                      },
                    ),
                    Text(
                      '$_quantity',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_rounded, color: Color(0xFFDC2626)),
                      onPressed: () => setState(() => _quantity++),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              // Botón Agregar
              Expanded(
                child: DiablaButton(
                  text: 'Agregar • ${PriceFormatter.formatSmart(totalPrice)}',
                  onPressed: () async {
                    final notesText = _notesController.text.trim();
                    await ref.read(cartNotifierProvider.notifier).addItem(
                          product: product,
                          quantity: _quantity,
                          selectedExtras: selectedExtrasList,
                          removedIngredients: _removedIngredients.toList(),
                          selectedOptions: _selectedOptions,
                          notes: notesText.isEmpty ? null : notesText,
                        );

                    if (context.mounted) {
                      final navContext = rootNavigatorKey.currentContext ?? context;
                      context.pop();
                      CartPopupHelper.showAddedToCart(
                        navContext,
                        product: product,
                        quantity: _quantity,
                        onViewCart: () => appRouter.go('/cart'),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontFamily: AppTypography.displayFamily,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: isDark ? AppColors.textLight : const Color(0xFF1E1E1E),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildOptionSelector({
    required String key,
    required List<String> options,
    required bool isDark,
  }) {
    final currentVal = _selectedOptions[key] ?? options.first;
    return Column(
      children: options.map((opt) {
        final isSelected = currentVal == opt;
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedOptions[key] = opt;
            });
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark ? const Color(0xFF3E1F1F) : const Color(0xFFFFEBEE))
                  : (isDark ? AppColors.cardDark : Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? const Color(0xFFDC2626) : (isDark ? AppColors.dividerDark : Colors.grey.shade200),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: isSelected ? const Color(0xFFDC2626) : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    opt,
                    style: TextStyle(
                      fontFamily: AppTypography.bodyFamily,
                      fontSize: 13.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFFDC2626)
                          : (isDark ? AppColors.textLight : Colors.black87),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
