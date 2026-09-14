// lib/core/widgets/diabla_button.dart
import 'package:flutter/material.dart';
import 'package:la_diabla/app/theme/app_colors.dart';
import 'package:la_diabla/app/theme/app_responsive.dart';
import 'package:la_diabla/app/theme/app_spacing.dart';

/// Botón principal con diseño audaz de La Diabla.
class DiablaButton extends StatelessWidget {
  const DiablaButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.backgroundColor = AppColors.primary,
    this.foregroundColor = AppColors.white,
    this.height,
    this.width,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final effectiveHeight = height ?? AppResponsive.buttonHeight(context);
    final iconSize = AppResponsive.dp(context, 20);
    final fontSize = AppResponsive.sp(context, 16);

    return SizedBox(
      width: width ?? double.infinity,
      height: effectiveHeight,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
        ),
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? SizedBox(
                height: iconSize,
                width: iconSize,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: iconSize),
                    SizedBox(width: AppResponsive.dp(context, AppSpacing.sm)),
                  ],
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: foregroundColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
