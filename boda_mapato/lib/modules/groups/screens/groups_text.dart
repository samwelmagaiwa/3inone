/// The words of the Groups (Vikundi) screens that are built from values the server sends: offices, statuses, kinds of money. One place, in
/// both languages, so every screen says them the same way.
library;

import 'package:flutter/material.dart';

import '../../../constants/theme_constants.dart';
import '../../inventory/screens/salon/salon_text.dart' as salon;

/// Money as the rest of the app writes it: "TSH 80,000".
String tsh(final num amount) => salon.tsh(amount);

/// How a payment was made: "M-Pesa", "Taslimu" / "Cash".
String methodLabel({required final bool sw, required final String method}) =>
    method == 'other' ? (sw ? 'Njia nyingine' : 'Other') : salon.channelLabel(sw: sw, channel: method);

/// The ways a payment can be made, in the order they are offered.
const List<String> paymentMethods = <String>['cash', 'mpesa', 'mixx', 'airtel_money', 'halopesa', 'bank_transfer', 'other'];

/// "2026-11-22" (or a full time) -> "22/11/2026".
String dateLabel(final String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final DateTime? d = DateTime.tryParse(iso);
  return d == null ? iso : salon.dayLabel(d.toLocal());
}

/// The offices, in the order the group ranks them.
const List<String> groupOffices = <String>[
  'mwenyekiti',
  'makamu_mwenyekiti',
  'mweka_hazina',
  'mweka_hazina_msaidizi',
  'katibu',
  'katibu_msaidizi',
  'mwenyekiti_miradi',
  'kamati_miradi',
];

String officeLabel({required final bool sw, required final String? office}) {
  switch (office) {
    case 'mwenyekiti':
      return sw ? 'Mwenyekiti' : 'Chairperson';
    case 'makamu_mwenyekiti':
      return sw ? 'Makamu Mwenyekiti' : 'Deputy Chairperson';
    case 'mweka_hazina':
      return sw ? 'Mweka Hazina' : 'Treasurer';
    case 'mweka_hazina_msaidizi':
      return sw ? 'Mweka Hazina Msaidizi' : 'Assistant Treasurer';
    case 'katibu':
      return sw ? 'Katibu' : 'Secretary';
    case 'katibu_msaidizi':
      return sw ? 'Katibu Msaidizi' : 'Assistant Secretary';
    case 'mwenyekiti_miradi':
      return sw ? 'Mwenyekiti wa Miradi' : 'Projects Chairperson';
    case 'kamati_miradi':
      return sw ? 'Kamati ya Miradi' : 'Projects Committee';
    case null:
    case '':
      return sw ? 'Mwanachama' : 'Member';
    default:
      return office;
  }
}

/// What each office is for, one line.
String officeDuty({required final bool sw, required final String office}) {
  switch (office) {
    case 'mwenyekiti':
      return sw ? 'Anaidhinisha na kuita vikao' : 'Approves and calls meetings';
    case 'makamu_mwenyekiti':
      return sw ? 'Anakaimu nafasi ya Mwenyekiti' : 'Stands in for the Chairperson';
    case 'mweka_hazina':
      return sw ? 'Anaidhinisha mambo ya fedha na kuhifadhi taarifa zake' : 'Approves money matters and keeps the records';
    case 'mweka_hazina_msaidizi':
      return sw ? 'Anamsaidia Mweka Hazina' : 'Helps the Treasurer';
    case 'katibu':
      return sw ? 'Anaratibu mambo ya chama' : "Coordinates the group's affairs";
    case 'katibu_msaidizi':
      return sw ? 'Anamsaidia Katibu' : 'Helps the Secretary';
    case 'mwenyekiti_miradi':
      return sw ? 'Anasimamia mikopo na miradi yote' : 'Oversees all loans and projects';
    case 'kamati_miradi':
      return sw ? 'Inashughulikia mikopo na miradi' : 'Works on loans and projects';
    default:
      return '';
  }
}

String statusLabel({required final bool sw, required final String status}) {
  switch (status) {
    case 'submitted':
      return sw ? 'Ombi jipya' : 'Application';
    case 'active':
      return sw ? 'Hai' : 'Active';
    case 'rejected':
      return sw ? 'Amekataliwa' : 'Rejected';
    case 'suspended':
      return sw ? 'Amesimamishwa' : 'Suspended';
    case 'exited':
      return sw ? 'Ameondoka' : 'Left';
    case 'deceased':
      return sw ? 'Marehemu' : 'Deceased';
    default:
      return status;
  }
}

