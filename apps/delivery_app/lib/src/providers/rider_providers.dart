import 'package:core/core.dart';
import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:delivery_app/src/services/document_uploader.dart';
import 'package:delivery_app/src/services/location_reporter.dart';
import 'package:delivery_app/src/services/offer_poller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- Infrastructure ---

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final locationReporterProvider = Provider<LocationReporter>((ref) {
  final reporter = LocationReporter(client: ref.watch(apiClientProvider));
  ref.onDispose(reporter.stop);
  return reporter;
});

/// KYC document capture and storage. Overridden in tests so the picker and the
/// storage bucket are never touched.
final documentUploaderProvider = Provider<DocumentUploader>(
  (ref) => DocumentUploader(),
);

/// Phone OTP send and verify. Behind a provider so onboarding is testable
/// without a live Supabase instance.
final phoneAuthProvider = Provider<PhoneAuth>((ref) => PhoneAuth());

/// Root-level alert plumbing. Overridden in main() with the real FCM transport,
/// and in tests with an in-memory one.
final alertCenterProvider = Provider<AlertCenter>((ref) {
  final center = AlertCenter(
    transport: InMemoryAlertTransport(),
    signal: PlatformAlertSignal(),
  );
  ref.onDispose(center.dispose);
  return center;
});

// --- Paasel Shared Wallet & Ledger ---

final walletRepositoryProvider = Provider<WalletRepository>(
  (ref) => WalletRepository(ref.watch(apiClientProvider)),
);

final walletDataProvider = FutureProvider.autoDispose<WalletData>((ref) async {
  final repo = ref.watch(walletRepositoryProvider);
  final result = await repo.getWallet();
  return result.when(
    success: (WalletData data) => data,
    failure: (AppError error) => throw error,
  );
});

// --- Rider identity & verification ---

final riderDataProvider = FutureProvider.autoDispose<RiderData>((ref) async {
  final client = ref.watch(apiClientProvider);
  final result = await client.get<Map<String, dynamic>>(
    '/api/v1/delivery-partners/me',
    fromJson: (d) => d as Map<String, dynamic>,
  );
  return result.when(
    success: RiderData.fromJson,
    failure: (AppError e) => throw e,
  );
});

/// Just the verification state, for the route guard and the online gate.
final riderKycStatusProvider = Provider.autoDispose<String?>(
  (ref) => ref.watch(riderDataProvider).valueOrNull?.kycStatus,
);

// --- Location permission ---

final locationAccessProvider =
    StateNotifierProvider<LocationAccessNotifier, LocationAccess>(
      (ref) => LocationAccessNotifier(ref.watch(locationReporterProvider)),
    );

class LocationAccessNotifier extends StateNotifier<LocationAccess> {
  LocationAccessNotifier(this._reporter) : super(LocationAccess.unknown);

  final LocationReporter _reporter;

  /// Re-reads the real OS state. Worth calling on resume: the rider may have
  /// changed the grant in Settings while the app was backgrounded.
  Future<void> refresh() async {
    state = await _reporter.currentAccess();
  }

  Future<void> request() async {
    state = await _reporter.request();
  }

  Future<void> openSettings() => _reporter.openSettings();
}

// --- Online/offline, welded to the location service ---

class OnlineState {
  const OnlineState({
    this.isOnline = false,
    this.busy = false,
    this.blockedReason,
  });

  final bool isOnline;
  final bool busy;

  /// Why the last attempt was refused, e.g. the server's 409 while a delivery
  /// is in progress. Surfaced to the rider; never silently swallowed.
  final String? blockedReason;

  OnlineState copyWith({
    bool? isOnline,
    bool? busy,
    String? blockedReason,
    bool clearReason = false,
  }) => OnlineState(
    isOnline: isOnline ?? this.isOnline,
    busy: busy ?? this.busy,
    blockedReason: clearReason ? null : (blockedReason ?? this.blockedReason),
  );
}

/// Owns the toggle state *and* the background location service as one unit.
///
/// These must never drift apart. A rider marked online with no reporter running
/// is invisible to matching but thinks they are working; a reporter running
/// after going offline is a battery and privacy problem. Both directions are
/// bugs, so both live behind this single notifier.
class OnlineStatusNotifier extends StateNotifier<OnlineState> {
  OnlineStatusNotifier({
    required ApiClient client,
    required LocationReporter reporter,
  }) : _client = client,
       _reporter = reporter,
       super(const OnlineState());

  final ApiClient _client;
  final LocationReporter _reporter;

  /// Adopts the server's view on load, without touching the toggle's meaning.
  /// Never trust a cached flag: the stale-online sweep may have flipped it.
  void hydrate(RiderData data) {
    if (state.busy) return;
    state = state.copyWith(isOnline: data.isOnline, clearReason: true);
    if (data.isOnline && !_reporter.isRunning) {
      // The server says online but nothing is reporting — reconcile by
      // actually starting the loop rather than leaving a lie on screen.
      _reporter.start().ignore();
    }
  }

