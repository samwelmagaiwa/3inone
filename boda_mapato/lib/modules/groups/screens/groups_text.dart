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
    case 'savings':
      return sw ? 'Akiba' : 'Savings';
    case 'contribution':
      return sw ? 'Mchango' : 'Contribution';
    case 'expense':
      return sw ? 'Matumizi ya kikundi' : 'Group expense';
    case 'loan_disbursement':
      return sw ? 'Mkopo uliotolewa' : 'Loan paid out';
    case 'loan_repayment':
      return sw ? 'Marejesho ya mkopo' : 'Loan repayment';
    case 'welfare':
      return sw ? 'Msaada' : 'Welfare';
    case 'hire':
      return sw ? 'Ukodishaji' : 'Hire';
    case 'dividend':
      return sw ? 'Gawio' : 'Dividend';
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
    case 'contribution_saved':
      return sw ? 'Mchango umehifadhiwa' : 'Contribution saved';
    case 'contribution_raised':
      return sw ? 'Mchango umeitishwa' : 'Contribution called';
    case 'obligation_exempted':
      return sw ? 'Udhuru umetolewa' : 'Member excused';
    case 'promise_made':
      return sw ? 'Ahadi imewekwa' : 'Promise made';
    case 'promise_cancelled':
      return sw ? 'Ahadi imeondolewa' : 'Promise withdrawn';
    case 'loan_applied':
      return sw ? 'Ombi la mkopo' : 'Loan applied for';
    case 'guarantee_accepted':
      return sw ? 'Udhamini umekubaliwa' : 'Guarantee accepted';
    case 'guarantee_declined':
      return sw ? 'Udhamini umekataliwa' : 'Guarantee declined';
    case 'loan_recommended':
      return sw ? 'Mkopo umependekezwa' : 'Loan recommended';
    case 'loan_approved':
      return sw ? 'Mkopo umeidhinishwa' : 'Loan approved';
    case 'loan_rejected':
      return sw ? 'Mkopo umekataliwa' : 'Loan turned down';
    case 'loan_cancelled':
      return sw ? 'Ombi la mkopo limeondolewa' : 'Loan application withdrawn';
    case 'loan_disbursed':
      return sw ? 'Mkopo umetolewa' : 'Loan paid out';
    case 'benefit_type_saved':
      return sw ? 'Aina ya msaada imehifadhiwa' : 'Welfare kind saved';
    case 'benefit_requested':
      return sw ? 'Ombi la msaada' : 'Welfare requested';
    case 'benefit_approved':
      return sw ? 'Msaada umeidhinishwa' : 'Welfare approved';
    case 'benefit_rejected':
      return sw ? 'Msaada umekataliwa' : 'Welfare turned down';
    case 'benefit_paid':
      return sw ? 'Msaada umelipwa' : 'Welfare paid';
    case 'asset_saved':
      return sw ? 'Mali imehifadhiwa' : 'Asset saved';
    case 'asset_maintenance':
      return sw ? 'Matengenezo ya mali' : 'Asset maintenance';
    case 'asset_damage':
      return sw ? 'Mali imeharibika' : 'Asset damaged';
    case 'asset_loss':
      return sw ? 'Mali imepotea' : 'Asset lost';
    case 'asset_repair':
      return sw ? 'Mali imetengenezwa' : 'Asset repaired';
    case 'asset_adjust':
      return sw ? 'Idadi imerekebishwa' : 'Count corrected';
    case 'asset_retire':
      return sw ? 'Mali imeondolewa kazini' : 'Asset retired';
    case 'hire_requested':
      return sw ? 'Ombi la kukodi' : 'Hire requested';
    case 'hire_approved':
      return sw ? 'Ukodishaji umekubaliwa' : 'Hire confirmed';
    case 'hire_declined':
      return sw ? 'Ukodishaji umekataliwa' : 'Hire declined';
    case 'hire_issued':
      return sw ? 'Vimetolewa' : 'Handed over';
    case 'hire_returned':
      return sw ? 'Vimerudishwa' : 'Brought back';
    case 'hire_charged':
      return sw ? 'Gharama ya uharibifu' : 'Damage charge';
    case 'hire_closed':
      return sw ? 'Ukodishaji umefungwa' : 'Hire closed';
    case 'dividend_prepared':
      return sw ? 'Gawio limeandaliwa' : 'Dividend prepared';
    case 'dividend_posted':
      return sw ? 'Gawio limelipwa kwenye akiba' : 'Dividend credited';
    case 'dividend_discarded':
      return sw ? 'Rasimu ya gawio imeachwa' : 'Dividend draft discarded';
    case 'meeting_called':
      return sw ? 'Kikao kimeitishwa' : 'Meeting called';
    case 'meeting_cancelled':
      return sw ? 'Kikao kimesitishwa' : 'Meeting cancelled';
    case 'meeting_recorded':
      return sw ? 'Kikao kimerekodiwa' : 'Meeting recorded';
    case 'announcement_posted':
      return sw ? 'Tangazo limewekwa' : 'Notice posted';
    case 'announcement_removed':
      return sw ? 'Tangazo limeondolewa' : 'Notice taken down';
    case 'texts_sent':
      return sw ? 'Ujumbe umetumwa' : 'Text sent';
    case 'invitation_created':
      return sw ? 'Namba ya mwaliko imetengenezwa' : 'Invitation code made';
    case 'invitation_stopped':
      return sw ? 'Namba ya mwaliko imesitishwa' : 'Invitation code stopped';
    case 'document_kept':
      return sw ? 'Faili imehifadhiwa' : 'File kept';
    case 'document_removed':
      return sw ? 'Faili imeondolewa' : 'File removed';
    case 'export_members':
      return sw ? 'Daftari la wanachama limetolewa' : 'Member register exported';
    case 'export_transactions':
      return sw ? 'Malipo yametolewa (CSV)' : 'Payments exported';
    default:
      return action;
  }
}

