import 'package:core/src/api/api_client.dart';
import 'package:core/src/errors/result.dart';

/// The roles an app may register its own user as.
///
/// Admin is absent on purpose: it is granted out of band, never claimed by a
/// client. Each app hard-codes exactly one of these.
enum PaaselRole {
  customer('customer'),
  shopOwner('shop_owner'),
  deliveryPartner('delivery_partner');

  const PaaselRole(this.wire);

  final String wire;
}

typedef PasselRole = PaaselRole;

/// Outcome of registering. [created] is false when the account already existed,
/// which is the normal case on every launch after the first.
class Registration {
  const Registration({
    required this.userId,
    required this.role,
    required this.created,
    this.roles = const [],
  });

  factory Registration.fromJson(Map<String, dynamic> json) => Registration(
    userId: json['user_id'] as String? ?? '',
    role: json['role'] as String? ?? '',
    created: json['created'] as bool? ?? false,
    roles: (json['roles'] as List?)?.map((e) => e.toString()).toList() ?? [],
  );

  final String userId;
  final String role;
  final bool created;
  final List<String> roles;

  bool hasRole(String targetRole) =>
      role == targetRole || roles.contains(targetRole);
}

/// Whether this Supabase identity has an account on the Paasel backend.
class RegistrationStatus {
  const RegistrationStatus({
    required this.registered,
    this.role,
    this.roles = const [],
  });

  factory RegistrationStatus.fromJson(Map<String, dynamic> json) =>
      RegistrationStatus(
        registered: json['registered'] as bool? ?? false,
        role: json['role'] as String?,
        roles:
            (json['roles'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );

  final bool registered;
  final String? role;
  final List<String> roles;

  bool hasRole(String targetRole) =>
      role == targetRole || roles.contains(targetRole);
}

/// Bridges a Supabase login to a Paasel account.
///
/// Supabase proves who someone is; it cannot give them a role here. Until
/// [register] has run, every other endpoint answers 401 `registration_required`
/// — so the apps call this immediately after OTP, and again on launch if the
/// status says it never completed.
class AuthRepository {
  AuthRepository(this._client);

  final ApiClient _client;

  Future<Result<Registration>> register({
    required String name,
    required PaaselRole role,
  }) => _client.post<Registration>(
    '/api/v1/auth/register',
    data: {'name': name, 'role': role.wire},
    fromJson: (data) => Registration.fromJson(data as Map<String, dynamic>),
  );

  Future<Result<RegistrationStatus>> status() =>
      _client.get<RegistrationStatus>(
        '/api/v1/auth/registration-status',
        fromJson: (data) =>
            RegistrationStatus.fromJson(data as Map<String, dynamic>),
      );
}
