import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

/// User roles in the Paasel platform.
enum UserRole { customer, shopOwner, rider }

/// Domain model representing a platform user.
@freezed
abstract class User with _$User {
  const factory User({
    required String id,
    required String name,
    required String email,
    required String phone,
    required UserRole role,
    String? avatarUrl,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
