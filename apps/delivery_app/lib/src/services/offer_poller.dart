import 'dart:async';

import 'package:core/core.dart';
import 'package:delivery_app/src/providers/rider_models.dart';

/// Asks the server whether an offer is waiting, for as long as the rider is
/// online.
///
/// Push is the only channel that can reach a backgrounded phone, so it stays
/// the primary route. It is not, however, a channel anything should depend on
/// alone: a device token rotates, a notification is dropped, Firebase is not
/// configured on this build, or the app is simply opened a moment after the
/// offer was made. In every one of those cases the assignment is sitting on
/// the server and the rider has been told nothing — and an offer nobody sees
/// is indistinguishable, to them, from no work being available.
///
/// So this is the pull half of the same fact. It writes into the exact state
/// the push route writes into, which means the offer card, its countdown and
/// its accept do not know or care which one woke them.
class OfferPoller {
  OfferPoller({
    required ApiClient client,
    required RiderOffer? Function() readOffer,
    required void Function(RiderOffer?) writeOffer,
    Duration interval = const Duration(seconds: 4),
  }) : _client = client,
       _readOffer = readOffer,
       _writeOffer = writeOffer,
       _interval = interval;

  static const path = '/api/v1/delivery-partners/me/offer';

  final ApiClient _client;
  final RiderOffer? Function() _readOffer;
  final void Function(RiderOffer?) _writeOffer;
  final Duration _interval;

  Timer? _timer;
  bool _inFlight = false;

  /// Offers the rider has already answered, or that lapsed on screen. Kept so a
  /// server that has not caught up yet cannot put a dead card back.
  final _settled = <String>{};

  /// When the most recent offer was settled. Used to discard replies that were
  /// already in the air at that moment.
  DateTime? _settledAt;

  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(_interval, (_) => poll());
    // Poll straight away. An offer may already be waiting — going online is
    // exactly when a rider is most likely to be handed one — and making them
    // watch an empty screen for a full interval reads as the app being broken.
    poll();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Stop offering this assignment, whatever the server still says about it.
  void markSettled(String assignmentId) {
    _settled.add(assignmentId);
    _settledAt = DateTime.now();
  }

  /// One round trip. Safe to call at any time; overlapping calls are dropped.
  Future<void> poll() async {
    if (_inFlight) return;
    _inFlight = true;
    final startedAt = DateTime.now();
    try {
      final result = await _client.get<Map<String, dynamic>>(
        path,
        fromJson: (d) => d as Map<String, dynamic>,
      );
      final body = result.when(
        success: (Map<String, dynamic> data) => data,
        // A poll that fails is not worth telling the rider about — the next one
        // is four seconds away, and a connectivity banner belongs elsewhere.
        failure: (AppError _) => null,
      );
      if (body != null) _apply(body, startedAt: startedAt);
    } finally {
      _inFlight = false;
    }
  }

  void _apply(Map<String, dynamic> body, {required DateTime startedAt}) {
    // This reply left before the rider answered, so it describes a world that
    // no longer exists. Re-showing an accepted offer is worse than losing a
    // poll.
    final settledAt = _settledAt;
    if (settledAt != null && startedAt.isBefore(settledAt)) return;

    final json = body['offer'] as Map<String, dynamic>?;
    final current = _readOffer();

    if (json == null) {
      // Withdrawn, expired, or handed to someone closer. Take it off screen
      // rather than let the rider accept into a 409.
      if (current != null) _writeOffer(null);
      return;
    }

    final offer = RiderOffer.fromJson(json);
    if (_settled.contains(offer.assignmentId)) return;
    // Same offer as the one already up. Writing it again would restart the
    // countdown ring on every poll and the window would never close.
    if (current?.assignmentId == offer.assignmentId) return;

    _writeOffer(offer);
  }
}
