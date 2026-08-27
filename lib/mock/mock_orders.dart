// lib/mock/mock_orders.dart
import '../domain/entities/address_entity.dart';
import '../domain/entities/order_entity.dart';

final mockAddress = AddressEntity(
  id: 'addr_sample',
  userId: 'usr_sample',
  label: AddressLabel.home,
  latitude: 7.092758,
  longitude: -73.142590,
  formattedAddress: 'Cl. 59 # 39W-24, Estoraques 1, Bucaramanga',
);

// Lista vacía para evitar pedidos fantasmas cuando no hay conexión o en cuentas nuevas
final List<OrderEntity> mockOrders = const [];
