import 'package:flutter_test/flutter_test.dart';

import 'package:wealthsync/services/finance_repository.dart';

/// Regression tests for the `ApiClient` helpers.
///
/// They originally looked like `_post(path, body) as Future<Map<String, dynamic>>`.
/// That cast can never succeed (`Future<dynamic>` is not a
/// `Future<Map<...>>`), so it threw immediately *and* orphaned the in-flight
/// response future — whose later failure then surfaced as an unhandled error.
/// Every ML call was therefore broken even with the backend running.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // NOTE: `ApiClient.instance` must be read inside a test body (not in the
  // `group` callback) so its `http.Client()` is created inside the test zone.
  group('ApiClient', () {
    test('predict attaches to the response instead of casting the Future',
        () async {
      // Under the test binding every request returns an empty 400 body, so the
      // real signal here is *which* error we get: a FormatException from
      // decoding proves the response future was awaited, whereas the old code
      // threw a TypeError on the cast and left the future unhandled.
      await expectLater(ApiClient.instance.predict('spending', const {'age_ref': 45.0}),
          throwsA(isA<FormatException>()));
    });

    test('explain attaches to the response instead of casting the Future',
        () async {
      await expectLater(ApiClient.instance.explain('risk', const {'AGE': 35.0}),
          throwsA(isA<FormatException>()));
    });
  });
}
