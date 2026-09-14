import 'package:customer_app/src/providers/customer_features_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('CustomerThemePersonalityProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to CustomerThemePersonality.classic (minimalist & professional)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final personality = container.read(customerThemePersonalityProvider);
      final isPinkie = container.read(isPinkieThemeActiveProvider);

      expect(personality, CustomerThemePersonality.classic);
      expect(isPinkie, isFalse);
    });

    test('can switch to CustomerThemePersonality.pinkie (for girls)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(customerThemePersonalityProvider.notifier);
      await notifier.setPersonality(CustomerThemePersonality.pinkie);

      expect(container.read(customerThemePersonalityProvider), CustomerThemePersonality.pinkie);
      expect(container.read(isPinkieThemeActiveProvider), isTrue);

      await notifier.setPersonality(CustomerThemePersonality.classic);
      expect(container.read(customerThemePersonalityProvider), CustomerThemePersonality.classic);
      expect(container.read(isPinkieThemeActiveProvider), isFalse);
    });

    test('toggle alternates between classic and pinkie', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(customerThemePersonalityProvider.notifier);
      expect(container.read(customerThemePersonalityProvider), CustomerThemePersonality.classic);

      notifier.toggle();
      expect(container.read(customerThemePersonalityProvider), CustomerThemePersonality.pinkie);

      notifier.toggle();
      expect(container.read(customerThemePersonalityProvider), CustomerThemePersonality.classic);
    });
  });
}
