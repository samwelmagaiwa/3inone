/// A receipt of the Groups (Vikundi) service: a verified payment, the group that gives it and the link its QR code carries.
library;

import 'group_models.dart';

class GroupReceipt {
  const GroupReceipt({required this.transaction, required this.group, required this.verifyUrl, this.reversed = false, this.memberPhone});

  factory GroupReceipt.fromJson(final Map<String, dynamic> j) => GroupReceipt(
        transaction: GroupTransaction.fromJson(Map<String, dynamic>.from(j['transaction'] as Map)),
        group: '${j['group'] ?? ''}',
        verifyUrl: '${j['verify_url'] ?? ''}',
        reversed: j['reversed'] == true,
        memberPhone: j['member_phone'] == null ? null : '${j['member_phone']}',
      );

  final GroupTransaction transaction;
  final String group;

  /// What the QR code holds: opening it shows whether the receipt is genuine.
  final String verifyUrl;

  /// The payment was later put right with a reversal.
  final bool reversed;

  /// The member's phone number, so the receipt can be sent to them (only when the signed-in person may send it).
  final String? memberPhone;
}