/// Where an obligation stands.
String obligationStateLabel({required final bool sw, required final String state}) {
  switch (state) {
    case 'paid':
      return sw ? 'Imelipwa' : 'Paid';
    case 'exempt':
      return sw ? 'Udhuru' : 'Excused';
    case 'cancelled':
      return sw ? 'Imefutwa' : 'Cancelled';
    case 'overdue':
      return sw ? 'Imepita muda' : 'Overdue';
    case 'due':
      return sw ? 'Inadaiwa' : 'Due';
    default:
      return state;
  }
}

Color obligationStateColor(final String state) {
  switch (state) {
    case 'paid':
      return ThemeConstants.successGreen;
    case 'overdue':
      return ThemeConstants.errorRed;
    case 'due':
      return ThemeConstants.warningAmber;
    default:
      return Colors.white54;
  }
}

String promiseStateLabel({required final bool sw, required final String state}) {
  switch (state) {
    case 'kept':
      return sw ? 'Imetimizwa' : 'Kept';
    case 'overdue':
      return sw ? 'Imevunjwa' : 'Missed';
    case 'due':
      return sw ? 'Inasubiriwa' : 'Pending';
    case 'cancelled':
      return sw ? 'Imeondolewa' : 'Withdrawn';
    default:
      return state;
  }
}

Color promiseStateColor(final String state) => switch (state) {
      'kept' => ThemeConstants.successGreen,
      'overdue' => ThemeConstants.errorRed,
      'due' => ThemeConstants.warningAmber,
      _ => Colors.white54,
    };

/// How often a contribution is asked for.
String frequencyLabel({required final bool sw, required final String frequency, final int? dueDay}) {
  switch (frequency) {
    case 'monthly':
      return dueDay == null ? (sw ? 'Kila mwezi' : 'Monthly') : (sw ? 'Kila mwezi, tarehe $dueDay' : 'Monthly, on the $dueDay${_ordinal(dueDay)}');
    case 'one_time':
      return sw ? 'Mara moja' : 'Once';
    case 'event':
      return sw ? 'Kwa tukio' : 'Per event';
    default:
      return frequency;
  }
}

String _ordinal(final int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return 'th';
  return switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
}

const List<String> contributionFrequencies = <String>['monthly', 'one_time', 'event'];

