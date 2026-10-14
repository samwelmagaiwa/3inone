import 'dart:async';

enum AuthEvent {
  unauthorized,

  /// The server answered 402 `subscription_expired`: the business's plan ended and it is held back until it pays.
  subscriptionExpired,
}

class AuthEvents {
  AuthEvents._();
  static final AuthEvents instance = AuthEvents._();

  final StreamController<AuthEvent> _controller =
      StreamController<AuthEvent>.broadcast();

  Stream<AuthEvent> get stream => _controller.stream;

  void emit(AuthEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  void dispose() {
    _controller.close();
  }
}
