import "package:flutter/material.dart";

import "../models/business.dart";

/// A one-line warning about the business's plan: expired, or about to run out.
/// Shows nothing at all while everything is fine (or the business never expires).
class SubscriptionBanner extends StatelessWidget {
  const SubscriptionBanner({required this.billing, required this.sw, super.key, this.soonDays = 7, this.onTap});

  final BusinessBilling billing;
  final bool sw;

  /// Opens the subscription details (dates and payments). Without it the banner is only a warning.
  final VoidCallback? onTap;

  /// Warn this many days before the end.
  final int soonDays;

  @override
  Widget build(final BuildContext context) {
    if (!billing.needsAttention(soonDays: soonDays)) return const SizedBox.shrink();

    final int days = billing.daysLeft ?? 0;
    final bool expired = billing.isExpired;
    final bool blocked = billing.blocked;

    final String text;
    if (blocked) {
      text = sw
          ? "Usajili wa biashara umeisha na huduma zimezuiwa. Wasiliana na msimamizi ili kuuhuisha."
          : "The subscription has ended and the service is on hold. Contact your administrator to renew.";
    } else if (expired) {
      text = sw
          ? "Usajili wa biashara umeisha (siku ${-days} zilizopita). Wasiliana na msimamizi ili kuuhuisha."
          : "The subscription ended ${-days} day(s) ago. Contact your administrator to renew.";
    } else if (days == 0) {
      text = sw ? "Usajili wa biashara unaisha leo." : "The subscription ends today.";
    } else {
      text = sw ? "Usajili wa biashara unaisha baada ya siku $days." : "The subscription ends in $days day(s).";
    }

    final Color color = expired ? Colors.redAccent : Colors.amberAccent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey<String>("subscription_banner"),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(expired ? Icons.error_outline : Icons.schedule, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13))),
              if (onTap != null) const Icon(Icons.chevron_right, color: Colors.white54, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
