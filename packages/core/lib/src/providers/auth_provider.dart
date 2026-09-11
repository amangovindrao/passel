import 'package:core/src/models/user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the current authenticated user session.
///
/// `null` means no user is logged in.
final authSessionProvider = StateProvider<User?>((ref) => null);

/// Provides the current user's role, or null if not authenticated.
final currentUserRoleProvider = Provider<UserRole?>((ref) {
  return ref.watch(authSessionProvider)?.role;
});
