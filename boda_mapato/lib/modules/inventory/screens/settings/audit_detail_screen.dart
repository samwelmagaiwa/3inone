import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_depot_models.dart';
import '../../providers/depot_provider.dart';
import '../widgets/glow_list_card.dart';

/// The words for what happened ("moved to trash"), or the plain action name when no translation exists for it.
String auditActionText(final LocalizationService loc, final String action) {
  final String key = 'audit_action_$action';
  final String text = loc.translate(key);

  return text == key ? action.replaceAll('_', ' ') : text;
}

/// "product", "customer payment": the kind of record, readable.
String auditEntityText(final String entityType) => entityType.replaceAll('_', ' ');

/// "selling_price" as "Selling price".
String auditFieldText(final String field) {
  final String spaced = field.replaceAll('_', ' ').trim();

  return spaced.isEmpty ? field : spaced[0].toUpperCase() + spaced.substring(1);
}

/// The first few changes of a row in one line: "Selling price: 500 → 650".
String auditChangesLine(final LocalizationService loc, final InvAuditEntry e, {final int most = 2}) {
  final List<AuditChange> changes = e.changes;
  if (changes.isEmpty || e.before == null && e.after == null) return '';
  final String empty = loc.translate('audit_empty_value');
  final Iterable<String> parts = changes.take(most).map((AuditChange c) {
    if (e.before == null) return '${auditFieldText(c.field)}: ${c.after ?? empty}';
    if (e.after == null) return auditFieldText(c.field);

    return '${auditFieldText(c.field)}: ${c.before ?? empty} → ${c.after ?? empty}';
  });
  final int more = changes.length - most;

  return parts.join('  •  ') + (more > 0 ? '  +$more' : '');
}

/// The full story of one entry in the audit trail: when, who, which record, and what changed field by field with the old value next to
/// the new one. Below it, the latest other things the same person did, each one a tap away.
class AuditDetailScreen extends StatefulWidget {
  const AuditDetailScreen({super.key, required this.entry, this.loadActivity});

  final InvAuditEntry entry;

  /// The latest entries of one person (for tests); the server's otherwise.
  final Future<List<InvAuditEntry>> Function(String userId)? loadActivity;

  @override
  State<AuditDetailScreen> createState() => _AuditDetailScreenState();
}

class _AuditDetailScreenState extends State<AuditDetailScreen> {
  List<InvAuditEntry>? _activity;

  @override
  void initState() {
    super.initState();
    _loadActivity();
  }

  Future<void> _loadActivity() async {
    final InvAuditEntry e = widget.entry;
    if (e.userId.isEmpty) {
      setState(() => _activity = <InvAuditEntry>[]);

      return;
    }
    final Future<List<InvAuditEntry>> Function(String) load = widget.loadActivity ?? (String id) => context.read<DepotProvider>().fetchAuditByUser(id);
    final List<InvAuditEntry> rows = await load(e.userId);
    if (!mounted) return;
    setState(() => _activity = rows.where((InvAuditEntry r) => r.id != e.id).toList());
  }

  static String _stamp(final DateTime at) => '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}/${at.year} '
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}:${at.second.toString().padLeft(2, '0')}';

  Widget _fact(final String label, final String value, {final Key? key}) => Row(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 96, child: Text(label, style: ThemeConstants.captionStyle)),
          Expanded(child: Text(value, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w600))),
        ],
      );

  Widget _title(final String text) => Center(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFFFFD166))));

  /// One changed field: its name, then what it was and what it is.
  Widget _change(final LocalizationService loc, final InvAuditEntry e, final AuditChange c) {
    final String empty = loc.translate('audit_empty_value');

    return Column(
      key: Key('audit_change_${c.field}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(auditFieldText(c.field), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        if (e.before != null && e.after != null) ...<Widget>[
          _side(loc.translate('audit_before'), c.before ?? empty, ThemeConstants.errorText, c.before == null),
          const SizedBox(height: 2),
          _side(loc.translate('audit_after'), c.after ?? empty, ThemeConstants.successGreen, c.after == null),
        ] else
          Text(e.before == null ? (c.after ?? empty) : (c.before ?? empty), style: ThemeConstants.bodyStyle),
      ],
    );
  }

  Widget _side(final String label, final String value, final Color color, final bool isEmpty) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 56, child: Text(label, style: ThemeConstants.captionStyle)),
          Expanded(child: Text(value, style: TextStyle(color: isEmpty ? Colors.white54 : color, fontWeight: FontWeight.w700, fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal))),
        ],
      );

  @override
  Widget build(final BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final InvAuditEntry e = widget.entry;
    final List<AuditChange> changes = e.changes;
    final bool created = e.before == null && e.after != null;
    final String heading = '${auditEntityText(e.entityType)} · ${auditActionText(loc, e.action)}';

    return Scaffold(
      appBar: AppBar(title: Text(loc.translate('audit_details'))),
      body: DecoratedBox(
        decoration: const BoxDecoration(color: ThemeConstants.primaryBlue),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: <Widget>[
            GlowListCard(
              dividerKey: 'audit_divider',
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              children: <Widget>[
                Text(heading, key: const Key('audit_heading'), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800, fontSize: 18)),
                _fact(loc.translate('audit_when'), _stamp(e.createdAt), key: const Key('audit_when')),
                _fact(loc.translate('audit_who'), e.userName.isEmpty ? '—' : e.userName, key: const Key('audit_who')),
                _fact(loc.translate('audit_record'), <String>[if (e.entityId != null) '#${e.entityId}', if (e.summary.isNotEmpty) e.summary].join('  ·  ').ifEmpty('—'), key: const Key('audit_record')),
                _title(created ? loc.translate('audit_new_details') : (e.after == null && e.before != null ? loc.translate('audit_removed_details') : loc.translate('audit_what_changed'))),
                if (changes.isEmpty)
                  Text(loc.translate('audit_no_changes'), key: const Key('audit_no_changes'), style: ThemeConstants.captionStyle)
                else
                  for (final AuditChange c in changes) _change(loc, e, c),
              ],
            ),
            const SizedBox(height: 14),
            GlowListCard(
              dividerKey: 'audit_more_divider',
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              children: <Widget>[
                _title(loc.translateWith('audit_more_by', <Object?>[e.userName.isEmpty ? '—' : e.userName])),
                if (_activity == null)
                  const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
                else if (_activity!.isEmpty)
                  Text(loc.translate('audit_nothing_else'), key: const Key('audit_nothing_else'), style: ThemeConstants.captionStyle)
                else
                  for (final InvAuditEntry r in _activity!) _activityRow(context, loc, r),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _activityRow(final BuildContext context, final LocalizationService loc, final InvAuditEntry r) {
    final String line = auditChangesLine(loc, r, most: 1);

    return InkWell(
      key: Key('audit_activity_${r.id}'),
      onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AuditDetailScreen(entry: r, loadActivity: widget.loadActivity))),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('${auditEntityText(r.entityType)} · ${auditActionText(loc, r.action)}', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
                Text(<String>[_stamp(r.createdAt), if (r.summary.isNotEmpty) r.summary].join('  •  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: ThemeConstants.captionStyle),
                if (line.isNotEmpty) Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: ThemeConstants.captionStyle),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white54),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(final String other) => isEmpty ? other : this;
}
