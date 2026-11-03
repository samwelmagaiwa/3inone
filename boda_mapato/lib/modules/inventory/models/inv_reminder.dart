enum InvReminderStatus { open, snoozed, done }

class InvReminder {
  InvReminder({
    required this.id,
    required this.type, // payment_due | low_stock
    required this.title,
    required this.description,
    required this.dueAt,
    this.status = InvReminderStatus.open,
    this.snoozeUntil,
    this.relatedId,
    this.customerName,
    this.amountLeft,
    this.days,
  });

  final int id;
  final String type;
  final String title;
  final String description;
  DateTime dueAt;
  InvReminderStatus status;
  DateTime? snoozeUntil;
  int? relatedId; // saleId or productId

  /// A payment reminder: whose debt it is, how much of the sale is still owed, and for how many days (read aloud).
  final String? customerName;
  final double? amountLeft;
  final int? days;
}
