// lib/core/widgets/diabla_category_card.dart
import 'package:flutter/material.dart';
import 'package:la_diabla/app/theme/app_colors.dart';
import 'package:la_diabla/app/theme/app_responsive.dart';
import 'package:la_diabla/app/theme/app_typography.dart';
import 'package:la_diabla/domain/entities/category_entity.dart';

class DiablaCategoryCard extends StatelessWidget {
  const DiablaCategoryCard({
    super.key,
    required this.category,
    this.isSelected = false,
    this.onTap,
  });

  final CategoryEntity category;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final padH = AppResponsive.dp(context, 14);
    final padV = AppResponsive.dp(context, 8);
    final iconSize = AppResponsive.dp(context, 26);
    final fontSize = AppResponsive.sp(context, 13);
    final emojiSize = AppResponsive.sp(context, 18);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF1F2) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected ? Colors.red.withAlpha(25) : Colors.black.withAlpha(8),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (category.localImage != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  category.localImage!,
                  width: iconSize,
                  height: iconSize,
                  fit: BoxFit.contain,
                ),
              )
            else
              Text(
                category.iconEmoji,
                style: TextStyle(fontSize: emojiSize),
              ),
            SizedBox(width: AppResponsive.dp(context, 8)),
            Text(
              category.name,
              style: TextStyle(
                fontFamily: AppTypography.bodyFamily,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? AppColors.primary : Colors.black87,
                fontSize: fontSize,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
