// lib/core/widgets/diabla_product_card.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:la_diabla/app/theme/app_colors.dart';
import 'package:la_diabla/app/theme/app_responsive.dart';
import 'package:la_diabla/core/utils/price_formatter.dart';
import 'package:la_diabla/domain/entities/product_entity.dart';
import 'diabla_card.dart';

class DiablaProductCard extends StatelessWidget {
  const DiablaProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.onAddToCart,
    this.width = 200,
  });

  final ProductEntity product;
  final VoidCallback? onTap;
  final VoidCallback? onAddToCart;
  final double width;

  Widget _buildSpicyBadge(BuildContext context) {
    if (product.spicyLevel == 0) return const SizedBox.shrink();

    final spicyIcons = switch (product.spicyLevel) {
      1 => '🌶️',
      2 => '🌶️🌶️',
      3 => '🔥 DIABLA',
      _ => '',
    };

    final badgeColor = switch (product.spicyLevel) {
      1 => AppColors.spicyMild,
      2 => AppColors.spicyMedium,
      3 => AppColors.spicyDiabla,
      _ => AppColors.primary,
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppResponsive.dp(context, 6),
        vertical: AppResponsive.dp(context, 2),
      ),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        spicyIcons,
        style: TextStyle(
          color: Colors.white,
          fontSize: AppResponsive.sp(context, 9),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padH = AppResponsive.dp(context, 10);
    final padV = AppResponsive.dp(context, 8);
    final titleSize = AppResponsive.sp(context, 14);
    final descSize = AppResponsive.sp(context, 11);
    final priceSize = AppResponsive.sp(context, 15);
    final addIconSize = AppResponsive.dp(context, 16);

    return SizedBox(
      width: width,
      child: DiablaCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 1.45,
                  child: CachedNetworkImage(
                    imageUrl: product.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: AppColors.divider.withValues(alpha: 0.2),
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: AppColors.cardDark,
                      child: const Icon(Icons.fastfood, size: 36, color: AppColors.textMuted),
                    ),
                  ),
                ),
                if (product.spicyLevel > 0)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: _buildSpicyBadge(context),
                  ),
              ],
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: titleSize,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: descSize,
                        ),
                  ),
                  SizedBox(height: AppResponsive.dp(context, 8)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        PriceFormatter.formatSmart(product.price),
                        style: TextStyle(
                          fontSize: priceSize,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      InkWell(
                        onTap: onAddToCart,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: EdgeInsets.all(AppResponsive.dp(context, 6)),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.add,
                            color: Colors.white,
                            size: addIconSize,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
