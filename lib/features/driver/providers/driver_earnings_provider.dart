// lib/features/driver/providers/driver_earnings_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_notifier.dart';

// ─── Entidad Ganancia ────────────────────────────────────────────────────────
class EarningEntry {
  const EarningEntry({
    required this.id,
    required this.orderId,
    required this.amount,
    required this.date,
    this.customerAddress = '',
    this.orderTotal = 0,
  });

  final String id;
  final String orderId;
  final double amount;
  final DateTime date;
  final String customerAddress;
  final double orderTotal;
}

// ─── Entidad Cuenta Bancaria ─────────────────────────────────────────────────
class BankAccount {
  const BankAccount({
    this.bank = '',
    this.accountNumber = '',
    this.accountType = 'Ahorros',
    this.holderName = '',
    this.documentNumber = '',
  });

  final String bank;
  final String accountNumber;
  final String accountType;
  final String holderName;
  final String documentNumber;

  factory BankAccount.fromMap(Map<String, dynamic> map) => BankAccount(
        bank: map['bank'] as String? ?? '',
        accountNumber: map['accountNumber'] as String? ?? '',
        accountType: map['accountType'] as String? ?? 'Ahorros',
        holderName: map['holderName'] as String? ?? '',
        documentNumber: map['documentNumber'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'bank': bank,
        'accountNumber': accountNumber,
        'accountType': accountType,
        'holderName': holderName,
        'documentNumber': documentNumber,
      };

  bool get isComplete =>
      bank.isNotEmpty &&
      accountNumber.isNotEmpty &&
      holderName.isNotEmpty &&
      documentNumber.isNotEmpty;
}

// ─── Estado ──────────────────────────────────────────────────────────────────
class DriverEarningsState {
  const DriverEarningsState({
    this.entries = const [],
    this.totalEarned = 0,
    this.totalDeliveries = 0,
    this.bankAccount = const BankAccount(),
    this.isLoading = false,
    this.isSavingBank = false,
    this.errorMessage,
  });

  final List<EarningEntry> entries;
  final double totalEarned;
  final int totalDeliveries;
  final BankAccount bankAccount;
  final bool isLoading;
  final bool isSavingBank;
  final String? errorMessage;

  double get todayEarnings {
    final today = DateTime.now();
    return entries
        .where((e) =>
            e.date.year == today.year &&
            e.date.month == today.month &&
            e.date.day == today.day)
        .fold(0.0, (acc, e) => acc + e.amount);
  }

  double get weekEarnings {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return entries
        .where((e) => e.date.isAfter(cutoff))
        .fold(0.0, (acc, e) => acc + e.amount);
  }

  DriverEarningsState copyWith({
    List<EarningEntry>? entries,
    double? totalEarned,
    int? totalDeliveries,
    BankAccount? bankAccount,
    bool? isLoading,
    bool? isSavingBank,
    String? errorMessage,
  }) =>
      DriverEarningsState(
        entries: entries ?? this.entries,
        totalEarned: totalEarned ?? this.totalEarned,
        totalDeliveries: totalDeliveries ?? this.totalDeliveries,
        bankAccount: bankAccount ?? this.bankAccount,
        isLoading: isLoading ?? this.isLoading,
        isSavingBank: isSavingBank ?? this.isSavingBank,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ─── Notifier ────────────────────────────────────────────────────────────────
class DriverEarningsNotifier extends StateNotifier<DriverEarningsState> {
  DriverEarningsNotifier(this.ref) : super(const DriverEarningsState());

  final Ref ref;
  final _db = FirebaseFirestore.instance;

  Future<void> loadEarnings() async {
    final driverId = ref.read(authNotifierProvider).user?.id;
    if (driverId == null || driverId.isEmpty) return;

    state = state.copyWith(isLoading: true);

    try {
      // Cargar resumen
      final summaryDoc = await _db
          .collection('users')
          .doc(driverId)
          .collection('earnings')
          .doc('__summary__')
          .get();

      double totalEarned = 0;
      int totalDeliveries = 0;
      if (summaryDoc.exists) {
        final d = summaryDoc.data()!;
        totalEarned = (d['totalEarned'] as num? ?? 0).toDouble();
        totalDeliveries = (d['totalDeliveries'] as num? ?? 0).toInt();
      }

      // Cargar entradas recientes (últimos 30 días)
      final cutoff = DateTime.now().subtract(const Duration(days: 30));
      final snap = await _db
          .collection('users')
          .doc(driverId)
          .collection('earnings')
          .where('date', isGreaterThan: Timestamp.fromDate(cutoff))
          .orderBy('date', descending: true)
          .where(FieldPath.documentId, isNotEqualTo: '__summary__')
          .get();

      final entries = snap.docs
          .map((doc) {
            final d = doc.data();
            return EarningEntry(
              id: doc.id,
              orderId: d['orderId'] as String? ?? '',
              amount: (d['amount'] as num? ?? 0).toDouble(),
              date: (d['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
              customerAddress: d['customerAddress'] as String? ?? '',
              orderTotal: (d['orderTotal'] as num? ?? 0).toDouble(),
            );
          })
          .toList();

      // Cargar cuenta bancaria
      final userDoc = await _db.collection('users').doc(driverId).get();
      final bankData = userDoc.data()?['bankAccount'] as Map<String, dynamic>?;
      final bankAccount =
          bankData != null ? BankAccount.fromMap(bankData) : const BankAccount();

      state = state.copyWith(
        entries: entries,
        totalEarned: totalEarned,
        totalDeliveries: totalDeliveries,
        bankAccount: bankAccount,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error cargando ganancias: $e',
      );
    }
  }

  /// Guarda los datos de la cuenta bancaria en Firestore.
  Future<bool> saveBankAccount(BankAccount account) async {
    final driverId = ref.read(authNotifierProvider).user?.id;
    if (driverId == null || driverId.isEmpty) return false;

    state = state.copyWith(isSavingBank: true);
    try {
      await _db.collection('users').doc(driverId).set({
        'bankAccount': account.toMap(),
        'bankUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      state = state.copyWith(bankAccount: account, isSavingBank: false);
      return true;
    } catch (e) {
      state = state.copyWith(isSavingBank: false, errorMessage: 'Error guardando cuenta: $e');
      return false;
    }
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────
final driverEarningsProvider =
    StateNotifierProvider<DriverEarningsNotifier, DriverEarningsState>(
  (ref) => DriverEarningsNotifier(ref),
);
