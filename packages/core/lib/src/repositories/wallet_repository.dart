import 'package:core/src/api/api_client.dart';
import 'package:core/src/errors/result.dart';

/// Single immutable transaction in the wallet ledger.
class WalletTransactionItem {
  const WalletTransactionItem({
    required this.id,
    required this.type,
    required this.direction,
    required this.amountPaise,
    this.status = 'COMPLETED',
    this.orderId,
    this.description,
    this.deliveryReference,
    this.createdAt,
  });

  factory WalletTransactionItem.fromJson(Map<String, dynamic> json) =>
      WalletTransactionItem(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? '',
        direction: (json['direction'] as String? ?? 'CREDIT').toUpperCase(),
        amountPaise: (json['amount_paise'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? 'COMPLETED',
        orderId: json['order_id'] as String?,
        description: json['description'] as String?,
        deliveryReference: json['delivery_reference'] as String?,
        createdAt: json['created_at'] as String?,
      );

  final String id;
  final String type;
  final String direction;
  final String status;
  final int amountPaise;
  final String? orderId;
  final String? description;
  final String? deliveryReference;
  final String? createdAt;

  bool get isCredit => direction == 'CREDIT';
  double get amountRupees => amountPaise / 100.0;
}

/// Wallet balance and transaction ledger.
class WalletData {
  const WalletData({
    required this.walletId,
    required this.balancePaise,
    required this.ownerType,
    this.transactions = const [],
  });

  factory WalletData.fromJson(Map<String, dynamic> json) => WalletData(
        walletId: json['wallet_id'] as String? ?? '',
        balancePaise: (json['balance_paise'] as num?)?.toInt() ?? 0,
        ownerType: json['owner_type'] as String? ?? 'user',
        transactions: (json['transactions'] as List?)
                ?.map((e) =>
                    WalletTransactionItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  final String walletId;
  final int balancePaise;
  final String ownerType;
  final List<WalletTransactionItem> transactions;

  double get balanceRupees => balancePaise / 100.0;
}

/// Repository for the shared Paasel wallet and ledger.
class WalletRepository {
  WalletRepository(this._client);
  final ApiClient _client;

  Future<Result<WalletData>> getWallet({int limit = 20, int offset = 0}) =>
      _client.get<WalletData>(
        '/api/v1/wallets',
        queryParameters: {
          'limit': limit.toString(),
          'offset': offset.toString(),
        },
        fromJson: (data) => WalletData.fromJson(data as Map<String, dynamic>),
      );
}