/// Where a loan stands (its status, or for a running loan: active, overdue, repaid).
String loanStateLabel({required final bool sw, required final String state}) {
  switch (state) {
    case 'awaiting_guarantors':
      return sw ? 'Inasubiri wadhamini' : 'Waiting for guarantors';
    case 'under_review':
      return sw ? 'Kwa kamati ya miradi' : 'With the projects committee';
    case 'recommended':
      return sw ? 'Imependekezwa' : 'Recommended';
    case 'approved':
      return sw ? 'Imeidhinishwa' : 'Approved';
    case 'active':
      return sw ? 'Inaendelea' : 'Running';
    case 'overdue':
      return sw ? 'Imepita muda' : 'Overdue';
    case 'repaid':
      return sw ? 'Imelipwa yote' : 'Repaid';
    case 'rejected':
      return sw ? 'Imekataliwa' : 'Turned down';
    case 'cancelled':
      return sw ? 'Imeondolewa' : 'Withdrawn';
    default:
      return state;
  }
}

Color loanStateColor(final String state) => switch (state) {
      'repaid' || 'active' => ThemeConstants.successGreen,
      'approved' || 'recommended' => ThemeConstants.invAccent,
      'awaiting_guarantors' || 'under_review' => ThemeConstants.warningAmber,
      'overdue' || 'rejected' => ThemeConstants.errorRed,
      _ => Colors.white54,
    };

String guarantorStatusLabel({required final bool sw, required final String status}) => switch (status) {
      'accepted' => sw ? 'Amekubali' : 'Accepted',
      'declined' => sw ? 'Amekataa' : 'Declined',
      _ => sw ? 'Anasubiriwa' : 'Waiting',
    };

Color guarantorStatusColor(final String status) => switch (status) {
      'accepted' => ThemeConstants.successGreen,
      'declined' => ThemeConstants.errorRed,
      _ => ThemeConstants.warningAmber,
    };

/// Why a member cannot borrow now.
String eligibilityReasonLabel({required final bool sw, required final String reason}) => switch (reason) {
      'not_active' => sw ? 'Uanachama wako si hai' : 'Your membership is not active',
      'terms_not_set' => sw ? 'Kikundi bado hakijaweka masharti ya mikopo (riba na njia yake)' : 'The group has not set its loan terms yet (rate and method)',
      'shares_unpaid' => sw ? 'Hisa za mradi bado hazijalipwa zote' : 'The project shares are not fully paid',
      'no_ceiling' => sw ? 'Hakuna kikomo: weka akiba kwanza, au maliza mikopo mingine' : 'No ceiling: save first, or finish other loans',
      _ => reason,
    };

String interestMethodLabel({required final bool sw, required final String method}) => switch (method) {
      'flat' => sw ? 'Riba ya kawaida (flat)' : 'Flat',
      'reducing' => sw ? 'Riba inayopungua (reducing balance)' : 'Reducing balance',
      _ => sw ? 'Haijawekwa' : 'Not set',
    };

/// Where a welfare request stands.
String benefitStateLabel({required final bool sw, required final String state}) => switch (state) {
      'submitted' => sw ? 'Inasubiri uamuzi' : 'Waiting for a decision',
      'approved' => sw ? 'Imeidhinishwa' : 'Approved',
      'paying' => sw ? 'Malipo yanasubiri uthibitisho' : 'Payment being verified',
      'paid' => sw ? 'Imelipwa' : 'Paid',
      'rejected' => sw ? 'Imekataliwa' : 'Turned down',
      'cancelled' => sw ? 'Imeondolewa' : 'Withdrawn',
      _ => state,
    };

Color benefitStateColor(final String state) => switch (state) {
      'paid' => ThemeConstants.successGreen,
      'approved' || 'paying' => ThemeConstants.invAccent,
      'submitted' => ThemeConstants.warningAmber,
      'rejected' => ThemeConstants.errorRed,
      _ => Colors.white54,
    };

/// Where an expense request stands.
String expenseStateLabel({required final bool sw, required final String state}) => switch (state) {
      'requested' => sw ? 'Inasubiri uamuzi' : 'Waiting for a decision',
      'approved' => sw ? 'Imeidhinishwa' : 'Approved',
      'paying' => sw ? 'Malipo yanasubiri uthibitisho' : 'Payment being verified',
      'paid' => sw ? 'Imelipwa' : 'Paid',
      'rejected' => sw ? 'Imekataliwa' : 'Turned down',
      'cancelled' => sw ? 'Imeondolewa' : 'Withdrawn',
      _ => state,
    };

