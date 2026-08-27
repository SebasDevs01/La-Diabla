// lib/domain/entities/user_entity.dart
import 'package:equatable/equatable.dart';

/// Rol del usuario en el sistema.
enum UserRole {
  customer,
  admin,
  driver,
  kitchen;

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => UserRole.customer,
    );
  }
}

/// Entidad de usuario del dominio.
class UserEntity extends Equatable {
  const UserEntity({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.phone,
    this.photoUrl,
    this.fcmToken,
    this.isGuest = false,
    this.referralCode,
    this.guestAddress,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String email;
  final UserRole role;
  final String? phone;
  final String? photoUrl;
  final String? fcmToken;
  final bool isGuest;
  final String? referralCode;
  final String? guestAddress;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isAdmin => role == UserRole.admin;
  bool get isDriver => role == UserRole.driver;
  bool get isKitchen => role == UserRole.kitchen;
  bool get isCustomer => role == UserRole.customer;

  String get displayName => name;
  String? get phoneNumber => phone;

  UserEntity copyWith({
    String? id,
    String? name,
    String? email,
    UserRole? role,
    String? phone,
    String? photoUrl,
    String? fcmToken,
    bool? isGuest,
    String? referralCode,
    String? guestAddress,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      photoUrl: photoUrl ?? this.photoUrl,
      fcmToken: fcmToken ?? this.fcmToken,
      isGuest: isGuest ?? this.isGuest,
      referralCode: referralCode ?? this.referralCode,
      guestAddress: guestAddress ?? this.guestAddress,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id, name, email, role, phone, photoUrl, fcmToken, isGuest, referralCode, guestAddress, createdAt, updatedAt,
  ];
}
