// lib/core/widgets/diabla_app_bar.dart
import 'package:flutter/material.dart';
import 'package:la_diabla/app/theme/app_colors.dart';
import 'package:la_diabla/app/theme/app_typography.dart';

class DiablaAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DiablaAppBar({
    super.key,
    this.title,
    this.showBack = true,
    this.actions,
    this.centerTitle = true,
    this.backgroundColor,
  });

  final String? title;
  final bool showBack;
  final List<Widget>? actions;
  final bool centerTitle;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      centerTitle: centerTitle,
      leading: showBack && Navigator.canPop(context)
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.maybePop(context),
            )
          : null,
      title: title != null
          ? Text(
              title!,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontFamily: AppTypography.displayFamily,
                    fontSize: 24,
                    letterSpacing: 0.5,
                  ),
            )
          : const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'LA DIABLA',
                  style: TextStyle(
                    fontFamily: AppTypography.displayFamily,
                    fontSize: 24,
                    color: AppColors.primary,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(width: 4),
                Text('🌶️', style: TextStyle(fontSize: 18)),
              ],
            ),
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
