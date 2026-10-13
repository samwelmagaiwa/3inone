import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/theme_constants.dart';
import '../providers/rental_provider.dart';
import '../services/localization_service.dart';

/// Defines the sequential stages of the rental service flow.
/// Each stage is a prerequisite for the next.
enum RentalFlowStage {
  hasNoProperties,  // No properties exist yet
  hasNoHouses,      // Properties exist but no houses added
  hasNoTenants,     // Houses exist but no tenants onboarded
  hasNoAgreements,  // Tenants exist but no active lease agreements
  hasNoBills,       // Agreements exist but no active bills
  complete,         // All stages satisfied
}

class RentalFlowValidator {
  // ─── Stage checkers ───────────────────────────────────────────────────────

  static bool hasProperties(RentalProvider p) => p.properties.isNotEmpty;

  static bool hasHouses(RentalProvider p) {
    for (final prop in p.properties) {
      if ((prop['houses'] as List?)?.isNotEmpty ?? false) return true;
    }
    return false;
  }

  static bool hasVacantHouses(RentalProvider p) {
    for (final prop in p.properties) {
      final houses = (prop['houses'] as List?) ?? [];
      for (final h in houses) {
        if (h['status'] == 'vacant' ||
            h['is_occupied'] == 0 ||
            h['is_occupied'] == false) {
          return true;
        }
      }
    }
    return false;
  }

  static bool hasTenants(RentalProvider p) => p.tenants.isNotEmpty;

  static bool hasActiveAgreements(RentalProvider p) =>
      p.agreements.any((a) => a['status'] == 'active');

  static bool hasUnpaidBills(RentalProvider p) =>
      p.bills.any((b) =>
          b['status'] == 'unpaid' ||
          b['status'] == 'partial' ||
          b['is_overdue'] == true ||
          b['is_overdue'] == 1);

  /// Evaluates the current flow stage by checking prerequisites in order.
  static Future<RentalFlowStage> evaluateStage(
      BuildContext context, RentalProvider provider) async {
    if (!hasProperties(provider)) return RentalFlowStage.hasNoProperties;
    if (!hasHouses(provider)) return RentalFlowStage.hasNoHouses;
    if (!hasTenants(provider)) return RentalFlowStage.hasNoTenants;
    if (!hasActiveAgreements(provider)) return RentalFlowStage.hasNoAgreements;
    if (!hasUnpaidBills(provider)) return RentalFlowStage.hasNoBills;
    return RentalFlowStage.complete;
  }

  // ─── Generic gate dialog (stays within rental nav stack) ─────────────────

  /// Shows a blocking dialog when a prerequisite stage is not met.
  /// All actions push WITHIN the current rental Navigator context — no
  /// cross-service navigation.
  static Future<void> validateStep({
    required BuildContext context,
    required Future<void> Function(RentalProvider) fetchData,
    required bool Function(RentalProvider) condition,
    required String title,
    required String message,
    required String actionLabel,
    String? actionRoute, // Optional if onAction is provided
    VoidCallback? onAction, // Optional custom action
    bool barrierDismissible = false,
  }) async {
    final provider = context.read<RentalProvider>();
    await fetchData(provider);
    if (!context.mounted) return;

    if (!condition(provider)) {
      await showDialog<void>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (ctx) => _RentalFlowDialog(
          title: title,
          message: message,
          actionLabel: actionLabel,
          onAction: onAction ?? () {
            Navigator.pop(ctx); // Close dialog
            Navigator.pop(context); // Go back to previous screen
            if (actionRoute != null) {
              Navigator.pushNamed(context, actionRoute);
            }
          },
          onBack: () {
            Navigator.pop(ctx);
            Navigator.pop(context);
          },
        ),
      );
    }
  }

  // ─── Stage-aware inline banner ────────────────────────────────────────────

  /// Returns an inline guidance banner when the stage prerequisite is not met,
  /// or null if the stage is satisfied.
  static Widget? buildStageBanner({
    required RentalFlowStage stage,
    required BuildContext context,
  }) {
    final config = _stageConfig(stage);
    if (config == null) return null;
    return _RentalStageBanner(
      icon: config['icon'] as IconData,
      title: config['title'] as String,
      message: config['message'] as String,
      actionLabel: config['actionLabel'] as String,
      actionRoute: config['actionRoute'] as String,
      context: context,
    );
  }

  static Map<String, dynamic>? _stageConfig(RentalFlowStage stage) {
    switch (stage) {
      case RentalFlowStage.hasNoProperties:
        return {
          'icon': Icons.business_center_outlined,
          'title': LocalizationService.instance.translate('add_a_property_first'),
          'message': LocalizationService.instance.translate('you_have_no_properties_start_by'),
          'actionLabel': LocalizationService.instance.translate('add_property_2'),
          'actionRoute': '/rental/add-property',
        };
      case RentalFlowStage.hasNoHouses:
        return {
          'icon': Icons.home_work_outlined,
          'title': LocalizationService.instance.translate('add_a_house_first'),
          'message': LocalizationService.instance.translate('you_have_a_property_but_no'),
          'actionLabel': LocalizationService.instance.translate('add_house'),
          'actionRoute': '/rental/properties',
        };
      case RentalFlowStage.hasNoTenants:
        return {
          'icon': Icons.person_add_outlined,
          'title': LocalizationService.instance.translate('add_a_tenant_first'),
          'message': LocalizationService.instance.translate('you_have_houses_but_no_tenants'),
          'actionLabel': LocalizationService.instance.translate('add_tenant'),
          'actionRoute': '/rental/onboard-tenant',
        };
      case RentalFlowStage.hasNoAgreements:
        return {
          'icon': Icons.description_outlined,
          'title': LocalizationService.instance.translate('create_an_agreement_first'),
          'message': LocalizationService.instance.translate('tenants_are_registered_but_there_is'),
          'actionLabel': LocalizationService.instance.translate('create_lease'),
          'actionRoute': '/rental/agreements',
        };
      case RentalFlowStage.hasNoBills:
        return {
          'icon': Icons.receipt_long_outlined,
          'title': LocalizationService.instance.translate('no_open_bills_3'),
          'message': LocalizationService.instance.translate('no_bills_need_payment_bills_are'),
          'actionLabel': LocalizationService.instance.translate('view_agreements'),
          'actionRoute': '/rental/agreements',
        };
      case RentalFlowStage.complete:
        return null;
    }
  }
}

// ─── Private Widgets ─────────────────────────────────────────────────────────

class _RentalFlowDialog extends StatelessWidget {
  const _RentalFlowDialog({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.onBack,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: ThemeConstants.bgMid,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: ThemeConstants.primaryOrange.withOpacity(0.12),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(
                  bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: ThemeConstants.primaryOrange.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_clock_outlined,
                        color: ThemeConstants.primaryOrange, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(message,
                  style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
            ),
            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onBack,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(LocalizationService.instance.translate('back'), style: TextStyle(color: Colors.white70)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: onAction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeConstants.primaryOrange,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                        shadowColor: ThemeConstants.primaryOrange.withOpacity(0.4),
                      ),
                      child: Text(actionLabel,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RentalStageBanner extends StatelessWidget {
  const _RentalStageBanner({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.actionRoute,
    required this.context,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final String actionRoute;
  final BuildContext context;

  @override
  Widget build(BuildContext ctx) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeConstants.primaryOrange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ThemeConstants.primaryOrange.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: ThemeConstants.primaryOrange, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(message,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, actionRoute),
              icon: const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white),
              label: Text(actionLabel,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: ThemeConstants.primaryOrange,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
