import 'package:core/src/api/api_client.dart';
import 'package:core/src/errors/result.dart';
import 'package:core/src/models/group_order.dart';

/// Repository for Paasel Group Order sessions and Private Cart Mode.
class GroupOrderRepository {
  GroupOrderRepository(this._client);
  final ApiClient _client;

  /// Fetch full session details with authoritative backend Private Cart scrubbing.
  Future<Result<GroupOrderSessionModel>> fetchSession(String sessionId) =>
      _client.get<GroupOrderSessionModel>(
        '/api/v1/group-orders/$sessionId',
        fromJson: (data) =>
            GroupOrderSessionModel.fromJson(data as Map<String, dynamic>),
      );

  /// Create a new group order session.
  Future<Result<GroupOrderSessionModel>> createSession({
    required String societyName,
    String? deliveryAddressId,
    bool privateCartMode = false,
    int durationMinutes = 30,
  }) =>
      _client.post<GroupOrderSessionModel>(
        '/api/v1/group-orders',
        data: {
          'society_name': societyName,
          'delivery_address_id': deliveryAddressId,
          'private_cart_mode': privateCartMode,
          'duration_minutes': durationMinutes,
        },
        fromJson: (data) =>
            GroupOrderSessionModel.fromJson(data as Map<String, dynamic>),
      );

  /// Join an existing group order session.
  Future<Result<GroupOrderSessionModel>> joinSession(String sessionId) =>
      _client.post<GroupOrderSessionModel>(
        '/api/v1/group-orders/$sessionId/join',
        fromJson: (data) =>
            GroupOrderSessionModel.fromJson(data as Map<String, dynamic>),
      );

  /// Toggle Private Cart Mode ON or OFF for the entire session.
  Future<Result<Map<String, dynamic>>> togglePrivacy(
    String sessionId, {
    required bool enable,
    bool confirmDisable = false,
  }) =>
      _client.patch<Map<String, dynamic>>(
        '/api/v1/group-orders/$sessionId/privacy',
        data: {
          'enable': enable,
          'confirm_disable': confirmDisable,
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );

  /// Add or update an item in the caller's group cart.
  Future<Result<GroupOrderSessionModel>> addItem(
    String sessionId, {
    required String shopId,
    required String productId,
    required int qty,
  }) =>
      _client.post<GroupOrderSessionModel>(
        '/api/v1/group-orders/$sessionId/items',
        data: {
          'shop_id': shopId,
          'product_id': productId,
          'qty': qty,
        },
        fromJson: (data) =>
            GroupOrderSessionModel.fromJson(data as Map<String, dynamic>),
      );

  /// Remove an item from the caller's group cart.
  Future<Result<GroupOrderSessionModel>> removeItem(
    String sessionId,
    String itemId,
  ) =>
      _client.delete<GroupOrderSessionModel>(
        '/api/v1/group-orders/$sessionId/items/$itemId',
        fromJson: (data) =>
            GroupOrderSessionModel.fromJson(data as Map<String, dynamic>),
      );

  /// Lock the group order session.
  Future<Result<GroupOrderSessionModel>> lockSession(String sessionId) =>
      _client.post<GroupOrderSessionModel>(
        '/api/v1/group-orders/$sessionId/lock',
        fromJson: (data) =>
            GroupOrderSessionModel.fromJson(data as Map<String, dynamic>),
      );

  /// Pay for caller's individual cart in the group order session.
  Future<Result<GroupOrderSessionModel>> payCart(
    String sessionId, {
    int walletAmountToUsePaise = 0,
    String paymentMode = 'online',
  }) =>
      _client.post<GroupOrderSessionModel>(
        '/api/v1/group-orders/$sessionId/pay',
        data: {
          'wallet_amount_to_use_paise': walletAmountToUsePaise,
          'payment_mode': paymentMode,
        },
        fromJson: (data) =>
            GroupOrderSessionModel.fromJson(data as Map<String, dynamic>),
      );

  /// Group captain pays remaining balance for all unpaid members.
  Future<Result<GroupOrderSessionModel>> captainPayAll(
    String sessionId, {
    int walletAmountToUsePaise = 0,
    String paymentMode = 'online',
  }) =>
      _client.post<GroupOrderSessionModel>(
        '/api/v1/group-orders/$sessionId/captain-pay',
        data: {
          'wallet_amount_to_use_paise': walletAmountToUsePaise,
          'payment_mode': paymentMode,
        },
        fromJson: (data) =>
            GroupOrderSessionModel.fromJson(data as Map<String, dynamic>),
      );

  /// Execute package handover using OTP verification.
  Future<Result<Map<String, dynamic>>> handoverPackage(
    String sessionId, {
    required String packageId,
    required String verificationCode,
  }) =>
      _client.post<Map<String, dynamic>>(
        '/api/v1/group-orders/$sessionId/handover',
        data: {
          'package_id': packageId,
          'verification_code': verificationCode,
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );

  /// Recheck deadlines and release expired reservations.
  Future<Result<GroupOrderSessionModel>> recheckDeadlines(String sessionId) =>
      _client.post<GroupOrderSessionModel>(
        '/api/v1/group-orders/$sessionId/recheck-deadlines',
        fromJson: (data) =>
            GroupOrderSessionModel.fromJson(data as Map<String, dynamic>),
      );
}
