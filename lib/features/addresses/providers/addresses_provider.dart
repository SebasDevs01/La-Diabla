// lib/features/addresses/providers/addresses_provider.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/entities/address_entity.dart';

// ─── State ────────────────────────────────────────────────────────────────────
class AddressesState {
  const AddressesState({this.addresses = const [], this.isLoading = false});

  final List<AddressEntity> addresses;
  final bool isLoading;

  AddressEntity? get defaultAddress =>
      addresses.where((a) => a.isDefault).firstOrNull ??
      addresses.firstOrNull;

  AddressesState copyWith({List<AddressEntity>? addresses, bool? isLoading}) =>
      AddressesState(
        addresses: addresses ?? this.addresses,
        isLoading: isLoading ?? this.isLoading,
      );
}

// ─── Notifier ─────────────────────────────────────────────────────────────────
class AddressesNotifier extends StateNotifier<AddressesState> {
  AddressesNotifier() : super(const AddressesState()) {
    _loadAddresses();
  }

  static const _prefsKey = 'saved_addresses';

  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  Future<void> _loadAddresses() async {
    state = state.copyWith(isLoading: true);
    try {
      // 1. Cargar inmediatamente de caché local para evitar pantalla en blanco
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      List<AddressEntity> localList = [];
      if (raw != null) {
        try {
          localList = (json.decode(raw) as List<dynamic>)
              .map((e) => _fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }
      if (localList.isNotEmpty) {
        state = state.copyWith(addresses: localList, isLoading: false);
      }

      // 2. Sincronizar desde Firestore si hay usuario autenticado (timeout 4s)
      final uid = _currentUserId;
      if (uid != null && uid.isNotEmpty && uid != 'guest') {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('addresses')
              .get()
              .timeout(const Duration(seconds: 4));

          if (snap.docs.isNotEmpty) {
            final firestoreList = snap.docs.map((d) => _fromJson(d.data())).toList();
            state = state.copyWith(addresses: firestoreList, isLoading: false);
            await _persistLocal(firestoreList);
            return;
          }
        } catch (_) {}
      }

      state = state.copyWith(addresses: localList, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> _persistLocal(List<AddressEntity> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        json.encode(list.map(_toJson).toList()),
      );
    } catch (_) {}
  }

  Future<void> addAddress(AddressEntity address) async {
    final uid = _currentUserId ?? 'guest';
    final isFirst = state.addresses.isEmpty;
    final newAddress = address.copyWith(
      userId: uid,
      isDefault: isFirst || address.isDefault,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Si la nueva es default, desmarcar las anteriores
    List<AddressEntity> updated;
    if (newAddress.isDefault) {
      updated = state.addresses.map((a) => a.copyWith(isDefault: false)).toList();
      updated.add(newAddress);
    } else {
      updated = [...state.addresses, newAddress];
    }

    // Actualización inmediata en memoria y almacenamiento local
    state = state.copyWith(addresses: updated);
    await _persistLocal(updated);

    // Sincronizar en Firestore en segundo plano (no bloqueante)
    if (uid != 'guest') {
      try {
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('addresses')
            .doc(newAddress.id)
            .set(_toJson(newAddress))
            .timeout(const Duration(seconds: 4))
            .catchError((_) {});
      } catch (_) {}
    }
  }

  Future<void> editAddress(AddressEntity address) async {
    final uid = _currentUserId ?? 'guest';
    final updated = state.addresses.map((a) {
      if (a.id == address.id) {
        return address.copyWith(updatedAt: DateTime.now());
      }
      return address.isDefault ? a.copyWith(isDefault: false) : a;
    }).toList();

    state = state.copyWith(addresses: updated);
    await _persistLocal(updated);

    if (uid != 'guest') {
      try {
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('addresses')
            .doc(address.id)
            .update(_toJson(address))
            .timeout(const Duration(seconds: 4))
            .catchError((_) {});
      } catch (_) {}
    }
  }

  Future<void> deleteAddress(String id) async {
    final uid = _currentUserId ?? 'guest';
    final updated = state.addresses.where((a) => a.id != id).toList();
    final hasDefault = updated.any((a) => a.isDefault);
    if (!hasDefault && updated.isNotEmpty) {
      updated[0] = updated[0].copyWith(isDefault: true);
    }
    state = state.copyWith(addresses: updated);
    await _persistLocal(updated);

    if (uid != 'guest') {
      try {
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('addresses')
            .doc(id)
            .delete()
            .timeout(const Duration(seconds: 4))
            .catchError((_) {});
      } catch (_) {}
    }
  }

  Future<void> setDefault(String id) async {
    final uid = _currentUserId ?? 'guest';
    final updated = state.addresses
        .map((a) => a.copyWith(isDefault: a.id == id))
        .toList();
    state = state.copyWith(addresses: updated);
    await _persistLocal(updated);

    if (uid != 'guest') {
      try {
        final batch = FirebaseFirestore.instance.batch();
        for (final addr in updated) {
          final docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('addresses')
              .doc(addr.id);
          batch.update(docRef, {'isDefault': addr.isDefault});
        }
        batch.commit().timeout(const Duration(seconds: 4)).catchError((_) {});
      } catch (_) {}
    }
  }

  // ─── JSON helpers ──────────────────────────────────────────────────────────
  static Map<String, dynamic> _toJson(AddressEntity a) => {
    'id': a.id,
    'userId': a.userId,
    'label': a.label.name,
    'formattedAddress': a.formattedAddress,
    'latitude': a.latitude,
    'longitude': a.longitude,
    'reference': a.reference,
    'isDefault': a.isDefault,
    'createdAt': a.createdAt?.toIso8601String(),
    'updatedAt': a.updatedAt?.toIso8601String(),
  };

  static AddressEntity _fromJson(Map<String, dynamic> j) => AddressEntity(
    id: j['id'] as String? ?? '',
    userId: j['userId'] as String? ?? '',
    label: AddressLabel.fromString(j['label'] as String? ?? 'other'),
    formattedAddress: j['formattedAddress'] as String? ?? 'Ubicación seleccionada',
    latitude: (j['latitude'] as num?)?.toDouble() ?? 7.092758,
    longitude: (j['longitude'] as num?)?.toDouble() ?? -73.142590,
    reference: j['reference'] as String?,
    isDefault: j['isDefault'] as bool? ?? false,
    createdAt: j['createdAt'] != null ? DateTime.tryParse(j['createdAt'] as String) : null,
    updatedAt: j['updatedAt'] != null ? DateTime.tryParse(j['updatedAt'] as String) : null,
  );
}

// ─── Provider ─────────────────────────────────────────────────────────────────
final addressesProvider =
    StateNotifierProvider<AddressesNotifier, AddressesState>(
      (ref) => AddressesNotifier(),
    );
