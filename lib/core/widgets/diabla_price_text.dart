// lib/core/widgets/diabla_price_text.dart
import 'package:flutter/material.dart';
import 'package:la_diabla/app/theme/app_colors.dart';
import 'package:la_diabla/core/utils/price_formatter.dart';

class DiablaPriceText extends StatelessWidget {
  const DiablaPriceText({
    super.key,
    required this.price,
    this.style,
    this.color = AppColors.primary,
    this.fontSize = 18,
    this.fontWeight = FontWeight.w900,
  });

  final double price;
  final TextStyle? style;
  final Color color;
  final double fontSize;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    return Text(
      PriceFormatter.formatSmart(price),
      style: style ??
          TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: fontWeight,
          ),
    );
  }
}
