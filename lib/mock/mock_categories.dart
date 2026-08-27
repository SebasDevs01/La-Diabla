// lib/mock/mock_categories.dart
import '../domain/entities/category_entity.dart';

/// Categorías del menú de La Diabla.
final List<CategoryEntity> mockCategories = [
  const CategoryEntity(
    id: 'tacos',
    name: 'Tacos',
    imageUrl: 'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=400',
    order: 1,
    emoji: '🌮',
    localImage: 'assets/images/taco.png',
  ),
  const CategoryEntity(
    id: 'burritos',
    name: 'Burritos',
    imageUrl: 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=400',
    order: 2,
    emoji: '🌯',
    localImage: 'assets/images/burrito.png',
  ),
  const CategoryEntity(
    id: 'quesadillas',
    name: 'Quesadillas',
    imageUrl: 'https://images.unsplash.com/photo-1599974579688-8dbdd335c77f?w=400',
    order: 3,
    emoji: '🧀',
    localImage: 'assets/images/quesadilla.png',
  ),
  const CategoryEntity(
    id: 'mariscos',
    name: 'Mariscos',
    imageUrl: 'https://images.unsplash.com/photo-1559742811-82286364ceaf?w=400',
    order: 4,
    emoji: '🦐',
    localImage: 'assets/images/especiales.png',
  ),
  const CategoryEntity(
    id: 'ensaladas',
    name: 'Ensaladas',
    imageUrl: 'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=400',
    order: 5,
    emoji: '🥗',
    localImage: 'assets/images/especiales.png',
  ),
  const CategoryEntity(
    id: 'bebidas',
    name: 'Bebidas',
    imageUrl: 'https://images.unsplash.com/photo-1544145945-f90425340c7e?w=400',
    order: 6,
    emoji: '🥤',
    localImage: 'assets/images/bebidas.png',
  ),
  const CategoryEntity(
    id: 'especiales',
    name: 'Especiales',
    imageUrl: 'https://images.unsplash.com/photo-1551504734-5ee1c4a1479b?w=400',
    order: 7,
    emoji: '⭐',
    localImage: 'assets/images/especiales.png',
  ),
];
