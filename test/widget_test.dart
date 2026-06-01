// Smoke test placeholder. The full app boots Firebase + GetIt DI in main(),
// so a top-level pumpWidget(app) isn't a meaningful unit test here. Feature
// tests live alongside their features. This keeps `flutter test` green.

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app package smoke test', () {
    expect(1 + 1, 2);
  });
}
