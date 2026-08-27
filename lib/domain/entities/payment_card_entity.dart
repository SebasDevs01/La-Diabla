// lib/domain/entities/payment_card_entity.dart
import 'package:equatable/equatable.dart';

class PaymentCardEntity extends Equatable {
  const PaymentCardEntity({
    required this.id,
    required this.userId,
    required this.holderName,
    required this.lastFourDigits,
    required this.brand, // 'visa', 'mastercard', 'amex', 'nequi', 'bancolombia'
    required this.expiryDate, // 'MM/YY' o fecha de vinculación
    this.cardType = 'Débito', // 'Crédito', 'Débito', 'Nequi', 'Bancolombia'
    this.isDefault = false,
    this.cardToken,
    this.phone,
    this.docType,
    this.docNumber,
    this.email,
    this.methodType = 'card', // 'card', 'nequi', 'bancolombia'
    this.createdAt,
  });

  final String id;
  final String userId;
  final String holderName;
  final String lastFourDigits;
  final String brand;
  final String expiryDate;
  final String cardType;
  final bool isDefault;
  final String? cardToken;
  final String? phone;
  final String? docType;
  final String? docNumber;
  final String? email;
  final String methodType;
  final DateTime? createdAt;

  String get maskedNumber {
    if (methodType == 'nequi') {
      return phone != null && phone!.length >= 4
          ? 'Cel. •••• ${phone!.substring(phone!.length - 4)}'
          : 'Nequi •••• $lastFourDigits';
    }
    if (methodType == 'bancolombia') {
      return docNumber != null && docNumber!.length >= 4
          ? '$docType •••• ${docNumber!.substring(docNumber!.length - 4)}'
          : 'Bancolombia PSE';
    }
    return '•••• $lastFourDigits';
  }

  String get displayTitle {
    if (methodType == 'nequi') return 'Nequi';
    if (methodType == 'bancolombia') return 'Bancolombia (PSE)';
    return '$brand $cardType'.toUpperCase();
  }

  PaymentCardEntity copyWith({
    String? id,
    String? userId,
    String? holderName,
    String? lastFourDigits,
    String? brand,
    String? expiryDate,
    String? cardType,
    bool? isDefault,
    String? cardToken,
    String? phone,
    String? docType,
    String? docNumber,
    String? email,
    String? methodType,
    DateTime? createdAt,
  }) {
    return PaymentCardEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      holderName: holderName ?? this.holderName,
      lastFourDigits: lastFourDigits ?? this.lastFourDigits,
      brand: brand ?? this.brand,
      expiryDate: expiryDate ?? this.expiryDate,
      cardType: cardType ?? this.cardType,
      isDefault: isDefault ?? this.isDefault,
      cardToken: cardToken ?? this.cardToken,
      phone: phone ?? this.phone,
      docType: docType ?? this.docType,
      docNumber: docNumber ?? this.docNumber,
      email: email ?? this.email,
      methodType: methodType ?? this.methodType,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'holderName': holderName,
      'lastFourDigits': lastFourDigits,
      'brand': brand,
      'expiryDate': expiryDate,
      'cardType': cardType,
      'isDefault': isDefault,
      'cardToken': cardToken,
      'phone': phone,
      'docType': docType,
      'docNumber': docNumber,
      'email': email,
      'methodType': methodType,
      'createdAt': createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  factory PaymentCardEntity.fromMap(Map<String, dynamic> map, String docId) {
    return PaymentCardEntity(
      id: docId,
      userId: map['userId'] as String? ?? '',
      holderName: map['holderName'] as String? ?? 'TITULAR',
      lastFourDigits: map['lastFourDigits'] as String? ?? '0000',
      brand: map['brand'] as String? ?? 'visa',
      expiryDate: map['expiryDate'] as String? ?? '12/28',
      cardType: map['cardType'] as String? ?? 'Débito',
      isDefault: map['isDefault'] as bool? ?? false,
      cardToken: map['cardToken'] as String?,
      phone: map['phone'] as String?,
      docType: map['docType'] as String?,
      docNumber: map['docNumber'] as String?,
      email: map['email'] as String?,
      methodType: map['methodType'] as String? ?? 'card',
      createdAt: map['createdAt'] != null ? DateTime.tryParse(map['createdAt'] as String) : null,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        holderName,
        lastFourDigits,
        brand,
        expiryDate,
        cardType,
        isDefault,
        cardToken,
        phone,
        docType,
        docNumber,
        email,
        methodType,
      ];
}
