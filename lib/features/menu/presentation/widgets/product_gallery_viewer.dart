// lib/features/menu/presentation/widgets/product_gallery_viewer.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../app/theme/app_typography.dart';

/// Visor de pantalla completa tipo Lightbox para ver todas las fotos de un platillo.
/// Soporta:
/// 1. Deslizamiento sin dar clic: Gestos táctiles libres (swipe / drag horizontal).
/// 2. Deslizamiento dando clic: Botones laterales (< y >) y miniaturas inferiores clicables.
/// 3. Zoom táctil: Pinch-to-zoom y doble toque en cada fotografía.
class ProductGalleryViewer extends StatefulWidget {
  const ProductGalleryViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
    required this.productName,
  });

  final List<String> images;
  final int initialIndex;
  final String productName;

  static Future<void> show(
    BuildContext context, {
    required List<String> images,
    int initialIndex = 0,
    required String productName,
  }) {
    if (images.isEmpty) return Future.value();
    return showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(240),
      useSafeArea: false,
      builder: (_) => ProductGalleryViewer(
        images: images,
        initialIndex: initialIndex,
        productName: productName,
      ),
    );
  }

  @override
  State<ProductGalleryViewer> createState() => _ProductGalleryViewerState();
}

class _ProductGalleryViewerState extends State<ProductGalleryViewer> {
  late PageController _pageController;
  late ScrollController _thumbScrollController;
  late int _currentIndex;
  final TransformationController _transformController = TransformationController();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.images.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _thumbScrollController = ScrollController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _thumbScrollController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
    _transformController.value = Matrix4.identity();
    _scrollToThumb(index);
  }

  void _scrollToThumb(int index) {
    if (!_thumbScrollController.hasClients) return;
    const itemWidth = 66.0; // 56px ancho + 10px margen
    final targetOffset = (index * itemWidth) - (MediaQuery.of(context).size.width / 2) + (itemWidth / 2);
    _thumbScrollController.animateTo(
      targetOffset.clamp(0.0, _thumbScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      // Loop al final si se desea
      _pageController.animateToPage(
        widget.images.length - 1,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _goToNext() {
    if (_currentIndex < widget.images.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      // Loop al inicio si se desea
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _jumpTo(int index) {
    if (index == _currentIndex) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiple = widget.images.length > 1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ─── 1. PageView Principal (Deslizamiento táctil "sin dar clic") ────
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: _onPageChanged,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              final url = widget.images[index];
              return Center(
                child: InteractiveViewer(
                  transformationController: _transformController,
                  minScale: 1.0,
                  maxScale: 4.0,
                  clipBehavior: Clip.none,
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFDC2626),
                        strokeWidth: 2,
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: const Color(0xFF1E1E1E),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image_rounded, size: 64, color: Colors.grey),
                          SizedBox(height: 8),
                          Text('No se pudo cargar la foto', style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // ─── 2. Botones de Clic Laterales ("dando clic" < y >) ──────────────
          if (hasMultiple) ...[
            // Flecha Izquierda (Anterior)
            Positioned(
              left: 14,
              top: 0,
              bottom: 120,
              child: Center(
                child: Material(
                  color: Colors.black.withAlpha(160),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    iconSize: 28,
                    padding: const EdgeInsets.all(12),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                    tooltip: 'Foto anterior',
                    onPressed: _goToPrevious,
                  ),
                ),
              ),
            ),

            // Flecha Derecha (Siguiente)
            Positioned(
              right: 14,
              top: 0,
              bottom: 120,
              child: Center(
                child: Material(
                  color: Colors.black.withAlpha(160),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    iconSize: 28,
                    padding: const EdgeInsets.all(12),
                    icon: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white),
                    tooltip: 'Foto siguiente',
                    onPressed: _goToNext,
                  ),
                ),
              ),
            ),
          ],

          // ─── 3. Barra Superior (Cerrar, Título, Contador) ───────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withAlpha(200),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    // Botón Cerrar
                    Material(
                      color: Colors.white.withAlpha(40),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Nombre del Platillo
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.productName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppTypography.displayFamily,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            hasMultiple
                                ? 'Desliza o toca las flechas para navegar'
                                : 'Pellizca con 2 dedos para hacer zoom',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withAlpha(180),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Badge Contador de Fotos (ej: "2 / 4")
                    if (hasMultiple)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFDC2626).withAlpha(100),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          '${_currentIndex + 1} / ${widget.images.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ─── 4. Barra Inferior con Miniaturas Clicables ─────────────────────
          if (hasMultiple)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Container(
                  height: 96,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withAlpha(220),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: ListView.builder(
                    controller: _thumbScrollController,
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.images.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      final isSelected = index == _currentIndex;
                      return GestureDetector(
                        onTap: () => _jumpTo(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 56,
                          height: 56,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? const Color(0xFFDC2626) : Colors.white24,
                              width: isSelected ? 2.5 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFFDC2626).withAlpha(120),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Opacity(
                              opacity: isSelected ? 1.0 : 0.55,
                              child: CachedNetworkImage(
                                imageUrl: widget.images[index],
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) => Container(
                                  color: Colors.black45,
                                  child: const Icon(Icons.fastfood_rounded, size: 20, color: Colors.white54),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
