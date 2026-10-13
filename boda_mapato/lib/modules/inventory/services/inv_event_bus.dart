import 'dart:async';

/// Domains that can be mutated. Providers subscribe and re-fetch when a
/// relevant domain is emitted so every screen stays consistent without
/// any direct cross-provider wiring.
enum InvDomain {
  /// A sale was created, cancelled, or had a payment applied.
  sale,

  /// A product was created, edited, or deleted.
  product,

  /// An expense was recorded or deleted.
  expense,

  /// A stock operation happened: stock-in, stock-out, write-off, stock-count,
  /// batch receipt, or goods receipt that changes on-hand quantities.
  stock,

  /// A crate movement was posted.
  crate,

  /// A purchase order was created, updated, or goods were received.
  purchase,

  /// A credit-customer balance changed (payment received or sale on debt).
  credit,

  /// The inventory settings (or the business's kind) changed: the till, the product page and the
  /// menus read them, so they refetch.
  settings,
}

/// Singleton broadcast bus. Call [emit] after any mutation; providers listen
/// and refresh their relevant slices of data automatically.
class InvEventBus {
  InvEventBus._();
  static final InvEventBus instance = InvEventBus._();

  final StreamController<Set<InvDomain>> _ctrl =
      StreamController<Set<InvDomain>>.broadcast();

  Stream<Set<InvDomain>> get stream => _ctrl.stream;

  /// Fire one or more domain events. Every provider listening will re-fetch
  /// the data it owns for those domains.
  void emit(Set<InvDomain> domains) {
    if (domains.isEmpty) return;
    _ctrl.add(domains);
  }
}
