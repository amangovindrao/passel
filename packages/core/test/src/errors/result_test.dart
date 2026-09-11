import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Result', () {
    test('Success.when returns success branch', () {
      const result = Result<int>.success(42);
      final value = result.when(
        success: (v) => v,
        failure: (_) => -1,
      );
      expect(value, 42);
    });

    test('Failure.when returns failure branch', () {
      const result = Result<int>.failure(
        NetworkError(message: 'timeout'),
      );
      final value = result.when(
        success: (v) => v,
        failure: (e) => -1,
      );
      expect(value, -1);
    });
  });
}
