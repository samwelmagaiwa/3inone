import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/login_response.dart';
import '../models/user_permissions.dart';
import '../services/api_service.dart';
import '../services/app_messenger.dart';
import '../services/auth_events.dart';
import '../services/auth_service.dart';
import '../services/localization_service.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider() {
    // Listen for global unauthorized events
    _authSub = AuthEvents.instance.stream.listen((event) async {
      if (event == AuthEvent.unauthorized) {
        await _handleUnauthorized();
      }
    });
  }

  UserData? _user;
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _error;
  String? _errorMessage;
  String? _lastErrorCode;
  
  // Support Contact Detail Cache
  String? _supportPhone;
  String? _supportEmail;

  late final StreamSubscription<AuthEvent> _authSub;
  Timer? _refreshTimer;

  // Background refresh interval — 5 min is frequent enough to catch
  // permission changes while avoiding a network hit every 60 seconds.
  static const Duration _refreshInterval = Duration(minutes: 5);
  // Rotate the API token about once a day (24h / refresh interval).
  static const int _renewEveryTicks = 24 * 60 ~/ 5;

  // Getters
  UserData? get user => _user;

  /// The user's effective permissions: role defaults UNION the explicit
  /// grants an admin gave them (the server's effective_permissions). Every
  /// screen should gate on this -- not on the role alone -- so a permission
  /// granted in the permission management screen actually takes effect, and
  /// so the client agrees with what the server enforces.
  UserPermissions get permissions {
    final UserData? u = _user;
    if (u == null) return const UserPermissions.empty();
    return UserPermissions.fromUser(
      userRole: u.role,
      explicitGrants: u.permissions,
    );
  }
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get errorMessage => _errorMessage;
  String? get lastErrorCode => _lastErrorCode;

  // Contact Getters (Database-only)
  String get supportPhone => _supportPhone ?? "";
  String get supportEmail => _supportEmail ?? "";

  @override
  void dispose() {
    _stopRefreshTimer();
    _authSub.cancel();
    super.dispose();
  }

  void _startRefreshTimer() {
    _stopRefreshTimer();
    if (_isAuthenticated && !kIsWeb) {
      _refreshTimer = Timer.periodic(_refreshInterval, (timer) {
        refreshUser();
        // Keep the server-side token lifetime rolling for sessions left open for days.
        if (timer.tick % _renewEveryTicks == 0) {
          unawaited(_renewToken());
        }
      });
    }
  }

  /// Swaps the stored API token for a fresh one (on every app start, and daily while open).
  /// The server no longer expires a token by age: a device stays signed in for as long as it
  /// is used, however many other devices the same account is signed in on. Renewing only keeps
  /// the token fresh. A failure is harmless: the current token keeps working.
  Future<void> _renewToken() async {
    try {
      await AuthService.refreshToken();
    } on Exception catch (e) {
      debugPrint("Token renewal skipped: $e");
    }
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  // Initialize auth state
  Future<void> initialize() async {
    _setLoading(true);
    try {
      _isAuthenticated = await AuthService.isAuthenticated();
      if (_isAuthenticated) {
        // Load cached data immediately for fast startup, then fetch fresh from server.
        final Map<String, dynamic>? cached = await AuthService.getUserData();
        if (cached != null) {
          _user = UserData.fromJson(cached);
        }

        // Fetch fresh user data from server; this also saves to cache.
        final Map<String, dynamic>? fresh = await AuthService.getCurrentUser();
        if (fresh != null) {
          _user = UserData.fromJson(fresh);
        }

        if (_user != null) {
          _startRefreshTimer();
          unawaited(_renewToken());
        } else {
          // Token exists locally but server rejected it — clear local state.
          await AuthService.clearAuthData();
          _isAuthenticated = false;
        }

        // Fire-and-forget: support contact fetch doesn't block the UI.
        unawaited(fetchSuperAdminContact());
      }
    } on Exception catch (e) {
      _setError("Failed to initialize auth: $e");
    } finally {
      _setLoading(false);
    }
  }

  // Login (direct authentication)
  Future<bool> login({
    required final String email,
    required final String password,
    required final String phoneNumber,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      // Preflight connectivity check to provide a clear error if backend is unreachable
      final api = ApiService();
      final bool serverUp = await api.testConnectivity();
      if (!serverUp) {
        final String url = ApiService.baseUrl;
        // The "same network / port 8000" wording only makes sense for a
        // local dev backend (127.0.0.1 / 192.168.x / the 10.0.2.2 emulator
        // loopback) -- pointing a user at production (a public HTTPS
        // domain) toward those steps sends them troubleshooting the wrong
        // thing. Only show it for the addresses it's actually true for.
        final bool isLocalBackend = url.contains('127.0.0.1') ||
            url.contains('10.0.2.2') ||
            url.contains('192.168.');
        final String msg = isLocalBackend
            ? 'Seva haipatikani: $url/health. Hakikisha simu yako na kompyuta yako ziko kwenye mtandao mmoja na bandari 8000 inaruhusiwa.'
            : 'Seva haipatikani: $url/health. Hakikisha kifaa chako kina intaneti inayofanya kazi, kisha jaribu tena.';
        _setError(msg);
        _errorMessage = msg;
        return false;
      }

      final Map<String, dynamic> response = await AuthService.login(
        email: email,
        password: password,
        phoneNumber: phoneNumber,
      );

      // Extract token and optimistically save it
      final Map<String, dynamic>? responseData =
          response["data"] as Map<String, dynamic>?;
      final String? token = responseData != null
          ? responseData["token"] as String?
          : response["token"] as String?;
      if (token != null && token.isNotEmpty) {
        await AuthService.saveToken(token);
      }

      // Fetch fresh user profile from backend using the token we just saved
      final Map<String, dynamic>? freshUser =
          await AuthService.getCurrentUser();
      if (freshUser == null) {
        throw Exception(
            "Imeshindikana kupata taarifa za mtumiaji baada ya kuingia.");
      }
      _user = UserData.fromJson(freshUser);

      _isAuthenticated = true;
      _startRefreshTimer();

      // Force service selection after every successful login by clearing any previous choice
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.remove('selected_service');
      } on Exception catch (_) {
        // ignore storage errors
      }

      notifyListeners();
      return true;
    } on AuthHttpException catch (e) {
      _lastErrorCode = e.code;
      _setError(e.message);
      _errorMessage = e.message;
      return false;
    } on Exception catch (e) {
      _lastErrorCode = null;
      _setError(e.toString());
      _errorMessage = e.toString();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Logout
  Future<void> logout() async {
    _setLoading(true);

    try {
      await AuthService.logout();
    } on Exception catch (e) {
      // Continue with logout even if server request fails
      debugPrint("Logout error: $e");
    } finally {
      _stopRefreshTimer();
      // Clear any persisted service choice so next login requires selection
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.remove('selected_service');
      } on Exception catch (_) {
        // ignore storage errors
      }

      _user = null;
      _isAuthenticated = false;
      _clearError();
      _setLoading(false);
    }
  }

  bool _verifyingSession = false;

  Future<void> _handleUnauthorized() async {
    // Several requests can come back 401 together; verify once, not per request.
    if (_verifyingSession) return;
    _verifyingSession = true;
    try {
      await _verifyOrEndSession();
    } finally {
      _verifyingSession = false;
    }
  }

  Future<void> _verifyOrEndSession() async {
    // A 401 on one endpoint is not proof the session is gone, so ask the server
    // directly. Only a definite 401 here ends the session -- a timeout, no
    // signal or a 5xx must NOT sign the user out (they would lose what they
    // are typing because of a bad connection, not a bad session).
    try {
      final Map<String, dynamic>? check = await AuthService.getCurrentUser();
      if (check != null) {
        _user = UserData.fromJson(check);
        notifyListeners();
      }
      return; // the server accepted the token: the earlier 401 was transient
    } on Exception catch (e) {
      if (!AuthService.isSessionInvalid(e)) {
        debugPrint("Session check inconclusive, staying signed in: $e");
        return;
      }
    }

    try {
      await AuthService.clearAuthData();
    } on Exception {
      // ignore
    }
    // Clear any persisted service choice so next login requires selection
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('selected_service');
    } on Exception catch (_) {
      // ignore storage errors
    }
    _user = null;
    _isAuthenticated = false;
    _error = null;
    _errorMessage = null;
    _stopRefreshTimer();
    notifyListeners();
    // Inform the user globally
    AppMessenger.show(
      localization.isSwahili
          ? 'Kikao chako kimeisha. Tafadhali ingia tena.'
          : 'Your session has ended. Please sign in again.',
    );
  }

  // Refresh user data — called on the background timer and after permission edits.
  Future<void> refreshUser() async {
    if (!_isAuthenticated) return;

    try {
      final oldPermissions = _user?.permissions?.join(',') ?? '';
      final oldRole = _user?.role ?? '';
      final oldActive = _user?.isActive ?? true;

      final Map<String, dynamic>? userData = await AuthService.getCurrentUser();
      if (userData == null) return;

      final newUser = UserData.fromJson(userData);

      // Force-logout if account was deactivated remotely.
      if (!newUser.isActive && oldActive) {
        AppMessenger.show('Akaunti yako imezimwa. Tafadhali wasiliana na msimamizi.');
        await logout();
        return;
      }

      final newPermissions = newUser.permissions?.join(',') ?? '';
      final permissionsChanged = oldPermissions != newPermissions;
      final roleChanged = oldRole != (newUser.role ?? '');

      _user = newUser;

      if (permissionsChanged || roleChanged) {
        // Something security-relevant changed — rebuild all permission-gated UI.
        await _checkServiceAccess(newUser);
        notifyListeners();
        AppMessenger.show(
          localization.isSwahili
              ? 'Ruhusa zako zimebadilika. Ukurasa umevifanywa upya.'
              : 'Your permissions have been updated. Page refreshed.',
        );
      }
      // If nothing changed we intentionally skip notifyListeners() to avoid
      // rebuilding every watch-subscribed widget on every 5-minute tick.
    } on Exception catch (e) {
      debugPrint("Failed to refresh user data: $e");
    }
  }

  // Check if user still has access to the selected service module
  Future<void> _checkServiceAccess(UserData user) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? selectedService = prefs.getString('selected_service');
      if (selectedService == null) return;

      bool hasAccess = true;
      if (selectedService == 'rental') {
        // Basic check for rental module access
        hasAccess = user.hasPermission('manage_properties_rental') || 
                   user.hasPermission('view_maintenance') ||
                   user.role == 'tenant' || 
                   user.role == 'landlord' ||
                   user.isSuperAdmin;
      } else if (selectedService == 'inventory') {
        hasAccess = user.hasPermission('view_inventory') || user.isAdmin || user.isSuperAdmin;
      } else if (selectedService == 'transport') {
        hasAccess = user.hasPermission('view_transport') || user.isAdmin || user.isSuperAdmin;
      }

      if (!hasAccess) {
        await prefs.remove('selected_service');
        AppMessenger.show(
            localization.isSwahili
            ? 'Huna ruhusa ya kufikia moduli hii tena.'
            : 'You no longer have access to this module.');
        // Navigator will automatically show ServiceSelectionScreen due to AuthWrapper logic
      }
    } catch (e) {
      debugPrint("Error checking service access: $e");
    }
  }

  LocalizationService get localization => LocalizationService.instance;

  // Update user profile
  Future<bool> updateProfile({
    final String? name,
    final String? email,
    final String? phone,
  }) async {
    if (!_isAuthenticated || _user == null) {
      return false;
    }

    _setLoading(true);
    _clearError();

    try {
      // Call backend to update profile
      final Map<String, dynamic> res = await AuthService.updateProfile(
        name: name,
        email: email,
        phone: phone,
      );

      final Map<String, dynamic>? updated =
          res['user'] is Map ? Map<String, dynamic>.from(res['user']) : null;
      if (updated != null) {
        _user = UserData.fromJson(updated);
      } else if (_user != null) {
        // Fallback: locally merge
        final Map<String, Object?> updatedUserData = <String, Object?>{
          "id": _user!.id,
          "name": name ?? _user!.name,
          "email": email ?? _user!.email,
          "phone_number": phone ?? _user!.phoneNumber,
          "role": _user!.role,
          "is_active": _user!.isActive,
          if (_user!.avatarUrl != null) 'avatar_url': _user!.avatarUrl,
        };
        await AuthService.saveUserData(updatedUserData);
        _user = UserData.fromJson(updatedUserData);
      }

      notifyListeners();
      return true;
    } on Exception catch (e) {
      _setError("Failed to update profile: $e");
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Upload profile image (avatar)
  Future<bool> uploadProfileImage({
    required List<int> bytes,
    required String filename,
  }) async {
    if (!_isAuthenticated) return false;
    _setLoading(true);
    _clearError();
    try {
      final api = ApiService();
      final res = await api.uploadProfileImage(
          bytes: Uint8List.fromList(bytes), filename: filename);
      // Try to get updated user from response
      Map<String, dynamic>? updated;
      if (res['data'] is Map && (res['data'] as Map)['user'] is Map) {
        updated =
            Map<String, dynamic>.from((res['data'] as Map)['user'] as Map);
      } else if (res['user'] is Map) {
        updated = Map<String, dynamic>.from(res['user'] as Map);
      }
      if (updated != null) {
        _user = UserData.fromJson(updated);
        await AuthService.saveUserData(updated);
      }
      notifyListeners();
      return true;
    } on Exception catch (e) {
      _setError("Failed to upload image: $e");
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Change password
  Future<bool> changePassword({
    required final String currentPassword,
    required final String newPassword,
    required final String confirmPassword,
  }) async {
    if (!_isAuthenticated) {
      return false;
    }

    _setLoading(true);
    _clearError();

    try {
      await AuthService.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
        confirmPassword: confirmPassword,
      );
      return true;
    } on Exception catch (e) {
      _setError("Failed to change password: $e");
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Helper methods
  void _setLoading(final bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(final String error) {
    _error = error;
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    _errorMessage = null;
    _lastErrorCode = null;
    notifyListeners();
  }

  // Fetch Superadmin contact details from DB
  Future<void> fetchSuperAdminContact() async {
    try {
      final api = ApiService();
      final admin = await api.getSuperAdminUser();
      
      // Always use the superadmin found in the users table
      if (admin != null) {
        _supportPhone = admin['phone_number']?.toString();
        _supportEmail = admin['email']?.toString();
        notifyListeners();
      }
    } catch (e) {
      debugPrint("AuthProvider.fetchSuperAdminContact failed: $e");
    }
  }

  // Get user display name
  String get userDisplayName {
    if (_user == null) {
      return "Guest";
    }
    return _user!.name.isNotEmpty ? _user!.name : _user!.email;
  }

  // Get user email
  String get userEmail {
    if (_user == null) {
      return "";
    }
    return _user!.email;
  }

  // Get user phone
  String get userPhone {
    if (_user == null) {
      return "";
    }
    return _user!.phoneNumber ?? "";
  }

  // Check if user has specific role
  bool hasRole(final String role) {
    if (_user == null) {
      return false;
    }
    return _user!.role == role;
  }

  // Check if user is admin
  bool get isAdmin => hasRole("admin");

  // Check if user is driver
  bool get isDriver => hasRole("driver");
}
