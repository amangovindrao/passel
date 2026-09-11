import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PaaselTheme', () {
    test('light theme uses Material 3', () {
      expect(PaaselTheme.light.useMaterial3, isTrue);
    });

    test('dark theme uses Material 3', () {
      expect(PaaselTheme.dark.useMaterial3, isTrue);
    });
  });
}
