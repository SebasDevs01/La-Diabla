// lib/features/favorites/providers/favorites_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../auth/providers/auth_notifier.dart';

class FavoritesState {
  const FavoritesState({
    this.favoriteIds = const {},
    this.isLoading = false,
  });

  final Set<String> favoriteIds;
  final bool isLoading;

  bool isFavorite(String productId) => favoriteIds.contains(productId);

  FavoritesState copyWith({
    Set<String>? favoriteIds,
    bool? isLoading,
  }) {
    return FavoritesState(
      favoriteIds: favoriteIds ?? this.favoriteIds,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class FavoritesNotifier extends StateNotifier<FavoritesState> {
  FavoritesNotifier(this._ref) : super(const FavoritesState()) {
    loadFavorites();
  }

  final Ref _ref;

  String _getUserPrefKey() {
    final user = _ref.read(authNotifierProvider).user;
    if (user == null || user.id.isEmpty) return 'favorites_anonymous';
    return 'favorites_${user.id}';
  }

  Future<void> loadFavorites() async {
    try {
      state = state.copyWith(isLoading: true);
      final user = _ref.read(authNotifierProvider).user;
      final key = _getUserPrefKey();
      final prefs = await SharedPreferences.getInstance();
      final localList = prefs.getStringList(key) ?? [];
      final ids = localList.toSet();

      if (user != null && !user.isGuest) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.id)
              .collection('favorites')
              .get();
          for (final doc in snap.docs) {
            ids.add(doc.id);
          }
        } catch (_) {}
      }

      state = state.copyWith(favoriteIds: ids, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> toggleFavorite(String productId) async {
    final updated = Set<String>.from(state.favoriteIds);
    final isAdding = !updated.contains(productId);

    if (isAdding) {
      updated.add(productId);
    } else {
      updated.remove(productId);
    }

    state = state.copyWith(favoriteIds: updated);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_getUserPrefKey(), updated.toList());

    final user = _ref.read(authNotifierProvider).user;
    if (user != null && !user.isGuest) {
      try {
        final docRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.id)
            .collection('favorites')
            .doc(productId);

        if (isAdding) {
          await docRef.set({
            'productId': productId,
            'addedAt': FieldValue.serverTimestamp(),
          });
        } else {
          await docRef.delete();
        }
      } catch (_) {}
    }
  }
}

final favoritesProvider = StateNotifierProvider<FavoritesNotifier, FavoritesState>((ref) {
  return FavoritesNotifier(ref);
});
