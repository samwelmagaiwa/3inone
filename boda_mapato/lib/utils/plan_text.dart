import "package:intl/intl.dart";

import "../models/business.dart";

/// The words about plans, in one language at a time: what a plan covers, how long it is paid for, what it costs, and
/// the message when a plan is too small for the services chosen.

/// "ONE service" / "Huduma MOJA", "TWO services" / "Huduma 2", "UP TO 3 services" / "Hadi huduma 3" (the owner chooses which).
String planCoverText(final int included, {required final bool sw}) => switch (included) {
      1 => sw ? "Huduma MOJA" : "ONE service",
      2 => sw ? "Huduma 2" : "TWO services",
      _ => sw ? "Hadi huduma $included" : "UP TO $included services",
    };

/// "1 month" / "Mwezi 1", "3 months" / "Miezi 3", "1 year" / "Mwaka 1".
String periodText(final int months, {required final bool sw}) {
  if (months == 12) return sw ? "Mwaka 1" : "1 year";
  if (months == 1) return sw ? "Mwezi 1" : "1 month";
  return sw ? "Miezi $months" : "$months months";
}

/// "TZS 30,000".
String moneyText(final String currency, final double amount) => "$currency ${NumberFormat("#,##0").format(amount)}";

/// "Standard" / "Kawaida": the name of a plan in the language of the app.
String planNameText(final String plan, {required final bool sw}) => businessPlanLabel(plan, sw: sw);

/// The message when [plan] covers fewer services than the [chosen] ones. [better] is the plan that fits.
String planTooSmallText(final String plan, final int included, final int chosen, final String better, {required final bool sw}) {
  final String name = planNameText(plan, sw: sw);
  final String betterName = planNameText(better, sw: sw);
  if (sw) {
    return included == 1
        ? "Mpango wa $name ni huduma MOJA tu, na umechagua $chosen. Chagua mpango wa $betterName au punguza huduma."
        : "Mpango wa $name unahusu huduma $included tu, na umechagua $chosen. Chagua mpango wa $betterName au punguza huduma.";
  }
  return included == 1
      ? "The $name plan covers ONE service only, and you chose $chosen. Choose the $betterName plan or fewer services."
      : "The $name plan covers $included services only, and you chose $chosen. Choose the $betterName plan or fewer services.";
}
