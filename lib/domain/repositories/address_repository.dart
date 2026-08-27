// lib/domain/repositories/address_repository.dart
import '../entities/address_entity.dart';

/// Interfaz del repositorio de direcciones de entrega.
abstract interface class AddressRepository {
  /// Obtiene todas las direcciones del usuario.
  Future<List<AddressEntity>> getAddresses(String userId);

  /// Stream de direcciones para actualizaciones reactivas.
  Stream<List<AddressEntity>> watchAddresses(String userId);

  /// Obtiene la dirección principal del usuario.
  Future<AddressEntity?> getDefaultAddress(String userId);

  /// Agrega una nueva dirección.
  Future<AddressEntity> addAddress(AddressEntity address);

  /// Actualiza una dirección existente.
  Future<void> updateAddress(AddressEntity address);

  /// Elimina una dirección.
  Future<void> deleteAddress(String addressId);

  /// Establece una dirección como predeterminada.
  Future<void> setDefaultAddress({
    required String userId,
    required String addressId,
  });
}
