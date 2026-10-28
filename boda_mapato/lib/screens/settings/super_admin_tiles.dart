import "package:flutter/material.dart";

import "../../constants/theme_constants.dart";
import "../../services/localization_service.dart";
import "../../widgets/pending_registrations_count.dart";
import "../../widgets/pending_sms_senders_count.dart";
import "../admin/businesses_screen.dart";
import "../admin/plan_prices_screen.dart";
import "../admin/registrations_screen.dart";
import "../admin/sms_senders_screen.dart";
import "backup_screen.dart";
import "permissions_management_screen.dart";
import "user_management_screen.dart";

/// The platform controls only a super admin has (users, registrations, businesses and plans, prices, SMS sender
/// names, permissions, backup). One list, shown on the main Settings screen and inside the Inventory and Salon
/// settings, so no service is missing any of them.
class SuperAdminTiles extends StatefulWidget {
  const SuperAdminTiles({super.key});

  @override
  State<SuperAdminTiles> createState() => _SuperAdminTilesState();
}

class _SuperAdminTilesState extends State<SuperAdminTiles> {
  final GlobalKey<PendingRegistrationsCountState> _pendingRegistrations =
      GlobalKey<PendingRegistrationsCountState>();
  final GlobalKey<PendingSmsSendersCountState> _pendingSmsSenders =
      GlobalKey<PendingSmsSendersCountState>();

  void _open(BuildContext context, Widget screen) {
    Navigator.push(
        context, MaterialPageRoute<void>(builder: (BuildContext _) => screen));
  }

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap,
      {Widget? badge}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Icon(icon, color: ThemeConstants.textSecondary, size: 24),
      title: Text(title,
          style: const TextStyle(
              color: ThemeConstants.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: const TextStyle(
              color: ThemeConstants.textSecondary, fontSize: 13)),
      trailing: badge == null
          ? const Icon(Icons.chevron_right,
              color: ThemeConstants.textSecondary, size: 20)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                badge,
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right,
                    color: ThemeConstants.textSecondary, size: 20),
              ],
            ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = LocalizationService.instance;
    return Column(
      children: <Widget>[
        _tile(
          Icons.people_alt_outlined,
          loc.translate('users'),
          loc.isSwahili
              ? 'Dhibiti watumiaji wote kwenye huduma zote'
              : 'Manage all users across every service',
          () => _open(context, const UserManagementScreen()),
        ),
        const Divider(color: Colors.white24, height: 1),
        PendingRegistrationsCount(
          key: _pendingRegistrations,
          builder: (BuildContext context, int? pending) => _tile(
            Icons.how_to_reg_outlined,
            loc.isSwahili ? 'Usajili wa Biashara' : 'Business Registrations',
            loc.isSwahili
                ? 'Kagua biashara zilizojisajili na uzipe huduma'
                : 'Review registered businesses and assign their services',
            () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (BuildContext _) => const RegistrationsScreen()),
              );
              // approving or rejecting changed the number
              await _pendingRegistrations.currentState?.refresh();
            },
            badge: (pending ?? 0) > 0 ? CountBadge(count: pending) : null,
          ),
        ),
        const Divider(color: Colors.white24, height: 1),
        _tile(
          Icons.storefront_outlined,
          loc.isSwahili ? 'Biashara na Mipango' : 'Businesses & Plans',
          loc.isSwahili
              ? 'Mipango, tarehe za malipo na taarifa za kila biashara'
              : 'Plan, paid-until date and details of every business',
          () => _open(context, const BusinessesScreen()),
        ),
        const Divider(color: Colors.white24, height: 1),
        _tile(
          Icons.sell_outlined,
          loc.isSwahili ? 'Mipango na Bei' : 'Plans & Prices',
          loc.isSwahili
              ? 'Basic = huduma 1, Standard = huduma 2, Premium = hadi 3: weka bei, zinaonekana kwenye usajili'
              : 'Basic = 1 service, Standard = 2, Premium = up to 3: set the prices, the registration form shows them',
          () => _open(context, const PlanPricesScreen()),
        ),
        const Divider(color: Colors.white24, height: 1),
        PendingSmsSendersCount(
          key: _pendingSmsSenders,
          builder: (BuildContext context, int? pending) => _tile(
            Icons.sms_outlined,
            loc.isSwahili ? 'Majina ya SMS (Sender ID)' : 'SMS Sender Names',
            loc.isSwahili
                ? 'Weka jina na API key ya kila biashara; ujumbe wake utatoka kwa jina hilo'
                : "Set each business's sender name and API key; its texts then go out under it",
            () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (BuildContext _) => const SmsSendersScreen()),
              );
              await _pendingSmsSenders.currentState?.refresh();
            },
            badge: (pending ?? 0) > 0 ? CountBadge(count: pending) : null,
          ),
        ),
        const Divider(color: Colors.white24, height: 1),
        _tile(
          Icons.admin_panel_settings_outlined,
          loc.isSwahili ? 'Ruhusa' : 'Permissions',
          loc.isSwahili
              ? 'Dhibiti ruhusa za moduli za huduma'
              : 'Manage service module permissions',
          () => _open(context, const PermissionsScreen()),
        ),
        const Divider(color: Colors.white24, height: 1),
        _tile(
          Icons.cloud_sync_outlined,
          loc.translate('backup'),
          loc.isSwahili
              ? 'Hifadhi na rejesha data ya mfumo wote'
              : 'Backup and restore entire system data',
          () => _open(context, const BackupScreen()),
        ),
      ],
    );
  }
}