  Future<void> goOnline() async {
    if (state.busy || state.isOnline) return;
    state = state.copyWith(busy: true, clearReason: true);

    final result = await _client.post<Map<String, dynamic>>(
      '/api/v1/delivery-partners/online',
      data: {'is_online': true},
      fromJson: (d) => d as Map<String, dynamic>,
    );

    final failure = result.when(
      success: (Map<String, dynamic> _) => null,
      failure: (AppError e) => e,
    );

    if (failure != null) {
      state = state.copyWith(
        busy: false,
        blockedReason: _messageFor(failure, fallback: 'Could not go online'),
      );
      return;
    }

    // Server now believes we are available, so the pings had better start. If
    // they cannot, roll the server back rather than sit in the exact stuck
    // state the stale-online sweep exists to clean up.
    try {
      await _reporter.start();
    } on LocationPermissionRequired catch (e) {
      await _forceOfflineOnServer();
      state = state.copyWith(busy: false, blockedReason: e.message);
      return;
    }

    state = state.copyWith(isOnline: true, busy: false, clearReason: true);
  }

  Future<void> goOffline() async {
    if (state.busy || !state.isOnline) return;
    state = state.copyWith(busy: true, clearReason: true);

    // Ask first, stop second. A refusal must leave the toggle — and the pings —
    // exactly as they were, so the UI never drifts from the server.
    final result = await _client.post<Map<String, dynamic>>(
      '/api/v1/delivery-partners/online',
      data: {'is_online': false},
      fromJson: (d) => d as Map<String, dynamic>,
    );

    final failure = result.when(
      success: (Map<String, dynamic> _) => null,
      failure: (AppError e) => e,
    );

    if (failure != null) {
      state = state.copyWith(
        busy: false,
        blockedReason: _messageFor(
          failure,
          fallback: 'Finish your current delivery first',
        ),
      );
      return;
    }

    await _reporter.stop();
    state = const OnlineState();
  }

  void clearBlockedReason() => state = state.copyWith(clearReason: true);

  Future<void> _forceOfflineOnServer() async {
    await _client.post<Map<String, dynamic>>(
      '/api/v1/delivery-partners/online',
      data: {'is_online': false},
      fromJson: (d) => d as Map<String, dynamic>,
    );
  }

  static String _messageFor(AppError error, {required String fallback}) {
    final message = error.message.trim();
    return message.isEmpty ? fallback : message;
  }
}

final onlineStatusProvider =
    StateNotifierProvider<OnlineStatusNotifier, OnlineState>(
      (ref) => OnlineStatusNotifier(
        client: ref.watch(apiClientProvider),
        reporter: ref.watch(locationReporterProvider),
      ),
    );

// --- Offers ---

/// The offer currently on screen, fresh or detour, or null for none.
///
/// Root-level and not auto-disposed: an offer can land while the rider is
/// anywhere in the app, and it must survive the navigation it triggers.
final currentOfferProvider = StateProvider<RiderOffer?>((ref) => null);

/// Tier 1 additions. Consent-free and non-blocking, so this is a banner
/// message rather than anything that interrupts the rider.
final batchAddedNoticeProvider = StateProvider<String?>((ref) => null);

/// The assignment the rider is committed to. Drives the dashboard's locked
/// state and the active-delivery screen.
final activeAssignmentProvider = StateProvider<ActiveAssignment?>(
  (ref) => null,
);

/// True when the dashboard must show the locked card instead of the toggle.
final isOnDeliveryProvider = Provider<bool>(
  (ref) => ref.watch(activeAssignmentProvider) != null,
);

/// Polls for a waiting offer while the rider is online.
///
/// Runs only between going online and going offline: an offer cannot exist
/// outside that window — matching requires the online flag and a recent ping,
/// and going offline releases anything unanswered — so polling while off duty
/// would spend battery to learn nothing.
///
/// The two subscriptions below are the whole of its lifecycle, which is why
/// they live here rather than inside the poller: the poller stays a plain
/// object with no Riverpod in it, and the rules about when it runs stay in one
/// place.
final offerPollerProvider = Provider<OfferPoller>((ref) {
  final poller = OfferPoller(
    client: ref.watch(apiClientProvider),
    readOffer: () => ref.read(currentOfferProvider),
    writeOffer: (offer) =>
        ref.read(currentOfferProvider.notifier).state = offer,
  );

  ref
    ..listen<OnlineState>(onlineStatusProvider, (_, next) {
      if (next.isOnline) {
        poller.start();
      } else {
        poller.stop();
      }
    }, fireImmediately: true)
    // Whatever cleared the offer — accepted, declined, or its ring ran out —
    // the poller must not put it back while the server catches up.
    ..listen<RiderOffer?>(currentOfferProvider, (previous, next) {
      if (previous != null && next == null) {
        poller.markSettled(previous.assignmentId);
      }
    })
    ..onDispose(poller.stop);

  return poller;
});

/// Dedicated shop code when rider chooses to deliver exclusively for a single store.
final dedicatedShopCodeProvider = StateProvider<String?>((ref) => null);

