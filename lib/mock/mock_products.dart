// lib/mock/mock_products.dart
import '../domain/entities/extra_entity.dart';
import '../domain/entities/product_entity.dart';

final List<ExtraEntity> mockExtras = [
  const ExtraEntity(id: 'ex_guacamole', name: 'Guacamole extra 🥑', price: 5000.0),
  const ExtraEntity(id: 'ex_queso', name: 'Queso fundido extra 🧀', price: 4000.0),
  const ExtraEntity(id: 'ex_crema', name: 'Crema agria 🥛', price: 3000.0),
  const ExtraEntity(id: 'ex_jalapenos', name: 'Jalapeños toreados 🌶️', price: 3000.0),
  const ExtraEntity(id: 'ex_salsa_diabla', name: 'Salsa La Diabla (Extrema 🔥)', price: 2000.0),
  const ExtraEntity(id: 'ex_tortillas', name: 'Porción de tortillas (3 unid) 🫓', price: 2500.0),
  const ExtraEntity(id: 'ex_totopos', name: 'Porción de Totopos crujientes 🌮', price: 3500.0),
  const ExtraEntity(id: 'ex_papas', name: 'Papas a la francesa 🍟', price: 6000.0),
];

final List<ProductEntity> mockProducts = [
  // ─── TEST / PRUEBAS DE PAGO ──────────────────────────────────────────────────
  ProductEntity(
    id: 'test_tarjeta_50',
    name: 'Taco de Prueba 🧪 (Test Tarjeta)',
    description:
        'Producto especial para probar cobro y pasarela de tarjetas sin gastar dinero. Valor simbólico de \$50 pesos COP.',
    price: 50.0,
    imageUrl: 'https://images.unsplash.com/photo-1551504734-5ee1c4a1479b?w=600',
    categoryId: 'especiales',
    spicyLevel: 1,
    ingredients: const ['Prueba de tarjeta', 'Cobro \$50 COP', 'Verificación pasarela'],
    extras: const [],
  ),

  // ─── 1. AGUACHILES (Diabla 🔥) ────────────────────────────────────────────────
  ProductEntity(
    id: 'aguachiles',
    name: 'Aguachiles',
    description:
        'Camarón marinado/curtido en especias picantes, cebolla, jalapeño, pepino, jugo de limón fresco y aguacate.',
    price: 49900.0,
    imageUrl: 'https://images.unsplash.com/photo-1535400255456-984241443b29?w=600',
    categoryId: 'mariscos',
    spicyLevel: 3,
    ingredients: const ['Camarón', 'Especias picantes', 'Cebolla', 'Jalapeño', 'Pepino', 'Jugo de limón', 'Aguacate'],
    extras: mockExtras,
  ),

  // ─── 2. AGUACHILES MIXTOS (Diabla 🔥) ─────────────────────────────────────────
  ProductEntity(
    id: 'aguachiles_mixtos',
    name: 'Aguachiles mixtos',
    description:
        'Camarones y pulpo marinados en especias picantes, limón, jalapeño, cebolla, pepino y aguacate.',
    price: 69900.0,
    imageUrl: 'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=600',
    categoryId: 'mariscos',
    spicyLevel: 3,
    ingredients: const ['Pulpo', 'Camarón', 'Especias picantes', 'Cebolla', 'Jalapeño', 'Pepino', 'Jugo de limón', 'Aguacate'],
    extras: mockExtras,
  ),

  // ─── 3. PULPADITAS (Sin picante) ──────────────────────────────────────────────
  ProductEntity(
    id: 'pulpaditas',
    name: 'Pulpaditas',
    description:
        'Tres mini tostadas de pulpo acompañadas de cebolla, mango, pepino y aguacate.',
    price: 39900.0,
    imageUrl: 'https://images.unsplash.com/photo-1544025162-d76694265947?w=600',
    categoryId: 'mariscos',
    spicyLevel: 0,
    ingredients: const ['Tres mini tostadas de pulpo con cebolla', 'mango', 'pepino', 'aguacate'],
    extras: mockExtras,
  ),

  // ─── 4. ENCHILADAS DE POLLO (Suave 🌶️) ────────────────────────────────────────
  ProductEntity(
    id: 'enchiladas_pollo',
    name: 'Enchiladas de pollo',
    description:
        'Enchilada rellena de pollo deshebrado, cubierta con salsa de mole y queso, con salsa verde opcional.',
    price: 19900.0,
    imageUrl: 'https://images.unsplash.com/photo-1584031036380-3fb6f2d51880?w=600',
    categoryId: 'enchiladas',
    spicyLevel: 1,
    ingredients: const ['Pollo deshebrado', 'salsa de mole', 'queso jack', 'salsa verde (opcional)'],
    extras: mockExtras,
  ),

  // ─── 5. ENCHILADAS DE QUESO (Suave 🌶️) ────────────────────────────────────────
  ProductEntity(
    id: 'enchiladas_queso',
    name: 'Enchiladas de queso',
    description:
        'Enchilada rellena de queso y cubierta con salsa de mole y queso, con salsa verde opcional.',
    price: 18900.0,
    imageUrl: 'https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?w=600',
    categoryId: 'enchiladas',
    spicyLevel: 1,
    ingredients: const ['Queso', 'Salsa de mole', 'Queso Jack', 'Salsa verde (opcional)'],
    extras: mockExtras,
  ),

  // ─── 6. ENCHILADAS DE RES (Suave 🌶️) ──────────────────────────────────────────
  ProductEntity(
    id: 'enchiladas_res',
    name: 'Enchiladas de res',
    description:
        'Enchilada rellena de carne de res deshebrada, cubierta con salsa de mole y queso, con salsa verde opcional.',
    price: 22000.0,
    imageUrl: 'https://images.unsplash.com/photo-1551504734-5ee1c4a1479b?w=600',
    categoryId: 'enchiladas',
    spicyLevel: 1,
    ingredients: const ['Carne de res deshebrada', 'Salsa de mole', 'Queso Jack', 'Salsa verde (opcional)'],
    extras: mockExtras,
  ),

  // ─── 7. BURRITO DE CARNE ASADA (Sin picante) ──────────────────────────────────
  ProductEntity(
    id: 'burrito_carne_asada',
    name: 'Burrito de carne asada',
    description:
        'Burrito de tortilla de harina relleno de carne asada, arroz, frijoles y queso.',
    price: 39500.0,
    imageUrl: 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=600',
    categoryId: 'burritos',
    spicyLevel: 0,
    ingredients: const ['Carne Black Angus', 'Arroz', 'Frijoles', 'Queso'],
    extras: mockExtras,
  ),

  // ─── 8. BURRITO DE POLLO (Sin picante) ────────────────────────────────────────
  ProductEntity(
    id: 'burrito_pollo',
    name: 'Burrito de pollo',
    description:
        'Burrito de tortilla de harina relleno de pollo deshebrado, frijoles, arroz y queso.',
    price: 29900.0,
    imageUrl: 'https://images.unsplash.com/photo-1584031036380-3fb6f2d51880?w=600',
    categoryId: 'burritos',
    spicyLevel: 0,
    ingredients: const ['Pollo', 'Arroz', 'Frijoles', 'Queso Jack'],
    extras: mockExtras,
  ),

  // ─── 9. BURRITO DE RES (Sin picante) ──────────────────────────────────────────
  ProductEntity(
    id: 'burrito_res',
    name: 'Burrito de res',
    description:
        'Burrito de tortilla de harina relleno de carne de res deshebrada, frijoles, arroz y queso.',
    price: 32900.0,
    imageUrl: 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=600',
    categoryId: 'burritos',
    spicyLevel: 0,
    ingredients: const ['Carne de res deshebrada', 'Arroz', 'Frijoles', 'Queso Jack'],
    extras: mockExtras,
  ),

  // ─── 10. POLLO ASADO / BURRITO DE POLLO ASADO (Sin picante) ───────────────────
  ProductEntity(
    id: 'pollo_asado',
    name: 'Burrito de pollo asado (A la mexicana)',
    description:
        'Burrito de tortilla de harina relleno de pollo asado, arroz, frijoles, aguacate, vegetales y queso cheddar.',
    price: 39900.0,
    imageUrl: 'https://images.unsplash.com/photo-1598515214211-89d3c73ae83b?w=600',
    categoryId: 'burritos',
    spicyLevel: 0,
    ingredients: const [
      'pollo asado en tiras',
      'tortilla de trigo',
      'frijoles',
      'aguacate',
      'lechuga romana',
      'tomate',
      'cebolla morada',
      'maíz dulce',
      'queso cheddar',
      'pico de gallo',
      'limón verde',
      'crema agria'
    ],
    extras: mockExtras,
  ),

  // ─── 11. FAJITAS DE POLLO (Medio 🌶️🌶️) ───────────────────────────────────────
  ProductEntity(
    id: 'fajitas_pollo',
    name: 'Fajitas de pollo',
    description:
        'Fajitas de pollo preparadas al momento con pimientos, cebolla asada, tomate y salsa especial de la casa.',
    price: 42900.0,
    imageUrl: 'https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?w=600',
    categoryId: 'fajitas',
    spicyLevel: 2,
    ingredients: const [
      'Pollo',
      'Pimientos',
      'Cebolla asada',
      'Tomate',
      'Salsa de fajitas',
      'Arroz',
      'Frijoles',
      'Crema',
      'Queso',
      'Guacamole',
      'Tortilla de maíz o harina'
    ],
    extras: mockExtras,
  ),

  // ─── 12. FAJITAS DE CAMARÓN (Medio 🌶️🌶️) ─────────────────────────────────────
  ProductEntity(
    id: 'fajitas_camaron',
    name: 'Fajitas de camarón',
    description:
        'Camarones salteados al estilo fajita con pimientos, cebolla asada, tomate y salsa especial de la casa.',
    price: 49900.0,
    imageUrl: 'https://images.unsplash.com/photo-1551504734-5ee1c4a1479b?w=600',
    categoryId: 'fajitas',
    spicyLevel: 2,
    ingredients: const [
      'Camarón',
      'Pimientos',
      'Cebolla asada',
      'Tomate',
      'Salsa de fajitas',
      'Arroz',
      'Frijoles',
      'Crema',
      'Queso',
      'Guacamole',
      'Tortilla de maíz o harina'
    ],
    extras: mockExtras,
  ),

  // ─── 13. FAJITAS MIXTAS (Medio 🌶️🌶️) ─────────────────────────────────────────
  ProductEntity(
    id: 'fajitas_mixtas',
    name: 'Fajitas mixtas',
    description:
        'Combinación de carne asada, camarón y pollo preparados con pimientos, cebolla, tomate y salsa especial de la casa.',
    price: 54900.0,
    imageUrl: 'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=600',
    categoryId: 'fajitas',
    spicyLevel: 2,
    ingredients: const [
      'Carne asada',
      'Pollo',
      'Camarón',
      'Pimientos',
      'Cebolla asada',
      'Tomate',
      'Salsa de fajitas',
      'Arroz',
      'Frijoles',
      'Crema',
      'Queso',
      'Guacamole',
      'Tortilla de maíz o harina'
    ],
    extras: mockExtras,
  ),

  // ─── 14. FAJITAS DE ASADA (Medio 🌶️🌶️) ───────────────────────────────────────
  ProductEntity(
    id: 'fajitas_asada',
    name: 'Fajitas de asada',
    description:
        'Tiras tiernas de carne asada preparadas al momento con pimientos, cebolla asada, tomate y salsa especial de la casa.',
    price: 47900.0,
    imageUrl: 'https://images.unsplash.com/photo-1599974579688-8dbdd335c77f?w=600',
    categoryId: 'fajitas',
    spicyLevel: 2,
    ingredients: const [
      'Carne asada',
      'Pimientos',
      'Cebolla asada',
      'Tomate',
      'Salsa de fajitas',
      'Arroz',
      'Frijoles',
      'Crema',
      'Queso',
      'Guacamole',
      'Tortilla de maíz o harina'
    ],
    extras: mockExtras,
  ),
];
