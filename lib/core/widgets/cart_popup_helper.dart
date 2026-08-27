// lib/core/widgets/cart_popup_helper.dart
import 'package:flutter/material.dart';
import '../../app/router/app_router.dart';
import '../../app/theme/app_typography.dart';
import '../../domain/entities/product_entity.dart';

class CartPopupHelper {
  /// Muestra un Popup/SnackBar flotante ultra-estético con botón directo al Carrito.
  static void showAddedToCart(
    BuildContext context, {
    required ProductEntity product,
    int quantity = 1,
    VoidCallback? onViewCart,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context) ??
        (rootNavigatorKey.currentContext != null
            ? ScaffoldMessenger.maybeOf(rootNavigatorKey.currentContext!)
            : null);

    if (messenger == null) return;
    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        elevation: 10,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        padding: EdgeInsets.zero,
        duration: const Duration(seconds: 4),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1F1612), Color(0xFF120B08)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFDC2626).withAlpha(180),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFDC2626).withAlpha(60),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withAlpha(140),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icono / Imagen miniatura
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withAlpha(40),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFDC2626).withAlpha(100),
                    width: 1.2,
                  ),
                ),
                child: const Center(
                  child: Text(
                    '🌶️',
                    style: TextStyle(fontSize: 22),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Información del producto
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF4ADE80),
                          size: 14,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '¡AGREGADO AL CARRITO!',
                          style: TextStyle(
                            fontFamily: AppTypography.displayFamily,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                            color: Color(0xFF4ADE80),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${quantity > 1 ? "($quantity) " : ""}${product.name}',
                      style: const TextStyle(
                        fontFamily: AppTypography.bodyFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Botón llamativo "VER CARRITO"
              ElevatedButton(
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  if (onViewCart != null) {
                    onViewCart();
                  } else {
                    appRouter.go('/cart');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 4,
                  shadowColor: const Color(0xFFDC2626).withAlpha(120),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'VER CARRITO',
                      style: TextStyle(
                        fontFamily: AppTypography.bodyFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.shopping_bag_outlined, size: 14),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
