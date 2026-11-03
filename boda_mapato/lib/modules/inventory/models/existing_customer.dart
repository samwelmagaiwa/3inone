import 'package:flutter/foundation.dart';

/// A customer who is already saved, found by name or by phone number.
@immutable
class ExistingCustomer {
  const ExistingCustomer({required this.id, required this.name, required this.phone});

  final int id;
  final String name;
  final String phone;
}
