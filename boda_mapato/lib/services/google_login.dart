import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The Google account chooser. The phone asks Google who the person is and gets an ID token back; the SERVER checks that token with
/// Google, so nothing the phone says about itself is believed.
class GoogleLogin {
  GoogleLogin._();

  /// The "Web application" OAuth client of this app (Google Cloud console). Tokens are made for it, and the server accepts only it.
  static const String webClientId = '427281190551-t67r5mg72ccnso67epg96srp3jkn36cg.apps.googleusercontent.com';

  static bool _ready = false;

  /// Shows Google's account chooser and returns the ID token of the account chosen, or null when the person backed out.
  /// Any other failure (no Google services, no network, a wrong setup) is thrown for the caller to explain.
  static Future<String?> idToken() async {
    final GoogleSignIn google = GoogleSignIn.instance;
    if (!_ready) {
      await google.initialize(serverClientId: webClientId);
      _ready = true;
    }
    try {
      // Forget the last account so the chooser always appears (someone may share the phone, or own two accounts).
      await google.signOut();
      final GoogleSignInAccount account = await google.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      debugPrint('Google sign-in failed: ${e.code} ${e.description}');
      rethrow;
    }
  }
}
