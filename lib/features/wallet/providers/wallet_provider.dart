// lib/features/wallet/providers/wallet_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../domain/entities/payment_card_entity.dart';
import '../../auth/providers/auth_notifier.dart';

class WalletState {
  const WalletState({
    this.cards = const [],
    this.selectedCard,
    this.isLoading = false,
    this.errorMessage,
  });

  final List<PaymentCardEntity> cards;
  final PaymentCardEntity? selectedCard;
  final bool isLoading;
  final String? errorMessage;

  WalletState copyWith({
    List<PaymentCardEntity>? cards,
    PaymentCardEntity? selectedCard,
    bool? isLoading,
    String? errorMessage,
  }) {
    return WalletState(
      cards: cards ?? this.cards,
      selectedCard: selectedCard ?? this.selectedCard,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class WalletNotifier extends StateNotifier<WalletState> {
  WalletNotifier(this._ref) : super(const WalletState()) {
    loadUserCards();
  }

  final Ref _ref;

  Future<void> loadUserCards() async {
    final user = _ref.read(authNotifierProvider).user;
    if (user == null || user.isGuest) {
      // Usuarios invitados o sin sesión inician sin tarjetas vinculadas
      state = state.copyWith(
        cards: const [],
        selectedCard: null,
        isLoading: false,
      );
      return;
    }

    try {
      state = state.copyWith(isLoading: true);
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.id)
          .collection('cards')
          .orderBy('createdAt', descending: true)
          .get();

      if (snapshot.docs.isEmpty) {
        state = state.copyWith(cards: const [], selectedCard: null, isLoading: false);
      } else {
        final cards = snapshot.docs.map((doc) => PaymentCardEntity.fromMap(doc.data(), doc.id)).toList();
        state = state.copyWith(
          cards: cards,
          selectedCard: cards.firstWhere((c) => c.isDefault, orElse: () => cards.first),
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Error al cargar tarjetas: $e');
    }
  }

  void selectCard(PaymentCardEntity card) {
    state = state.copyWith(selectedCard: card);
  }

  Future<bool> addCard({
    required String cardNumber,
    required String holderName,
    required String expiryDate,
    required String cvv,
    String cardType = 'Débito',
  }) async {
    final user = _ref.read(authNotifierProvider).user;
    final cleanNumber = cardNumber.replaceAll(RegExp(r'\s+'), '');
    final lastFour = cleanNumber.length >= 4 ? cleanNumber.substring(cleanNumber.length - 4) : '0000';

    String brand = 'visa';
    if (cleanNumber.startsWith('5') || cleanNumber.startsWith('2')) {
      brand = 'mastercard';
    } else if (cleanNumber.startsWith('3')) {
      brand = 'amex';
    }

    final cardId = const Uuid().v4();
    final newCard = PaymentCardEntity(
      id: cardId,
      userId: user?.id ?? 'guest',
      holderName: holderName.toUpperCase().trim(),
      lastFourDigits: lastFour,
      brand: brand,
      expiryDate: expiryDate.trim(),
      cardType: cardType,
      methodType: 'card',
      isDefault: state.cards.isEmpty,
      createdAt: DateTime.now(),
    );

    try {
      if (user != null && !user.isGuest) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.id)
            .collection('cards')
            .doc(cardId)
            .set(newCard.toMap());
      }

      final updatedCards = [newCard, ...state.cards];
      state = state.copyWith(
        cards: updatedCards,
        selectedCard: newCard,
      );
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Error al guardar tarjeta: $e');
      return false;
    }
  }

  Future<bool> linkNequi({
    required String phone,
    required String holderName,
    required String email,
    required String docType,
    required String docNumber,
  }) async {
    final user = _ref.read(authNotifierProvider).user;
    final cardId = const Uuid().v4();
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    final lastFour = cleanPhone.length >= 4 ? cleanPhone.substring(cleanPhone.length - 4) : '0000';

    final nequiMethod = PaymentCardEntity(
      id: cardId,
      userId: user?.id ?? 'guest',
      holderName: holderName.toUpperCase().trim(),
      lastFourDigits: lastFour,
      brand: 'nequi',
      expiryDate: 'Activa',
      cardType: 'Nequi',
      methodType: 'nequi',
      phone: cleanPhone,
      docType: docType,
      docNumber: docNumber,
      email: email,
      isDefault: state.cards.isEmpty,
      createdAt: DateTime.now(),
    );

    try {
      if (user != null && !user.isGuest) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.id)
            .collection('cards')
            .doc(cardId)
            .set(nequiMethod.toMap());
      }

      final updatedCards = [nequiMethod, ...state.cards];
      state = state.copyWith(
        cards: updatedCards,
        selectedCard: nequiMethod,
      );
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Error al vincular Nequi: $e');
      return false;
    }
  }

  Future<bool> linkBancolombia({
    required String docType,
    required String docNumber,
    required String holderName,
    required String email,
  }) async {
    final user = _ref.read(authNotifierProvider).user;
    final cardId = const Uuid().v4();
    final lastFour = docNumber.length >= 4 ? docNumber.substring(docNumber.length - 4) : '0000';

    final bancolombiaMethod = PaymentCardEntity(
      id: cardId,
      userId: user?.id ?? 'guest',
      holderName: holderName.toUpperCase().trim(),
      lastFourDigits: lastFour,
      brand: 'bancolombia',
      expiryDate: 'Activa',
      cardType: 'Bancolombia',
      methodType: 'bancolombia',
      docType: docType,
      docNumber: docNumber,
      email: email,
      isDefault: state.cards.isEmpty,
      createdAt: DateTime.now(),
    );

    try {
      if (user != null && !user.isGuest) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.id)
            .collection('cards')
            .doc(cardId)
            .set(bancolombiaMethod.toMap());
      }

      final updatedCards = [bancolombiaMethod, ...state.cards];
      state = state.copyWith(
        cards: updatedCards,
        selectedCard: bancolombiaMethod,
      );
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Error al vincular Bancolombia: $e');
      return false;
    }
  }

  Future<void> setDefaultCard(String cardId) async {
    final user = _ref.read(authNotifierProvider).user;
    final updated = state.cards.map((c) => c.copyWith(isDefault: c.id == cardId)).toList();
    final selected = updated.firstWhere((c) => c.id == cardId, orElse: () => updated.first);

    state = state.copyWith(cards: updated, selectedCard: selected);

    if (user != null && !user.isGuest) {
      try {
        final batch = FirebaseFirestore.instance.batch();
        for (final c in updated) {
          final docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(user.id)
              .collection('cards')
              .doc(c.id);
          batch.update(docRef, {'isDefault': c.isDefault});
        }
        await batch.commit();
      } catch (_) {}
    }
  }

  Future<void> removeCard(String cardId) async {
    final user = _ref.read(authNotifierProvider).user;
    try {
      if (user != null && !user.isGuest) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.id)
            .collection('cards')
            .doc(cardId)
            .delete();
      }

      final updatedCards = state.cards.where((c) => c.id != cardId).toList();
      state = state.copyWith(
        cards: updatedCards,
        selectedCard: updatedCards.isNotEmpty ? updatedCards.first : null,
      );
    } catch (_) {}
  }
}

final walletProvider = StateNotifierProvider<WalletNotifier, WalletState>((ref) {
  return WalletNotifier(ref);
});
