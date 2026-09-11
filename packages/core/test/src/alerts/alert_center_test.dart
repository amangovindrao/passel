import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records whether the signal was played, so the foreground/background split
/// can be asserted without a real speaker or vibrator.
class _RecordingSignal implements AlertSignal {
  int plays = 0;
  int stops = 0;

  @override
  Future<void> play() async => plays++;

  @override
  Future<void> stop() async => stops++;
}

void main() {
  test('a foreground alert plays the signal — nothing else will', () async {
    final transport = InMemoryAlertTransport();
    final signal = _RecordingSignal();
    final center = AlertCenter(transport: transport, signal: signal);
    addTearDown(center.dispose);

    final received = <AlertMessage>[];
    center.alerts.listen(received.add);
    await center.start();

    transport.emit(
      const AlertMessage(
        kind: 'offer_fresh',
        delivery: AlertDelivery.foreground,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(signal.plays, 1);
  });

  test('a background alert does not double the OS notification', () async {
    final transport = InMemoryAlertTransport();
    final signal = _RecordingSignal();
    final center = AlertCenter(transport: transport, signal: signal);
    addTearDown(center.dispose);

    final received = <AlertMessage>[];
    center.alerts.listen(received.add);
    await center.start();

    transport.emit(
      const AlertMessage(
        kind: 'offer_fresh',
        delivery: AlertDelivery.background,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // The alert still arrives and still routes; it just does not make noise a
    // second time, since the notification channel already did.
    expect(received, hasLength(1));
    expect(signal.plays, 0);
  });

  test('acknowledge silences a repeating signal', () async {
    final transport = InMemoryAlertTransport();
    final signal = _RecordingSignal();
    final center = AlertCenter(transport: transport, signal: signal);
    addTearDown(center.dispose);

    await center.start();
    await center.acknowledge();

    expect(signal.stops, 1);
  });

  test('start is idempotent', () async {
    final transport = InMemoryAlertTransport();
    final center = AlertCenter(transport: transport);
    addTearDown(center.dispose);

    await center.start();
    await center.start();

    expect(transport.isStarted, isTrue);
  });

  group('AlertMessage.tryParse', () {
    test('reads kind and stringifies the rest', () {
      final alert = AlertMessage.tryParse({
        'kind': 'offer_fresh',
        'window_seconds': 35,
        'shop_name': 'Corner',
      }, delivery: AlertDelivery.foreground);

      expect(alert, isNotNull);
      expect(alert!.kind, 'offer_fresh');
      expect(alert.delivery, AlertDelivery.foreground);
      expect(alert['shop_name'], 'Corner');
      expect(alert.intOf('window_seconds'), 35);
      expect(alert.data.containsKey('kind'), isFalse);
    });

    test('a payload with no kind is not an alert', () {
      expect(
        AlertMessage.tryParse({
          'order_id': 'o1',
        }, delivery: AlertDelivery.foreground),
        isNull,
      );
      expect(
        AlertMessage.tryParse({'kind': ''}, delivery: AlertDelivery.foreground),
        isNull,
      );
    });

    test('intOf returns null for a non-numeric value', () {
      final alert = AlertMessage.tryParse({
        'kind': 'x',
        'detour_meters': 'lots',
      }, delivery: AlertDelivery.background);
      expect(alert!.intOf('detour_meters'), isNull);
      expect(alert.intOf('missing'), isNull);
    });
  });
}
