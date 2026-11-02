import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'localization_service.dart';

/// Why Google's account chooser did not give an account, in words a person can act on.
class GoogleLoginProblem implements Exception {
  const GoogleLoginProblem(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The Google account chooser. The phone asks Google who the person is and gets an ID token back; the SERVER checks that token with
/// Google, so nothing the phone says about itself is believed.
class GoogleLogin {
  GoogleLogin._();

  /// The "Web application" OAuth client of this app (Google Cloud console). Tokens are made for it, and the server accepts only it.
  static const String webClientId = '427281190551-t67r5mg72ccnso67epg96srp3jkn36cg.apps.googleusercontent.com';

  static bool _ready = false;

  /// Shows Google's account chooser and returns the ID token of the account chosen, or null when the person backed out.
  /// Anything else that stops it is thrown as a [GoogleLoginProblem] that says what to do.
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
      final String? token = account.authentication.idToken;
      if (token == null) throw GoogleLoginProblem(explain(null, 'Google gave no ID token'));
      return token;
    } on GoogleSignInException catch (e) {
      debugPrint('Google sign-in failed: ${e.code} ${e.description}');
      // On Android, "no account could be offered" and "this app is not registered for Google sign-in" both come back as `canceled`.
      // Only a description that says the PERSON cancelled is treated as backing out.
      final String why = (e.description ?? '').toLowerCase();
      final bool backedOut = e.code == GoogleSignInExceptionCode.canceled && (why.contains('cancelled by the user') || why.contains('canceled by the user') || why.contains('user cancel'));
      if (backedOut) return null;
      throw GoogleLoginProblem(explain(e.code, e.description));
    }
  }

  /// A message for a failure: what it most likely is and what to do, with the technical code in brackets for whoever is helping.
  @visibleForTesting
  static String explain(final GoogleSignInExceptionCode? code, final String? description) {
    final bool sw = LocalizationService.instance.isSwahili;
    final String tech = ' (${code?.name ?? 'error'}${description == null || description.isEmpty ? '' : ': $description'})';
    switch (code) {
      case GoogleSignInExceptionCode.canceled:
        return (sw
                ? 'Google haikuweza kutoa akaunti. Ongeza akaunti ya Google kwenye simu (Settings, kisha Accounts) kisha jaribu tena. Kama akaunti ipo, app huenda haijasajiliwa na Google kwa funguo hizi za kusaini.'
                : 'Google could not offer an account. Add a Google account to the phone (Settings, then Accounts) and try again. If one is there, the app may not be registered with Google for this signing key.') +
            tech;
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return (sw
                ? 'Kuingia kwa Google hakujawekwa sawa kwenye simu hii (Google Play Services au usajili wa app).'
                : 'Sign-in with Google is not set up correctly on this phone (Google Play services or the app registration).') +
            tech;
      case GoogleSignInExceptionCode.interrupted:
      case GoogleSignInExceptionCode.uiUnavailable:
        return (sw ? 'Kuingia kwa Google kumekatizwa. Jaribu tena.' : 'Google sign-in was interrupted. Try again.') + tech;
      default:
        return (sw ? 'Kuingia kwa Google kumeshindikana. Jaribu tena.' : 'Google sign-in failed. Try again.') + tech;
    }
  }
}
