import 'dart:async';

import 'package:boda_mapato/screens/auth/register_business_screen.dart';

/// Every test file runs with this setup. The registration form asks for the business's captured location (required in the real app); the
/// many tests that fill the form in to check something else do not stand at a business, so it is off here and the tests about the location
/// itself (test/registration_point_test.dart) switch it back on.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  RegisterBusinessScreen.requireLocation = false;
  await testMain();
}
