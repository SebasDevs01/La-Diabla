// lib/core/widgets/diabla_bottom_nav.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la_diabla/app/theme/app_colors.dart';
import 'package:la_diabla/app/theme/app_responsive.dart';
import 'package:la_diabla/app/theme/app_typography.dart';
import 'package:la_diabla/features/assistant/presentation/screens/diabla_assistant_sheet.dart';

// ─── Mixin para shell navigation compartida ───────────────────────────────────

/// Widget que envuelve toda la scaffold adaptativa (bottom nav en phone,
/// NavigationRail en tablet) y expone el [navigationShell] como contenido.
class DiablaAdaptiveScaffold extends ConsumerWidget {
  const DiablaAdaptiveScaffold({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  static const List<_NavData> _items = [
    _NavData(icon: Icons.home_outlined,              activeIcon: Icons.home_rounded,                 label: 'Inicio',  index: 0),
    _NavData(icon: Icons.local_fire_department_outlined, activeIcon: Icons.local_fire_department_rounded, label: 'Menú',   index: 1),
    _NavData(icon: Icons.shopping_bag_outlined,       activeIcon: Icons.shopping_bag_rounded,         label: 'Pedidos', index: 3),
    _NavData(icon: Icons.person_outline_rounded,      activeIcon: Icons.person_rounded,               label: 'Perfil',  index: 4),
  ];

  void _onItemTapped(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTablet = AppResponsive.isTablet(context);

    if (isTablet) {
      return _TabletScaffold(
        navigationShell: navigationShell,
        items: _items,
        onItemTapped: _onItemTapped,
        currentIndex: navigationShell.currentIndex,
      );
    }

    return _PhoneScaffold(
      navigationShell: navigationShell,
      items: _items,
      onItemTapped: _onItemTapped,
      currentIndex: navigationShell.currentIndex,
    );
  }
}

// ─── Scaffold para teléfonos (bottom nav) ─────────────────────────────────────

class _PhoneScaffold extends StatelessWidget {
  const _PhoneScaffold({
    required this.navigationShell,
    required this.items,
    required this.onItemTapped,
    required this.currentIndex,
  });

  final StatefulNavigationShell navigationShell;
  final List<_NavData> items;
  final ValueChanged<int> onItemTapped;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DiablaBottomNav(
        navigationShell: navigationShell,
      ),
    );
  }
}

// ─── Scaffold para tablets (NavigationRail lateral) ───────────────────────────

class _TabletScaffold extends StatelessWidget {
  const _TabletScaffold({
    required this.navigationShell,
    required this.items,
    required this.onItemTapped,
    required this.currentIndex,
  });

  final StatefulNavigationShell navigationShell;
  final List<_NavData> items;
  final ValueChanged<int> onItemTapped;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLarge = AppResponsive.isTabletLarge(context);
    final bgColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final selectedColor = AppColors.primary;
    final unselectedColor = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return Scaffold(
      body: Row(
        children: [
          // ── NavigationRail lateral ──
          Container(
            decoration: BoxDecoration(
              color: bgColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 8,
                  offset: const Offset(2, 0),
                ),
              ],
            ),
            child: SafeArea(
              child: NavigationRail(
                extended: isLarge,
                minWidth: 72,
                minExtendedWidth: 200,
                backgroundColor: bgColor,
                selectedIndex: _railIndex(currentIndex),
                selectedIconTheme: IconThemeData(color: selectedColor, size: 26),
                unselectedIconTheme: IconThemeData(color: unselectedColor, size: 24),
                selectedLabelTextStyle: TextStyle(
                  fontFamily: AppTypography.bodyFamily,
                  color: selectedColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                unselectedLabelTextStyle: TextStyle(
                  fontFamily: AppTypography.bodyFamily,
                  color: unselectedColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
                onDestinationSelected: (railIdx) {
                  final appIdx = items[railIdx].index;
                  onItemTapped(appIdx);
                },
                // Botón Chile como leading
                leading: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: GestureDetector(
                    onTap: () => DiablaAssistantSheet.show(context),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/chileboton.png',
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                destinations: items.map((item) {
                  return NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.activeIcon),
                    label: Text(item.label),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    indicatorColor: selectedColor.withValues(alpha: 0.12),
                  );
                }).toList(),
              ),
            ),
          ),
          // ── Contenido principal ──
          Expanded(child: navigationShell),
        ],
      ),
    );
  }

  /// Convierte el índice de tab del router al índice del rail (sin el gap central).
  int _railIndex(int appIndex) {
    // items order: 0→Inicio, 1→Menú, 3→Pedidos, 4→Perfil
    // rail index:  0        1       2            3
    return items.indexWhere((e) => e.index == appIndex).clamp(0, items.length - 1);
  }
}

// ─── Bottom Nav (teléfono) — unchanged ───────────────────────────────────────

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

// ─── Datos de navegación ──────────────────────────────────────────────────────

class _NavData {
  const _NavData({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
}
