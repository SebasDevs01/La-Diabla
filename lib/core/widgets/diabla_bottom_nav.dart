// lib/core/widgets/diabla_bottom_nav.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la_diabla/app/theme/app_colors.dart';
import 'package:la_diabla/app/theme/app_typography.dart';
import 'package:la_diabla/features/assistant/presentation/screens/diabla_assistant_sheet.dart';

class DiablaBottomNav extends ConsumerWidget {
  const DiablaBottomNav({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  void _onItemTapped(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = navigationShell.currentIndex;

    const iconSize = 25.0;
    const labelStyle = TextStyle(
      fontFamily: AppTypography.bodyFamily,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              // Barra de navegación con los 4 ítems
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // 0 — Inicio
                  _NavItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home_rounded,
                    label: 'Inicio',
                    index: 0,
                    currentIndex: currentIndex,
                    onTap: _onItemTapped,
                    iconSize: iconSize,
                    labelStyle: labelStyle,
                  ),
                  // 1 — Menú (Ícono de llama / fuego)
                  _NavItem(
                    icon: Icons.local_fire_department_outlined,
                    activeIcon: Icons.local_fire_department_rounded,
                    label: 'Menu',
                    index: 1,
                    currentIndex: currentIndex,
                    onTap: _onItemTapped,
                    iconSize: iconSize,
                    labelStyle: labelStyle,
                  ),
                  // Espacio para el botón chile central
                  const SizedBox(width: 68),
                  // 3 — Pedidos (Ícono de bolsa de compras)
                  _NavItem(
                    icon: Icons.shopping_bag_outlined,
                    activeIcon: Icons.shopping_bag_rounded,
                    label: 'Pedidos',
                    index: 3,
                    currentIndex: currentIndex,
                    onTap: _onItemTapped,
                    iconSize: iconSize,
                    labelStyle: labelStyle,
                  ),
                  // 4 — Perfil
                  _NavItem(
                    icon: Icons.person_outline_rounded,
                    activeIcon: Icons.person_rounded,
                    label: 'Perfil',
                    index: 4,
                    currentIndex: currentIndex,
                    onTap: _onItemTapped,
                    iconSize: iconSize,
                    labelStyle: labelStyle,
                  ),
                ],
              ),

              // ─── Botón Chile Central (Asistente IA Adaptado) ──────────────────
              Positioned(
                top: -22,
                child: GestureDetector(
                  onTap: () => DiablaAssistantSheet.show(context),
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/chileboton.png',
                        width: 62,
                        height: 62,
                        fit: BoxFit.cover,
                      ),
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
    required this.iconSize,
    required this.labelStyle,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final double iconSize;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) {
    final isActive = index == currentIndex;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselectedColor = isDark ? AppColors.textMutedDark : AppColors.textMuted;
    final color = isActive ? const Color(0xFFDC2626) : unselectedColor;

    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: color,
              size: iconSize,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: labelStyle.copyWith(
                color: color,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