Color expenseStateColor(final String state) => switch (state) {
      'paid' => ThemeConstants.successGreen,
      'approved' || 'paying' => ThemeConstants.invAccent,
      'requested' => ThemeConstants.warningAmber,
      'rejected' => ThemeConstants.errorRed,
      _ => Colors.white54,
    };

String expenseCategoryLabel({required final bool sw, required final String category}) => switch (category) {
      'project' => sw ? 'Mradi' : 'Project',
      'office' => sw ? 'Ofisi' : 'Office',
      'meeting' => sw ? 'Kikao' : 'Meeting',
      'transport' => sw ? 'Usafiri' : 'Transport',
      'event' => sw ? 'Tukio' : 'Event',
      _ => sw ? 'Nyingine' : 'Other',
    };

/// Where a project stands.
String projectStateLabel({required final bool sw, required final String state}) => switch (state) {
      'proposed' => sw ? 'Pendekezo' : 'Proposed',
      'active' => sw ? 'Unaendelea' : 'Running',
      'completed' => sw ? 'Umekamilika' : 'Completed',
      'rejected' => sw ? 'Umekataliwa' : 'Turned down',
      'cancelled' => sw ? 'Umefutwa' : 'Cancelled',
      _ => state,
    };

Color projectStateColor(final String state) => switch (state) {
      'completed' => ThemeConstants.successGreen,
      'active' => ThemeConstants.invAccent,
      'proposed' => ThemeConstants.warningAmber,
      'rejected' => ThemeConstants.errorRed,
      _ => Colors.white54,
    };

/// Who the help is for: the member themself or one of their people.
const List<String> benefitRelationships = <String>['self', 'parent', 'spouse', 'child', 'parent_in_law', 'other'];

String benefitRelationshipLabel({required final bool sw, required final String relationship}) =>
    relationship == 'self' ? (sw ? 'Mimi mwenyewe' : 'Myself') : relationshipLabel(sw: sw, relationship: relationship);

/// Where a hire stands.
String hireStateLabel({required final bool sw, required final String state}) => switch (state) {
      'requested' => sw ? 'Ombi jipya' : 'Requested',
      'waiting_payment' => sw ? 'Inasubiri malipo' : 'Waiting for payment',
      'confirmed' => sw ? 'Imethibitishwa' : 'Confirmed',
      'out' => sw ? 'Viko nje' : 'Out',
      'overdue' => sw ? 'Vimechelewa kurudi' : 'Late back',
      'damage_pending' => sw ? 'Uharibifu unasubiri uamuzi' : 'Damage to decide',
      'balance_due' => sw ? 'Kuna deni' : 'Balance due',
      'settled' => sw ? 'Imelipwa yote' : 'Settled',
      'closed' => sw ? 'Imefungwa' : 'Closed',
      'declined' => sw ? 'Imekataliwa' : 'Declined',
      'cancelled' => sw ? 'Imeondolewa' : 'Withdrawn',
      _ => state,
    };

Color hireStateColor(final String state) => switch (state) {
      'confirmed' || 'settled' || 'closed' => ThemeConstants.successGreen,
      'out' => ThemeConstants.invAccent,
      'requested' || 'waiting_payment' || 'balance_due' || 'damage_pending' => ThemeConstants.warningAmber,
      'overdue' || 'declined' => ThemeConstants.errorRed,
      _ => Colors.white54,
    };

String conditionLabel({required final bool sw, required final String condition}) => switch (condition) {
      'good' => sw ? 'Nzuri' : 'Good',
      'fair' => sw ? 'Wastani' : 'Fair',
      'poor' => sw ? 'Mbaya' : 'Poor',
      _ => condition,
    };

String assetEventLabel({required final bool sw, required final String kind}) => switch (kind) {
      'custody' => sw ? 'Mtunzaji amebadilishwa' : 'New keeper',
      'maintenance' => sw ? 'Matengenezo' : 'Maintenance',
      'damage' => sw ? 'Uharibifu' : 'Damage',
      'loss' => sw ? 'Upotevu' : 'Loss',
      'repair' => sw ? 'Imetengenezwa' : 'Repaired',
      'adjust' => sw ? 'Marekebisho ya idadi' : 'Count corrected',
      'retire' => sw ? 'Imeondolewa kazini' : 'Retired',
      _ => kind,
    };