/// The colour a member's status is drawn in (the same meaning as everywhere: green fine, amber waiting, red stopped).
Color statusColor(final String status) {
  switch (status) {
    case 'active':
      return ThemeConstants.successGreen;
    case 'submitted':
      return ThemeConstants.warningAmber;
    case 'suspended':
      return ThemeConstants.primaryOrange;
    case 'rejected':
      return ThemeConstants.errorRed;
    default:
      return Colors.white54;
  }
}

String categoryLabel({required final bool sw, required final String category}) {
  switch (category) {
    case 'joining_fee':
      return sw ? 'Ada ya kujiunga' : 'Joining fee';
    case 'shares':
      return sw ? 'Hisa za mradi' : 'Project shares';
    default:
      return category;
  }
}

String paymentStatusLabel({required final bool sw, required final String status}) {
  switch (status) {
    case 'pending':
      return sw ? 'Inasubiri' : 'Waiting';
    case 'verified':
      return sw ? 'Imethibitishwa' : 'Verified';
    case 'rejected':
      return sw ? 'Imekataliwa' : 'Turned down';
    default:
      return status;
  }
}

Color paymentStatusColor(final String status) {
  switch (status) {
    case 'verified':
      return ThemeConstants.successGreen;
    case 'pending':
      return ThemeConstants.warningAmber;
    case 'rejected':
      return ThemeConstants.errorRed;
    default:
      return Colors.white54;
  }
}

String relationshipLabel({required final bool sw, required final String relationship}) {
  switch (relationship) {
    case 'parent':
      return sw ? 'Mzazi' : 'Parent';
    case 'spouse':
      return sw ? 'Mwenza' : 'Spouse';
    case 'child':
      return sw ? 'Mtoto' : 'Child';
    case 'parent_in_law':
      return sw ? 'Mkwe (mzazi wa mwenza)' : 'Parent-in-law';
    case 'other':
      return sw ? 'Mwingine' : 'Other';
    default:
      return relationship;
  }
}

const List<String> relationships = <String>['parent', 'spouse', 'child', 'parent_in_law', 'other'];

/// Why an application cannot be approved yet.
String blockerLabel({required final bool sw, required final String blocker}) {
  switch (blocker) {
    case 'joining_fee_unpaid':
      return sw ? 'Ada ya kujiunga bado haijalipwa na kuthibitishwa' : 'The joining fee is not yet paid and verified';
    case 'shares_unpaid':
      return sw ? 'Hisa za mradi bado hazijalipwa na kuthibitishwa' : 'The project shares are not yet paid and verified';
    default:
      return blocker;
  }
}

/// What happened, from the activity log's action code.
String activityLabel({required final bool sw, required final String action}) {
  switch (action) {
    case 'member_applied':
      return sw ? 'Ombi la uanachama limerekodiwa' : 'Application recorded';
    case 'member_entered':
      return sw ? 'Mwanachama aliyekuwepo ameingizwa' : 'Existing member entered';
    case 'member_updated':
      return sw ? 'Taarifa za mwanachama zimebadilishwa' : 'Member details changed';
    case 'member_approve':
      return sw ? 'Uanachama umeidhinishwa' : 'Membership approved';
    case 'member_reject':
      return sw ? 'Ombi limekataliwa' : 'Application rejected';
    case 'member_suspend':
      return sw ? 'Mwanachama amesimamishwa' : 'Member suspended';
    case 'member_reinstate':
      return sw ? 'Mwanachama amerudishwa' : 'Member reinstated';
    case 'member_exit':
      return sw ? 'Mwanachama ameondoka' : 'Member left';
    case 'member_deceased':
      return sw ? 'Kifo kimerekodiwa' : 'Death recorded';
    case 'office_changed':
      return sw ? 'Cheo kimebadilishwa' : 'Office changed';
    case 'dependant_saved':
      return sw ? 'Mtegemezi amehifadhiwa' : 'Dependant saved';
    case 'dependant_removed':
      return sw ? 'Mtegemezi ameondolewa' : 'Dependant removed';
    case 'sign_in_created':
    case 'sign_in_linked':
      return sw ? 'Akaunti ya kuingia imetolewa' : 'Sign-in given';
    case 'sign_in_reset':
      return sw ? 'Nenosiri jipya la muda' : 'New one-time password';
    case 'payment_submitted':
      return sw ? 'Malipo yametumwa' : 'Payment sent';
    case 'payment_verified':
      return sw ? 'Malipo yamethibitishwa' : 'Payment verified';
    case 'payment_rejected':
      return sw ? 'Malipo yamekataliwa' : 'Payment turned down';
    case 'payment_reversed':
      return sw ? 'Malipo yamerekebishwa' : 'Payment reversed';
    case 'settings_changed':
      return sw ? 'Mipangilio imebadilishwa' : 'Settings changed';
    default:
      return action;
  }
}
