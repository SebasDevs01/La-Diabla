// lib/data/repositories/address_repository_impl.dart
import 'dart:async';
import '../../domain/entities/address_entity.dart';
import '../../domain/repositories/address_repository.dart';

class AddressRepositoryImpl implements AddressRepository {
  final List<AddressEntity> _addresses = [
    AddressEntity(
      id: 'addr_1',
      userId: 'user_mock',
      label: AddressLabel.home,
      formattedAddress: 'Av. Insurgentes Sur 123, Roma Norte, CDMX',
      latitude: 19.4123,
      longitude: -99.1623,
      reference: 'Depto 402, timbre blanco',
      isDefault: true,
      createdAt: DateTime.now(),
    ),
  ];

  final _addressController = StreamController<List<AddressEntity>>.broadcast();

  void _notify(String userId) {
    _addressController.add(
      _addresses.where((a) => a.userId == userId).toList(),
    );
  }

  @override
  Future<List<AddressEntity>> getAddresses(String userId) async {
    return _addresses.where((a) => a.userId == userId).toList();
  }

  @override
  Stream<List<AddressEntity>> watchAddresses(String userId) async* {
    yield await getAddresses(userId);
    yield* _addressController.stream;
  }

  @override
  Future<AddressEntity?> getDefaultAddress(String userId) async {
    try {
      return _addresses.firstWhere(
        (a) => a.userId == userId && a.isDefault,
      );
    } catch (_) {
      final userAddrs = await getAddresses(userId);
      return userAddrs.isNotEmpty ? userAddrs.first : null;
    }
  }

  @override
  Future<AddressEntity> addAddress(AddressEntity address) async {
    if (address.isDefault) {
      for (var i = 0; i < _addresses.length; i++) {
        if (_addresses[i].userId == address.userId) {
          _addresses[i] = _addresses[i].copyWith(isDefault: false);
        }
      }
    }
    _addresses.add(address);
    _notify(address.userId);
    return address;
  }

  @override
  Future<void> updateAddress(AddressEntity address) async {
    final index = _addresses.indexWhere((a) => a.id == address.id);
    if (index != -1) {
      if (address.isDefault) {
        for (var i = 0; i < _addresses.length; i++) {
          if (_addresses[i].userId == address.userId) {
            _addresses[i] = _addresses[i].copyWith(isDefault: false);
          }
        }
      }
      _addresses[index] = address;
      _notify(address.userId);
    }
  }

  @override
  Future<void> deleteAddress(String addressId) async {
    final index = _addresses.indexWhere((a) => a.id == addressId);
    if (index != -1) {
      final userId = _addresses[index].userId;
      _addresses.removeAt(index);
      _notify(userId);
    }
  }

  @override
  Future<void> setDefaultAddress({
    required String userId,
    required String addressId,
  }) async {
    for (var i = 0; i < _addresses.length; i++) {
      if (_addresses[i].userId == userId) {
        final isMatch = _addresses[i].id == addressId;
        _addresses[i] = _addresses[i].copyWith(isDefault: isMatch);
      }
    }
    _notify(userId);
  }
}
