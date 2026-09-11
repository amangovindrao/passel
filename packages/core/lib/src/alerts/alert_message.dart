/// How an alert reached the app, which decides who is responsible for noise.
enum AlertDelivery {
  /// Arrived while the app was awake and on screen. No OS notification was
  /// shown, so nothing has caught the user's attention yet — the app must.
  foreground,

  /// Arrived as a notification while the app was backgrounded or closed, and
  /// the user tapped it. The OS already played the channel's sound; making
  /// more noise now would just be startling.
  background,
}

/// A single actionable alert, decoded from a push data message.
///
/// [kind] is the discriminator each app switches on to pick a surface. The
/// payload stays as a loose map because the wire format is owned by the
/// backend, and every app cares about a different subset of it.
class AlertMessage {
  const AlertMessage({
    required this.kind,
    required this.delivery,
    this.data = const <String, String>{},
  });

  /// Builds an alert from a push data payload. Returns null when the payload
  /// carries no `kind`, which is how non-alert data messages are ignored.
  static AlertMessage? tryParse(
    Map<String, dynamic> payload, {
    required AlertDelivery delivery,
  }) {
    final kind = payload['kind'];
    if (kind is! String || kind.isEmpty) return null;
    return AlertMessage(
      kind: kind,
      delivery: delivery,
      data: <String, String>{
        for (final entry in payload.entries)
          if (entry.key != 'kind') entry.key: '${entry.value}',
      },
    );
  }

  final String kind;
  final AlertDelivery delivery;
  final Map<String, String> data;

  String? operator [](String key) => data[key];

  int? intOf(String key) => int.tryParse(data[key] ?? '');

  @override
  String toString() => 'AlertMessage($kind, $delivery, $data)';
}
