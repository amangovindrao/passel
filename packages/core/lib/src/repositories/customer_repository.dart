import 'package:core/src/api/api_client.dart';
import 'package:core/src/errors/result.dart';

/// Customer profile status.
class CustomerProfile {
  const CustomerProfile({required this.exists, this.name, this.userId});

  factory CustomerProfile.fromJson(Map<String, dynamic> json) =>
      CustomerProfile(
        exists: json['exists'] as bool,
        name: json['name'] as String?,
        userId: json['user_id'] as String?,
      );

  final bool exists;
  final String? name;
  final String? userId;
}

/// Repository for customer profile and onboarding.
class CustomerRepository {
  CustomerRepository(this._client);
  final ApiClient _client;

  Future<Result<CustomerProfile>> getProfile() =>
      _client.get<CustomerProfile>(
        '/api/v1/customers/profile',
        fromJson: (data) =>
            CustomerProfile.fromJson(data as Map<String, dynamic>),
      );

  Future<Result<Map<String, dynamic>>> createOrUpdateProfile({
    required String name,
  }) =>
      _client.post<Map<String, dynamic>>(
        '/api/v1/customers/profile',
        data: {'name': name},
        fromJson: (data) => data as Map<String, dynamic>,
      );
}
