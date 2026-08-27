// lib/features/home/presentation/screens/home_screen.dart
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../domain/entities/product_entity.dart';
import '../../../../mock/mock_categories.dart';
import '../../../../mock/mock_products.dart';
import '../../../cart/providers/cart_notifier.dart';
import '../../../favorites/providers/favorites_provider.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/utils/price_formatter.dart';
import '../../../../core/widgets/cart_popup_helper.dart';
import '../../../../core/widgets/diabla_cart_badge_button.dart';
import '../../../../core/widgets/diabla_offline_view.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _selectedCategoryId;
  final _searchController = TextEditingController();

  double _minPrice = 0;
  double _maxPrice = 50000;
  String _sortBy = 'popular';

  // Banner Carousel State
  late final PageController _bannerPageController;
  int _currentBannerIndex = 0;
  Timer? _bannerTimer;

  final List<String> _bannerImages = [
    'assets/images/bannerenvio.png',
    'assets/images/antojoextra2.png',
    'assets/images/enviofree2.png',
  ];

  bool get _hasActiveFilters =>
      _searchController.text.trim().isNotEmpty ||
      _selectedCategoryId != null ||
      _minPrice > 0 ||
      _maxPrice < 50000 ||
      _sortBy != 'popular';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {});
    });

    _bannerPageController = PageController();
    _startBannerTimer();
    // Mostrar cupón primer pedido si es nuevo usuario
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirstLoginCoupon());
  }

  /// Verifica si el usuario es nuevo (nunca ha iniciado sesión antes).
  /// El cupón DIABLAFREE solo se muestra y es redimible 1 vez por cuenta.
  Future<void> _checkFirstLoginCoupon() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final couponShown = prefs.getBool('diabla_free_coupon_shown') ?? false;
    if (!couponShown) {
      // Marcar que ya se mostró — no se volverá a mostrar
      await prefs.setBool('diabla_free_coupon_shown', true);
      if (mounted) {
        _showFreeDeliveryCouponDialog(context);
      }
    }
  }

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_bannerPageController.hasClients) {
        final nextIndex = (_currentBannerIndex + 1) % _bannerImages.length;
        _bannerPageController.animateToPage(
          nextIndex,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerPageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<ProductEntity> get _filteredProducts {
    final query = _searchController.text.trim().toLowerCase();
    var list = mockProducts.where((p) {
      final matchesCategory =
          _selectedCategoryId == null || p.categoryId == _selectedCategoryId;
      final matchesQuery = query.isEmpty ||
          p.name.toLowerCase().contains(query) ||
          p.description.toLowerCase().contains(query);
      final matchesPrice = p.price >= _minPrice && p.price <= _maxPrice;
      return matchesCategory && matchesQuery && matchesPrice;
    }).toList();

    if (_sortBy == 'price_asc') {
      list.sort((a, b) => a.price.compareTo(b.price));
    } else if (_sortBy == 'price_desc') {
      list.sort((a, b) => b.price.compareTo(a.price));
    } else {
      list.sort(
          (a, b) => mockProducts.indexOf(a).compareTo(mockProducts.indexOf(b)));
    }
    return list;
  }

  void _clearFilters() {
    setState(() {
      _selectedCategoryId = null;
      _searchController.clear();
      _minPrice = 0;
      _maxPrice = 50000;
      _sortBy = 'popular';
    });
  }

  void _onBannerTapped(int index) {
    if (index == 0 || index == 1) {
      // bannerenvio o antojoextra -> Ir al menú
      context.go('/menu');
    } else if (index == 2) {
      // primerpedidoenviofree -> Modal especial de cupón bienvenida
      _showFreeDeliveryCouponDialog(context);
    }
  }

  void _showFreeDeliveryCouponDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: isDark ? AppColors.cardDark : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo La Diabla como ícono del cupón
                Image.asset(
                  'assets/images/logo_diabla_cupon.png',
                  height: 90,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 10),

                // Título
                Text(
                  '¡ENVÍO GRATIS!',
                  style: TextStyle(
                    fontFamily: AppTypography.displayFamily,
                    fontSize: 28,
                    color: isDark ? const Color(0xFFFF5252) : const Color(0xFFC62828),
                    letterSpacing: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),

                Text(
                  '¡Bienvenido a La Diabla! 🎉\nTu primer pedido tiene\nenvío 100% GRATIS.',
                  style: TextStyle(
                    fontFamily: AppTypography.bodyFamily,
                    fontSize: 14,
                    color: isDark ? AppColors.textLight : AppColors.textDark,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Tarjeta de Cupón con borde punteado premium
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? AppColors.dividerDark : Colors.red.shade200,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'TU CUPÓN DE PRIMER PEDIDO',
                        style: TextStyle(
                          fontFamily: AppTypography.bodyFamily,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.textMutedDark : Colors.grey,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'DIABLAFREE',
                        style: TextStyle(
                          fontFamily: AppTypography.displayFamily,
                          fontSize: 26,
                          color: isDark ? const Color(0xFFFF5252) : const Color(0xFFDC2626),
                          letterSpacing: 2.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '⚡ Válido solo en tu primer pedido · 1 uso',
                        style: TextStyle(
                          fontFamily: AppTypography.bodyFamily,
                          fontSize: 10,
                          color: isDark ? AppColors.textMutedDark : Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Botón Aplicar
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      elevation: 4,
                    ),
                    onPressed: () async {
                      Navigator.pop(dialogCtx);
                      // Marcar y aplicar cupón
                      await ref.read(cartNotifierProvider.notifier).applyCoupon('DIABLAFREE');
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('🛵 ¡Cupón DIABLAFREE aplicado! Envío gratis activado.'),
                          backgroundColor: AppColors.secondary,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                      context.go('/menu');
                    },
                    child: const Text(
                      '¡APLICAR Y VER MENÚ!',
                      style: TextStyle(
                        fontFamily: AppTypography.displayFamily,
                        fontSize: 18,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Botón cerrar
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text(
                    'Quizás después',
                    style: TextStyle(
                      fontFamily: AppTypography.bodyFamily,
                      fontSize: 13,
                      color: isDark ? AppColors.textMutedDark : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFilterSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    double tempMin = _minPrice;
    double tempMax = _maxPrice;
    String tempSort = _sortBy;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.dividerDark
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'FILTRAR Y ORDENAR',
                    style: TextStyle(
                      fontFamily: AppTypography.displayFamily,
                      fontSize: 22,
                      color: const Color(0xFFDC2626),
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Rango de Precio',
                    style: TextStyle(
                      fontFamily: AppTypography.bodyFamily,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: isDark ? AppColors.textLight : AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(PriceFormatter.formatSmart(tempMin),
                          style: const TextStyle(
                              fontFamily: AppTypography.bodyFamily,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFDC2626),
                              fontSize: 14)),
                      Text(PriceFormatter.formatSmart(tempMax),
                          style: const TextStyle(
                              fontFamily: AppTypography.bodyFamily,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFDC2626),
                              fontSize: 14)),
                    ],
                  ),
                  RangeSlider(
                    values: RangeValues(tempMin, tempMax),
                    min: 0,
                    max: 50000,
                    divisions: 50,
                    activeColor: const Color(0xFFDC2626),
                    inactiveColor: Colors.red.shade100,
                    onChanged: (v) =>
                        setSheet(() { tempMin = v.start; tempMax = v.end; }),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ordenar por',
                    style: TextStyle(
                      fontFamily: AppTypography.bodyFamily,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: isDark ? AppColors.textLight : AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    children: [
                      _sortChip('popular', '🔥 Populares', tempSort, isDark,
                          (v) => setSheet(() => tempSort = v)),
                      _sortChip('price_asc', '⬆️ Menor precio', tempSort,
                          isDark, (v) => setSheet(() => tempSort = v)),
                      _sortChip('price_desc', '⬇️ Mayor precio', tempSort,
                          isDark, (v) => setSheet(() => tempSort = v)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setSheet(() {
                              tempMin = 0;
                              tempMax = 50000;
                              tempSort = 'popular';
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFDC2626)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Limpiar',
                              style: TextStyle(
                                  color: Color(0xFFDC2626),
                                  fontFamily: AppTypography.bodyFamily,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _minPrice = tempMin;
                              _maxPrice = tempMax;
                              _sortBy = tempSort;
                            });
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                          ),
                          child: const Text('Aplicar',
                              style: TextStyle(
                                  fontFamily: AppTypography.bodyFamily,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _sortChip(String value, String label, String currentSort, bool isDark,
      ValueChanged<String> onSelected) {
    final isSelected = currentSort == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(value),
      selectedColor: const Color(0xFFDC2626),
      backgroundColor: isDark ? AppColors.cardDark : Colors.grey.shade100,
      labelStyle: TextStyle(
        fontFamily: AppTypography.bodyFamily,
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: isSelected
            ? Colors.white
            : (isDark ? AppColors.textLight : AppColors.textDark),
      ),
      side: BorderSide(
        color: isSelected
            ? const Color(0xFFDC2626)
            : (isDark ? AppColors.dividerDark : Colors.grey.shade300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final products = _filteredProducts;

    final cardColor = isDark ? AppColors.cardDark : Colors.white;
    final textColor = isDark ? AppColors.textLight : AppColors.textDark;
    final subtitleColor =
        isDark ? AppColors.textMutedDark : const Color(0xFF6D4C41);
    final searchBgColor = isDark ? AppColors.cardDark : Colors.white;
    final searchBorderColor =
        isDark ? AppColors.dividerDark : const Color(0xFFDC2626);

    // Color de fondo sólido para Home (sin imagen decorativa)
    final homeBg = isDark ? AppColors.surfaceDark : const Color(0xFFF9F9F9);

    return Scaffold(
      backgroundColor: homeBg,
      body: Stack(
        children: [

          // ─── CONTENIDO ───────────────────────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── 1. HEADER ────────────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.cardDark : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(isDark ? 30 : 10),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: IconButton(
                                  icon: const Icon(Icons.notifications_none_rounded,
                                      color: Color(0xFFDC2626), size: 22),
                                  onPressed: () => context.push('/notifications'),
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const DiablaCartBadgeButton(),
                          ],
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '¡BIENVENIDO\nA LA DIABLA!',
                                    style: TextStyle(
                                      fontFamily: AppTypography.displayFamily,
                                      fontSize: 34,
                                      fontWeight: FontWeight.w400,
                                      color: isDark ? const Color(0xFFFF5252) : const Color(0xFFC62828),
                                      height: 1.05,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'El sabor que\nte acompaña 🌶️',
                                    style: TextStyle(
                                      fontFamily: AppTypography.bodyFamily,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: subtitleColor,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Image.asset(
                              'assets/images/logo.png',
                              height: 180,
                              fit: BoxFit.contain,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Si no hay conexión a internet, mostrar estado offline limpio estilo Rappi
                  if (ref.watch(isOnlineProvider).value == false) ...[
                    const SizedBox(height: 40),
                    DiablaOfflineView(
                      title: 'Ups, algo salió mal.',
                      subtitle: 'Estamos en ello para resolverlo cuanto antes. Comprueba tu conexión a internet.',
                      onRetry: () => ref.refresh(isOnlineProvider),
                    ),
                  ] else ...[

                  // ─── 2. BARRA DE BÚSQUEDA ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: searchBgColor,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: searchBorderColor, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withAlpha(isDark ? 10 : 20),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 14),
                          const Icon(Icons.search_rounded,
                              color: Color(0xFFDC2626), size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: TextStyle(
                                fontFamily: AppTypography.bodyFamily,
                                fontSize: 14,
                                color: textColor,
                              ),
                              decoration: InputDecoration(
                                hintText: '¿Qué se te antoja hoy?',
                                hintStyle: TextStyle(
                                  fontFamily: AppTypography.bodyFamily,
                                  color: isDark
                                      ? AppColors.textMutedDark
                                      : Colors.grey,
                                  fontSize: 14,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                fillColor: Colors.transparent,
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.close_rounded,
                                            size: 18,
                                            color: isDark
                                                ? AppColors.textMutedDark
                                                : Colors.grey),
                                        onPressed: () =>
                                            _searchController.clear(),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _showFilterSheet(context),
                            child: Container(
                              margin: const EdgeInsets.all(5),
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFFDC2626),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(Icons.tune_rounded,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ─── 3. CATEGORÍAS ────────────────────────────────────────────────
                  SizedBox(
                    height: 104,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: mockCategories.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final cat = mockCategories[index];
                        final isSelected = _selectedCategoryId == cat.id;

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedCategoryId =
                                  isSelected ? null : cat.id;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 82,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFFFECEE)
                                  : cardColor,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFFDC2626)
                                    : (isDark
                                        ? AppColors.dividerDark
                                        : Colors.grey.shade200),
                                width: isSelected ? 2 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: isSelected
                                      ? Colors.red.withAlpha(30)
                                      : Colors.black.withAlpha(10),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: cat.localImage != null
                                      ? Image.asset(cat.localImage!,
                                          width: 52,
                                          height: 52,
                                          fit: BoxFit.contain)
                                      : Text(cat.iconEmoji,
                                          style:
                                              const TextStyle(fontSize: 30)),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  cat.name,
                                  style: TextStyle(
                                    fontFamily: AppTypography.bodyFamily,
                                    fontSize: 11,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: isSelected
                                        ? const Color(0xFFDC2626)
                                        : (isDark
                                            ? AppColors.textLight
                                            : Colors.black87),
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

                  const SizedBox(height: 18),

                  // ─── 4. BANNER CAROUSEL (Rotación cada 10 seg) ────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: 1280 / 465, // Exact 1280x465 px
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(isDark ? 35 : 20),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: PageView.builder(
                                controller: _bannerPageController,
                                itemCount: _bannerImages.length,
                                onPageChanged: (index) {
                                  setState(() {
                                    _currentBannerIndex = index;
                                  });
                                },
                                itemBuilder: (context, index) {
                                  return GestureDetector(
                                    onTap: () => _onBannerTapped(index),
                                    child: Image.asset(
                                      _bannerImages[index],
                                      width: double.infinity,
                                      height: double.infinity,
                                      fit: BoxFit.fill,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_bannerImages.length, (index) {
                            final isCurrent = index == _currentBannerIndex;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              width: isCurrent ? 18 : 6,
                              height: 6,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? const Color(0xFFDC2626)
                                    : (isDark
                                        ? AppColors.dividerDark
                                        : Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ─── 5. POPULARES / FILTRADOS ─────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              _selectedCategoryId != null
                                  ? '${mockCategories.firstWhere((c) => c.id == _selectedCategoryId, orElse: () => mockCategories.first).name.toUpperCase()} 🔥'
                                  : 'POPULARES 🔥',
                              style: TextStyle(
                                fontFamily: AppTypography.displayFamily,
                                fontSize: 22,
                                fontWeight: FontWeight.w400,
                                color: textColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                            if (_hasActiveFilters) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _clearFilters,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.cardDark
                                        : Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: const Color(0xFFDC2626)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.close_rounded,
                                          size: 12,
                                          color: Color(0xFFDC2626)),
                                      SizedBox(width: 3),
                                      Text(
                                        'Limpiar',
                                        style: TextStyle(
                                          fontFamily: AppTypography.bodyFamily,
                                          fontSize: 11,
                                          color: Color(0xFFDC2626),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        TextButton(
                          onPressed: () => context.go('/menu'),
                          child: Row(
                            children: [
                              Text(
                                'Ver más ',
                                style: TextStyle(
                                  color: const Color(0xFFDC2626),
                                  fontFamily: AppTypography.bodyFamily,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: Color(0xFFDC2626), size: 18),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Lista de productos
                  if (products.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 36, horizontal: 20),
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        children: [
                          const Text('🌶️',
                              style: TextStyle(fontSize: 36)),
                          const SizedBox(height: 8),
                          Text(
                            'No encontramos platillos con esos filtros',
                            style: TextStyle(
                              fontFamily: AppTypography.bodyFamily,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: textColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _clearFilters,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                            ),
                            child: const Text(
                                'Mostrar todos los platillos'),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      height: 230,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: products.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 14),
                        itemBuilder: (context, index) {
                          final product = products[index];
                          return GestureDetector(
                            onTap: () =>
                                context.push('/product/${product.id}'),
                            child: Container(
                              width: 165,
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black
                                          .withAlpha(isDark ? 30 : 18),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3)),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: const BorderRadius.vertical(
                                            top: Radius.circular(18)),
                                        child: CachedNetworkImage(
                                          imageUrl: product.imageUrl,
                                          height: 115,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) => Container(
                                            color: Colors.grey.shade100,
                                            child: const Center(
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Color(0xFFDC2626),
                                              ),
                                            ),
                                          ),
                                          errorWidget: (context, url, error) =>
                                              Container(
                                            color: Colors.grey.shade200,
                                            child: const Center(
                                              child: Icon(Icons.fastfood,
                                                  size: 36,
                                                  color: Colors.grey),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 6,
                                        right: 6,
                                        child: GestureDetector(
                                          onTap: () {
                                            ref.read(favoritesProvider.notifier).toggleFavorite(product.id);
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(5),
                                            decoration: BoxDecoration(
                                              color: isDark ? Colors.black54 : Colors.white.withAlpha(220),
                                              shape: BoxShape.circle,
                                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                            ),
                                            child: Icon(
                                              ref.watch(favoritesProvider).isFavorite(product.id)
                                                  ? Icons.favorite_rounded
                                                  : Icons.favorite_border_rounded,
                                              color: const Color(0xFFDC2626),
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product.name,
                                          style: TextStyle(
                                            fontFamily:
                                                AppTypography.bodyFamily,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: textColor,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '\$${product.price.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontFamily:
                                                    AppTypography.bodyFamily,
                                                fontWeight: FontWeight.w900,
                                                color: Color(0xFFDC2626),
                                                fontSize: 14,
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () async {
                                                await ref
                                                    .read(cartNotifierProvider
                                                        .notifier)
                                                    .addItem(
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
                                                padding:
                                                    const EdgeInsets.all(5),
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                      color: const Color(
                                                          0xFFDC2626),
                                                      width: 1.5),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.add,
                                                  color: Color(0xFFDC2626),
                                                  size: 16,
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
                        },
                      ),
                    ),
                  const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
