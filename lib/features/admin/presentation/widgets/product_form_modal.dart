// lib/features/admin/presentation/widgets/product_form_modal.dart
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../domain/entities/product_entity.dart';
import '../../../home/providers/home_provider.dart';

class ProductFormModal extends ConsumerStatefulWidget {
  const ProductFormModal({
    super.key,
    this.productToEdit,
  });

  final ProductEntity? productToEdit;

  static Future<void> show(BuildContext context, {ProductEntity? productToEdit}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductFormModal(productToEdit: productToEdit),
    );
  }

  @override
  ConsumerState<ProductFormModal> createState() => _ProductFormModalState();
}

class _ProductFormModalState extends ConsumerState<ProductFormModal> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _priceController;
  late TextEditingController _urlController;
  late TextEditingController _ingredientController;

  late String _selectedCategory;
  late int _spicyLevel;
  late bool _available;
  late List<String> _ingredients;

  final List<String> _existingImages = [];
  final List<File> _pickedImageFiles = [];
  bool _isSaving = false;

  final List<Map<String, String>> _predefinedCategories = [
    {'id': 'tacos', 'name': '🌮 Tacos'},
    {'id': 'burritos', 'name': '🌯 Burritos'},
    {'id': 'quesadillas', 'name': '🧀 Quesadillas'},
    {'id': 'bebidas', 'name': '🥤 Bebidas'},
    {'id': 'especiales', 'name': '⭐ Especiales'},
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.productToEdit;

    _nameController = TextEditingController(text: p?.name ?? '');
    _descController = TextEditingController(text: p?.description ?? '');
    _priceController = TextEditingController(
      text: p != null ? p.price.toInt().toString() : '',
    );
    _urlController = TextEditingController();
    _ingredientController = TextEditingController();

    _selectedCategory = p?.categoryId ?? 'tacos';
    _spicyLevel = p?.spicyLevel ?? 1;
    _available = p?.available ?? true;
    _ingredients = List.from(p?.ingredients ?? []);

    if (p != null) {
      _existingImages.addAll(p.allImages);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _priceController.dispose();
    _urlController.dispose();
    _ingredientController.dispose();
    super.dispose();
  }

  Future<void> _pickMultipleImages() async {
    try {
      final picker = ImagePicker();
      final pickedList = await picker.pickMultiImage(
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (pickedList.isNotEmpty) {
        setState(() {
          _pickedImageFiles.addAll(pickedList.map((x) => File(x.path)));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar imágenes: $e')),
        );
      }
    }
  }

  Future<void> _pickCameraImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() {
          _pickedImageFiles.add(File(picked.path));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al tomar foto con cámara: $e')),
        );
      }
    }
  }

  void _addUrlImage() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa una URL válida que comience con http:// o https://')),
      );
      return;
    }
    setState(() {
      _existingImages.add(url);
      _urlController.clear();
    });
  }

  void _removeExistingImage(int index) {
    setState(() {
      _existingImages.removeAt(index);
    });
  }

  void _removePickedImage(int index) {
    setState(() {
      _pickedImageFiles.removeAt(index);
    });
  }

  void _addIngredient() {
    final text = _ingredientController.text.trim();
    if (text.isNotEmpty && !_ingredients.contains(text)) {
      setState(() {
        _ingredients.add(text);
        _ingredientController.clear();
      });
    }
  }

  void _removeIngredient(String ingredient) {
    setState(() {
      _ingredients.remove(ingredient);
    });
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    if (_ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Por favor agrega al menos un ingrediente al producto'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final repo = ref.read(productRepositoryProvider);
      final id = widget.productToEdit?.id ??
          'prod_${DateTime.now().millisecondsSinceEpoch}';

      final List<String> finalImages = List.from(_existingImages);

      // Subir imágenes locales nuevas a Firebase Storage
      if (_pickedImageFiles.isNotEmpty) {
        final storage = StorageService();
        for (int i = 0; i < _pickedImageFiles.length; i++) {
          final uploadedUrl = await storage.uploadProductImageItem(
            productId: id,
            file: _pickedImageFiles[i],
            index: i,
          );
          finalImages.add(uploadedUrl);
        }
      }

      if (finalImages.isEmpty) {
        finalImages.add('https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=600');
      }

      final primaryImageUrl = finalImages.first;
      final priceVal = double.tryParse(_priceController.text.trim()) ?? 0.0;

      final product = ProductEntity(
        id: id,
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        price: priceVal,
        imageUrl: primaryImageUrl,
        images: finalImages,
        categoryId: _selectedCategory,
        spicyLevel: _spicyLevel,
        available: _available,
        ingredients: _ingredients,
        extras: widget.productToEdit?.extras ?? [],
        createdAt: widget.productToEdit?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (widget.productToEdit == null) {
        await repo.createProduct(product);
      } else {
        await repo.updateProduct(product);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.productToEdit == null
                ? '✅ ¡Producto "${product.name}" creado con éxito!'
                : '✅ ¡Producto "${product.name}" actualizado con éxito!'),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al guardar producto: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditing = widget.productToEdit != null;

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E140F) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey.withAlpha(80),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEditing ? '✏️ Editar Producto' : '✨ Nuevo Producto',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Form
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ─── Fotos del Producto (Multi-Foto) ──────────────────────────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Fotos del Platillo 📸',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            '${_existingImages.length + _pickedImageFiles.length} foto(s)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Tira horizontal de fotos
                      Container(
                        height: 120,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black26 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                        ),
                        child: (_existingImages.isEmpty && _pickedImageFiles.isEmpty)
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_photo_alternate_rounded,
                                        size: 40, color: Colors.grey.shade400),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Sin fotos aún. Agrega fotos de la galería o cámara.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.all(8),
                                children: [
                                  // Fotos existentes (red)
                                  ..._existingImages.asMap().entries.map((entry) {
                                    final idx = entry.key;
                                    final url = entry.value;
                                    final isPrimary = idx == 0;
                                    return Container(
                                      width: 104,
                                      margin: const EdgeInsets.only(right: 8),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: CachedNetworkImage(
                                              imageUrl: url,
                                              fit: BoxFit.cover,
                                              errorWidget: (context, url, error) => Container(
                                                color: Colors.black26,
                                                child: const Icon(Icons.fastfood_rounded),
                                              ),
                                            ),
                                          ),
                                          if (isPrimary)
                                            Positioned(
                                              top: 4,
                                              left: 4,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFEAB308),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  '⭐ Principal',
                                                  style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ),
                                          Positioned(
                                            top: 4,
                                            right: 4,
                                            child: GestureDetector(
                                              onTap: () => _removeExistingImage(idx),
                                              child: Container(
                                                padding: const EdgeInsets.all(3),
                                                decoration: const BoxDecoration(
                                                  color: Colors.black87,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),

                                  // Fotos recién seleccionadas (locales)
                                  ..._pickedImageFiles.asMap().entries.map((entry) {
                                    final idx = entry.key;
                                    final file = entry.value;
                                    final isPrimary = _existingImages.isEmpty && idx == 0;
                                    return Container(
                                      width: 104,
                                      margin: const EdgeInsets.only(right: 8),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: Image.file(file, fit: BoxFit.cover),
                                          ),
                                          Positioned(
                                            top: 4,
                                            left: 4,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isPrimary ? const Color(0xFFEAB308) : Colors.black87,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                isPrimary ? '⭐ Principal' : 'Nueva ⏳',
                                                style: TextStyle(
                                                  color: isPrimary ? Colors.black : Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 4,
                                            right: 4,
                                            child: GestureDetector(
                                              onTap: () => _removePickedImage(idx),
                                              child: Container(
                                                padding: const EdgeInsets.all(3),
                                                decoration: const BoxDecoration(
                                                  color: Colors.black87,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                      ),
                      const SizedBox(height: 10),

                      // Botones para agregar fotos
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _pickMultipleImages,
                              icon: const Icon(Icons.photo_library_rounded, size: 16),
                              label: const Text('+ Galería', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _pickCameraImage,
                              icon: const Icon(Icons.camera_alt_rounded, size: 16),
                              label: const Text('+ Cámara', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Input URL con botón Agregar
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _urlController,
                              decoration: InputDecoration(
                                labelText: 'O ingresa URL de imagen',
                                hintText: 'https://...',
                                prefixIcon: const Icon(Icons.link_rounded),
                                filled: true,
                                fillColor: isDark ? Colors.black26 : Colors.grey.shade50,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                              onFieldSubmitted: (_) => _addUrlImage(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark ? const Color(0xFF2C1E18) : Colors.grey.shade200,
                              foregroundColor: isDark ? Colors.white : Colors.black87,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            ),
                            onPressed: _addUrlImage,
                            child: const Text('Agregar', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ─── Nombre del Artículo ──────────────────────────────────────────
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Nombre del artículo *',
                      hintText: 'Ej. Tacos al Pastor Especiales',
                      prefixIcon: const Icon(Icons.fastfood_rounded),
                      filled: true,
                      fillColor: isDark ? Colors.black26 : Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'El nombre es obligatorio' : null,
                  ),
                  const SizedBox(height: 16),

                  // ─── Descripción ──────────────────────────────────────────────────
                  TextFormField(
                    controller: _descController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Descripción del platillo',
                      hintText: 'Describe el sabor, porciones o preparación...',
                      prefixIcon: const Icon(Icons.description_rounded),
                      filled: true,
                      fillColor: isDark ? Colors.black26 : Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ─── Precio y Categoría ───────────────────────────────────────────
                  Row(
                    children: [
                      // Precio
                      Expanded(
                        child: TextFormField(
                          controller: _priceController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Precio (COP) *',
                            hintText: '18000',
                            prefixIcon: const Icon(Icons.monetization_on_rounded),
                            filled: true,
                            fillColor: isDark ? Colors.black26 : Colors.grey.shade50,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Requerido';
                            final n = double.tryParse(v.trim());
                            if (n == null || n <= 0) return 'Precio inválido';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Categoría
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedCategory,
                          decoration: InputDecoration(
                            labelText: 'Categoría *',
                            filled: true,
                            fillColor: isDark ? Colors.black26 : Colors.grey.shade50,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          items: _predefinedCategories.map((c) {
                            return DropdownMenuItem(
                              value: c['id'],
                              child: Text(c['name']!, style: const TextStyle(fontSize: 13)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedCategory = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ─── Nivel de Picante ─────────────────────────────────────────────
                  const Text('Nivel de picante:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildSpicyChip(0, '🫑 Sin picante'),
                      const SizedBox(width: 6),
                      _buildSpicyChip(1, '🌶️ Suave'),
                      const SizedBox(width: 6),
                      _buildSpicyChip(2, '🌶️🌶️ Medio'),
                      const SizedBox(width: 6),
                      _buildSpicyChip(3, '🔥 La Diabla'),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ─── Gestión de Ingredientes ──────────────────────────────────────
                  const Text('Ingredientes del platillo *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    'Escribe un ingrediente y presiona "Agregar" o Enter:',
                    style: TextStyle(fontSize: 11.5, color: isDark ? AppColors.textMutedDark : Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _ingredientController,
                          decoration: InputDecoration(
                            hintText: 'Ej. Queso Oaxaca, Piña asada...',
                            filled: true,
                            fillColor: isDark ? Colors.black26 : Colors.grey.shade50,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onFieldSubmitted: (_) => _addIngredient(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _addIngredient,
                        child: const Text('Agregar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Chips de ingredientes
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _ingredients.map((ing) {
                      return Chip(
                        label: Text(ing, style: const TextStyle(fontSize: 12)),
                        backgroundColor: isDark ? const Color(0xFF2C1E18) : const Color(0xFFFEF2F2),
                        deleteIcon: const Icon(Icons.close_rounded, size: 16),
                        onDeleted: () => _removeIngredient(ing),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: Colors.red.withAlpha(60)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // ─── Switch de Disponibilidad ─────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black26 : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Disponible para venta', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text(
                              _available ? 'Visible para pedidos en la app móvil' : 'Agotado (no se mostrará a clientes)',
                              style: TextStyle(
                                fontSize: 11,
                                color: _available ? const Color(0xFF16A34A) : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: _available,
                          activeTrackColor: const Color(0xFF16A34A),
                          activeThumbColor: Colors.white,
                          onChanged: (val) => setState(() => _available = val),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ─── Botón Guardar ────────────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _isSaving ? null : _saveProduct,
                      child: _isSaving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              isEditing ? '💾 Guardar Cambios' : '🚀 Publicar Producto en la App',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpicyChip(int level, String label) {
    final isSelected = _spicyLevel == level;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _spicyLevel = level),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFDC2626)
                : (Theme.of(context).brightness == Brightness.dark
                    ? Colors.black26
                    : Colors.grey.shade100),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFFDC2626) : Colors.grey.withAlpha(50),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : null,
            ),
          ),
        ),
      ),
    );
  }
}
