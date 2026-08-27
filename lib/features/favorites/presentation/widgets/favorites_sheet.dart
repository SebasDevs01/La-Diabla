// lib/features/favorites/presentation/widgets/favorites_sheet.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/utils/price_formatter.dart';
import '../../../../core/widgets/cart_popup_helper.dart';
import '../../../../core/widgets/diabla_offline_view.dart';
import '../../../../mock/mock_products.dart';
import '../../../cart/providers/cart_notifier.dart';
import '../../providers/favorites_provider.dart';

class FavoritesSheet extends ConsumerWidget {
  const FavoritesSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const FavoritesSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final favState = ref.watch(favoritesProvider);
    final favProducts = mockProducts.where((p) => favState.isFavorite(p.id)).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1712) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.favorite_rounded, color: Color(0xFFDC2626), size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'MIS FAVORITOS ❤️',
                      style: TextStyle(
                        fontFamily: AppTypography.displayFamily,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${favProducts.length} guardado${favProducts.length != 1 ? "s" : ""}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Lista de Favoritos
          Expanded(
            child: ref.watch(isOnlineProvider).value == false
                ? DiablaOfflineView(
                    title: 'Algo ocurrió',
                    subtitle: 'Hubo un error mientras cargábamos tus favoritos. Comprueba tu conexión a internet.',
                    onRetry: () => ref.refresh(isOnlineProvider),
                  )
                : favProducts.isEmpty
                    ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626).withAlpha(20),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.favorite_border_rounded, size: 54, color: Color(0xFFDC2626)),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Aún no tienes platillos favoritos',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Explora el menú y toca el corazón ❤️ en cualquier platillo para guardarlo y pedirlo fácilmente.',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            icon: const Icon(Icons.restaurant_menu_rounded, size: 18),
                            label: const Text('Ver el Menú 🔥', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () {
                              Navigator.pop(context);
                              context.go('/menu');
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: favProducts.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) {
                      final product = favProducts[i];
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF281E18) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(isDark ? 30 : 10),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Imagen
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: product.imageUrl,
                                width: 75,
                                height: 75,
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) => Container(
                                  width: 75,
                                  height: 75,
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.fastfood, color: Colors.grey),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    product.description,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    PriceFormatter.formatSmart(product.price),
                                    style: const TextStyle(
                                      fontFamily: AppTypography.displayFamily,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFFDC2626),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Acciones: Quitar favorito + Agregar al Carrito
                            Column(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.favorite_rounded, color: Color(0xFFDC2626), size: 22),
                                  tooltip: 'Quitar de favoritos',
                                  onPressed: () {
                                    ref.read(favoritesProvider.notifier).toggleFavorite(product.id);
                                  },
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFDC2626),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () async {
                                    await ref.read(cartNotifierProvider.notifier).addItem(
                                          product: product,
                                          quantity: 1,
                                        );
                                    if (ctx.mounted) {
                                      CartPopupHelper.showAddedToCart(
                                        ctx,
                                        product: product,
                                        quantity: 1,
                                      );
                                    }
                                  },
                                  child: const Text('+ Carrito', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
