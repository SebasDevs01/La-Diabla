// lib/features/menu/presentation/screens/menu_screen.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../domain/entities/category_entity.dart';
import '../../../../mock/mock_categories.dart';
import '../../../../mock/mock_products.dart';
import '../../../cart/providers/cart_notifier.dart';
import '../../../favorites/providers/favorites_provider.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/utils/price_formatter.dart';
import '../../../../core/widgets/cart_popup_helper.dart';
import '../../../../core/widgets/diabla_cart_badge_button.dart';
import '../../../../core/widgets/diabla_offline_view.dart';


class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key, this.categoryId});

  final String? categoryId;

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  late String _selectedCategoryId;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.categoryId ?? 'all';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? AppColors.textLight : AppColors.textDark;
    final subtitleColor = isDark ? AppColors.textMutedDark : const Color(0xFF6D4C41);

    final allCategories = [
      const CategoryEntity(
        id: 'all',
        name: 'Todos',
        imageUrl: '',
        order: 0,
        emoji: '🔥',
      ),
      ...mockCategories,
    ];

    final filteredProducts = mockProducts.where((p) {
      final matchesCategory =
          _selectedCategoryId == 'all' || p.categoryId == _selectedCategoryId;
      final matchesSearch = _searchQuery.isEmpty ||
          p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.description.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ─── HEADER CON DIABLO ARRIBA DERECHA ─────────────────────────────
            _buildHeader(context),

            // ─── BARRA DE BÚSQUEDA ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.cardDark : Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFEF4444), width: 1.4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withAlpha(isDark ? 10 : 16),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    const Icon(Icons.search_rounded, color: Color(0xFFDC2626), size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => _searchQuery = val),
                        style: TextStyle(
                          fontFamily: AppTypography.bodyFamily,
                          fontSize: 14,
                          color: textColor,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Buscar tacos, burritos, bebidas...',
                          hintStyle: TextStyle(
                            fontFamily: AppTypography.bodyFamily,
                            color: isDark ? AppColors.textMutedDark : Colors.grey,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          fillColor: Colors.transparent,
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),

            if (ref.watch(isOnlineProvider).value == false)
              Expanded(
                child: DiablaOfflineView(
                  title: 'Ups, algo salió mal.',
                  subtitle: 'Estamos en ello para resolverlo cuanto antes. Comprueba tu conexión a internet.',
                  onRetry: () => ref.refresh(isOnlineProvider),
                ),
              )
            else ...[
            // ─── CATEGORÍAS HORIZONTALES CON IMÁGENES ─────────────────────────
            SizedBox(
              height: 82,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: allCategories.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (ctx, index) {
                  final cat = allCategories[index];
                  final isSelected = cat.id == _selectedCategoryId;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategoryId = cat.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 78,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFDC2626)
                            : (isDark ? AppColors.cardDark : Colors.white),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFDC2626)
                              : (isDark ? AppColors.dividerDark : Colors.grey.shade200),
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isSelected
                                ? Colors.red.withAlpha(40)
                                : Colors.black.withAlpha(10),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (cat.localImage != null)
                            Image.asset(
                              cat.localImage!,
                              width: 40,
                              height: 40,
                              fit: BoxFit.contain,
                            )
                          else
                            Text(cat.iconEmoji, style: const TextStyle(fontSize: 26)),
                          const SizedBox(height: 4),
                          Text(
                            cat.name,
                            style: TextStyle(
                              fontFamily: AppTypography.bodyFamily,
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? AppColors.textLight : Colors.black87),
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // ─── SUBTÍTULO DE CATEGORÍA ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 6),
                      Text(
                        _selectedCategoryId == 'all'
                            ? 'TODOS'
                            : allCategories
                                .firstWhere((c) => c.id == _selectedCategoryId,
                                    orElse: () => allCategories.first)
                                .name
                                .toUpperCase(),
                        style: TextStyle(
                          fontFamily: AppTypography.displayFamily,
                          fontSize: 22,
                          color: textColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Los clásicos que nunca fallan',
                    style: TextStyle(
                      fontFamily: AppTypography.bodyFamily,
                      fontSize: 12,
                      color: subtitleColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ─── LISTA DE PRODUCTOS ────────────────────────────────────────────
            Expanded(
              child: filteredProducts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('🌶️', style: TextStyle(fontSize: 36)),
                          const SizedBox(height: 8),
                          const Text(
                            'No encontramos ese platillo',
                            style: TextStyle(
                              fontFamily: AppTypography.bodyFamily,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      itemCount: filteredProducts.length + 1, // +1 para banner al final
                      itemBuilder: (context, index) {
                        // Último ítem → banner ¿ANTOJO DIABÓLICO?
                        if (index == filteredProducts.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 16, bottom: 20),
                            child: _buildAntojoBanner(context),
                          );
                        }

                        final product = filteredProducts[index];
                        return _buildProductListTile(context, product);
                      },
                    ),
            ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── HEADER con título MENÚ y diablo parte de arriba ─────────────────────────
  Widget _buildHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.textLight : AppColors.textDark;
    final subtitleColor = isDark ? AppColors.textMutedDark : const Color(0xFF6D4C41);

    return Container(
      height: 150,
      padding: const EdgeInsets.only(left: 20, top: 8, bottom: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Texto izquierdo
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'MENÚ',
                  style: TextStyle(
                    fontFamily: AppTypography.displayFamily,
                    fontSize: 44,
                    color: textColor,
                    letterSpacing: 2,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Elige tu antojo\ny disfrútalo 🌶️',
                  style: TextStyle(
                    fontFamily: AppTypography.bodyFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: subtitleColor,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),

          // Diablo parte de arriba - derecha
          Positioned(
            right: 0,
            top: -20, // sobresale un poco arriba
            child: Image.asset(
              'assets/images/diablopartedearriba.png',
              height: 190,
              fit: BoxFit.contain,
            ),
          ),

          // Botón Carrito en esquina superior derecha
          const Positioned(
            right: 12,
            top: 4,
            child: DiablaCartBadgeButton(),
          ),
        ],
      ),
    );
  }

  // ─── PRODUCT LIST TILE (fila horizontal imagen + datos) ──────────────────────
  Widget _buildProductListTile(BuildContext context, dynamic product) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.textLight : AppColors.textDark;
    final bool isPopular = product.spicyLevel == 3 || mockProducts.indexOf(product) < 3;
    final bool isDiabla = product.spicyLevel == 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? (Theme.of(context).brightness == Brightness.dark ? AppColors.cardDark : Colors.white),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(Theme.of(context).brightness == Brightness.dark ? 30 : 18), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: InkWell(
        onTap: () => context.push('/product/${product.id}'),
        borderRadius: BorderRadius.circular(18),
        child: Row(
          children: [
            // Imagen cuadrada redondeada
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                bottomLeft: Radius.circular(18),
              ),
              child: CachedNetworkImage(
                imageUrl: product.imageUrl,
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorWidget: (ctx, url, err) => Container(
                  width: 100,
                  height: 100,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.fastfood, color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info del producto
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nombre + badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: TextStyle(
                              fontFamily: AppTypography.bodyFamily,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isPopular && !isDiabla)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B35),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'POPULAR',
                              style: TextStyle(
                                fontFamily: AppTypography.bodyFamily,
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        if (isDiabla)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '🔥 DIABLA',
                              style: TextStyle(
                                fontFamily: AppTypography.bodyFamily,
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      product.description,
                      style: TextStyle(
                        fontFamily: AppTypography.bodyFamily,
                        fontSize: 12,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.textMutedDark
                            : Colors.grey,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          PriceFormatter.formatSmart(product.price),
                          style: const TextStyle(
                            fontFamily: AppTypography.bodyFamily,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFDC2626),
                            fontSize: 15,
                          ),
                        ),
                        Row(
                          children: [
                            // Botón Favorito
                            GestureDetector(
                              onTap: () {
                                ref.read(favoritesProvider.notifier).toggleFavorite(product.id);
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: Icon(
                                  ref.watch(favoritesProvider).isFavorite(product.id)
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  color: const Color(0xFFDC2626),
                                  size: 22,
                                ),
                              ),
                            ),
                            // Botón + agregar al carrito
                            GestureDetector(
                              onTap: () async {
                                await ref.read(cartNotifierProvider.notifier).addItem(
                                      product: product,
                                      quantity: 1,
                                    );
                                if (context.mounted) {
                                  CartPopupHelper.showAddedToCart(
                                    context,
                                    product: product,
                                    quantity: 1,
                                  );
                                }
                              },
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFFDC2626), width: 1.5),
                                ),
                                child: const Icon(Icons.add, color: Color(0xFFDC2626), size: 18),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  // ─── BANNER ¿ANTOJO DIABÓLICO? ────────────────────────────────────────────────
  Widget _buildAntojoBanner(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        // Al tocar, muestra todos y sube al inicio
        setState(() {
          _selectedCategoryId = 'all';
          _searchController.clear();
          _searchQuery = '';
        });
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 35 : 18),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: 995 / 204,
            child: Image.asset(
              'assets/images/antojoextra.png',
              width: double.infinity,
              fit: BoxFit.fill,
              errorBuilder: (context, error, stackTrace) => const SizedBox(),
            ),
          ),
        ),
      ),
    );
  }
}
