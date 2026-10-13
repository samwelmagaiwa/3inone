/// API Configuration for different environments
/// This file manages API endpoints for the Boda Mapato app
library;

import "package:http/http.dart" as http;

mixin ApiConfig {
  // Environment enum
  // threeInOne = the new multi-business backend (3inone.nexoryatech.com).
  // production = the older depot backend. Change this one word to switch back.
  static const String _environment = Environment.threeInOne;

  // Toggle verbose HTTP logging in debug builds only
  static const bool enableHttpLogs = true;

  // Get base URL based on environment
  static String get baseUrl {
    switch (_environment) {
      case Environment.local:
        // Localhost/dev machine
        return "http://127.0.0.1:8000/api";
      case Environment.network:
        // LAN IP of the dev machine hosting Laravel (Wi-Fi IP)
        return "http://192.168.160.20:8000/api";
      case Environment.emulator:
        // Android emulator loopback to host
        return "http://10.0.2.2:8000/api";
      case Environment.production:
        return "https://depot.magrethschools.sc.tz/api";
      case Environment.threeInOne:
        return "https://3inone.nexoryatech.com/api";
      default:
        return "http://127.0.0.1:8000/api";
    }
  }

  // Get web base URL (without /api)
  static String get webBaseUrl {
    switch (_environment) {
      case Environment.local:
        return "http://127.0.0.1:8000";
      case Environment.network:
        return "http://192.168.160.20:8000";
      case Environment.emulator:
        return "http://10.0.2.2:8000";
      case Environment.production:
        return "https://depot.magrethschools.sc.tz";
      case Environment.threeInOne:
        return "https://3inone.nexoryatech.com";
      default:
        return "http://127.0.0.1:8000";
    }
  }

  // Connection timeout. Was 12s, which is shorter than MySQL's lock-wait
  // window on the backend -- a save queued behind another user's in-flight
  // transaction (e.g. two sales on the same product) could still be running
  // when this fired, showing the user a false "failed" error for a save
  // that actually succeeded. 30s gives the backend's own 15s lock-wait
  // timeout (config/database.php DB_LOCK_WAIT_TIMEOUT) room to surface a
  // real error first.
  static const Duration timeoutDuration = Duration(seconds: 30);

  // Headers
  static Map<String, String> get headers => <String, String>{
        "Content-Type": "application/json",
        "Accept": "application/json",
      };

  // Test connectivity
  static Future<bool> testConnectivity() async {
    try {
      final http.Response response = await http
          .get(
            Uri.parse("$baseUrl/health"),
            headers: headers,
          )
          .timeout(timeoutDuration);

      return response.statusCode == 200;
    } on Exception {
      return false;
    }
  }
}

// Environment constants
mixin Environment {
  // 127.0.1:8000 - for desktop/web development
  static const String local = "local";
  // 192.168.1.5:8000 - for real device testing
  static const String network = "network";
  // 10.0.2.2:8000 - for Android emulator
  static const String emulator = "emulator";
  // production server (older depot backend)
  static const String production = "production";
  // new multi-business backend, Docker image magaiwa/3inone-backend
  static const String threeInOne = "threeInOne";
}
