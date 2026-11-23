import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../../widgets/temporary_password_dialog.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'group_dashboard_screen.dart';
import 'groups_text.dart';
import 'member_form_screen.dart';
import 'payment_form.dart';
import 'statement_screen.dart';
import 'widgets/groups_ui.dart';
import 'widgets/member_avatar.dart';
import 'widgets/member_documents_card.dart';

/// One member's file: who they are, where their membership stands and the steps that move it, their office, sign-in, money, dependants,
/// whom they brought in and the history of every change. Each step shows only to whoever holds its right, and asks Yes / No first.
class MemberDetailScreen extends StatefulWidget {
  const MemberDetailScreen({required this.api, required this.me, required this.memberId, super.key});

  final GroupsApi api;
  final GroupMe me;
  final int memberId;

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  GroupMemberFile? _file;
  List<GroupTransaction> _payments = const <GroupTransaction>[];
  String? _error;

  bool get _sw => context.read<LocalizationService>().isSwahili;

  /// Is this the person looking at it? Nobody moves their own membership or office.
  bool get _isSelf => widget.me.member?.id == widget.memberId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final GroupMemberFile f = await widget.api.member(widget.memberId);
      List<GroupTransaction> payments = const <GroupTransaction>[];
      if (widget.me.seesPayments) {
        payments = (await widget.api.transactions(memberId: widget.memberId)).transactions;
      }
      if (!mounted) return;
      setState(() {
        _file = f;
        _payments = payments;
        _error = null;
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
  }

  /// Runs [action], shows [done] in the green banner, and reads the file again; a refusal is shown in the red one.
  Future<void> _run(final Future<Object?> Function() action, final String done) async {
    try {
      await action();
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, done);
      await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _approve(final GroupMember m) async {
    final bool sw = _sw;
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Idhinisha uanachama?' : 'Approve this membership?',
      message: sw ? '${m.fullName} atakuwa mwanachama hai na kupewa namba ya uanachama.' : '${m.fullName} becomes an active member and gets a member number.',
      yes: sw ? 'Idhinisha' : 'Approve',
      tone: GroupTone.positive,
    );
    if (ok) await _run(() => widget.api.moveMember(m.id, 'approve'), sw ? 'Uanachama umeidhinishwa.' : 'Membership approved.');
  }

  Future<void> _reinstate(final GroupMember m) async {
    final bool sw = _sw;
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Mrudishe kazini?' : 'Reinstate this member?',
      message: sw ? '${m.fullName} atakuwa mwanachama hai tena.' : '${m.fullName} becomes an active member again.',
      yes: sw ? 'Rudisha' : 'Reinstate',
      tone: GroupTone.positive,
    );
    if (ok) await _run(() => widget.api.moveMember(m.id, 'reinstate'), sw ? 'Amerudishwa.' : 'Reinstated.');
  }

  /// A step that needs a reason (reject, suspend, exit, deceased): the reason card is its Yes / No.
  Future<void> _withReason(final GroupMember m, final String action) async {
    final bool sw = _sw;
    final (String, String, String) words = switch (action) {
      'reject' => (sw ? 'Kataa ombi' : 'Reject the application', sw ? 'Kataa' : 'Reject', sw ? 'Ombi limekataliwa.' : 'Application rejected.'),
      'suspend' => (sw ? 'Simamisha uanachama' : 'Suspend the membership', sw ? 'Simamisha' : 'Suspend', sw ? 'Amesimamishwa.' : 'Suspended.'),
      'exit' => (sw ? 'Rekodi kuondoka kwake' : 'Record that they left', sw ? 'Rekodi' : 'Record', sw ? 'Imerekodiwa.' : 'Recorded.'),
      _ => (sw ? 'Rekodi kifo' : 'Record a death', sw ? 'Rekodi' : 'Record', sw ? 'Imerekodiwa.' : 'Recorded.'),
    };
    final String? reason = await groupReason(
      context,
      title: words.$1,
      message: '${m.fullName}. ${sw ? 'Andika sababu; itahifadhiwa kwenye historia.' : 'Write the reason; it is kept in the history.'}',
      yes: words.$2,
    );
    if (reason != null) await _run(() => widget.api.moveMember(m.id, action, reason: reason), words.$3);
  }

  Future<void> _office(final GroupMember m) async {
    final bool sw = _sw;
    final String? picked = await groupActions(
      context,
      title: sw ? 'Cheo cha ${m.fullName}' : 'Office of ${m.fullName}',
      actions: <GroupSheetAction>[
        for (final String o in groupOffices)
          if (o != m.office) GroupSheetAction(icon: Icons.workspace_premium_outlined, label: officeLabel(sw: sw, office: o), value: o),
        if (m.office != null) GroupSheetAction(icon: Icons.remove_circle_outline, label: sw ? 'Ondoa cheo' : 'Remove the office', value: '__none', tone: GroupTone.danger),
      ],
    );
    if (picked == null || !mounted) return;
    final String? office = picked == '__none' ? null : picked;

    // Who holds it now (only one person holds each office but the committee's).
    String? holder;
    if (office != null && office != 'kamati_miradi') {
      try {
        final GroupMemberPage page = await widget.api.members(office: office);
        holder = page.members.where((final GroupMember h) => h.id != m.id).map((final GroupMember h) => h.fullName).firstOrNull;
      } on Exception {
        holder = null;
      }
    }
    if (!mounted) return;
    final bool ok = await groupConfirm(
      context,
      title: office == null ? (sw ? 'Ondoa cheo?' : 'Remove the office?') : (sw ? 'Mpe cheo?' : 'Give this office?'),
      message: office == null
          ? (sw ? '${m.fullName} atabaki mwanachama wa kawaida.' : '${m.fullName} stays an ordinary member.')
          : '${m.fullName}: ${officeLabel(sw: sw, office: office)} — ${officeDuty(sw: sw, office: office)}.'
              '${holder == null ? '' : (sw ? '\n$holder ataachia cheo hiki.' : '\n$holder will no longer hold it.')}',
      yes: office == null ? (sw ? 'Ondoa' : 'Remove') : (sw ? 'Mpe' : 'Give'),
      tone: office == null ? GroupTone.danger : GroupTone.positive,
    );
    if (ok) await _run(() => widget.api.setOffice(m.id, office, replace: holder != null), sw ? 'Cheo kimebadilishwa.' : 'Office changed.');
  }

  Future<void> _signIn(final GroupMember m) async {
    final bool sw = _sw;
    final bool reset = m.hasSignIn;
    final bool ok = await groupConfirm(
      context,
      title: reset ? (sw ? 'Nenosiri jipya la muda?' : 'New one-time password?') : (sw ? 'Mpe akaunti ya kuingia?' : 'Give a sign-in?'),
      message: reset
          ? (sw ? 'Nenosiri la zamani halitafanya kazi tena. Litaonyeshwa mara moja tu.' : 'The old password stops working. The new one is shown only once.')
          : (sw ? '${m.fullName} ataingia kwa namba ${m.phone} na nenosiri la muda, ambalo ataulizwa kulibadilisha.' : '${m.fullName} signs in with ${m.phone} and a one-time password they must change.'),
      yes: sw ? 'Endelea' : 'Continue',
      tone: GroupTone.positive,
    );
    if (!ok || !mounted) return;
    try {
      final Map<String, dynamic> got = await widget.api.signIn(m.id, reset: reset);
      if (!mounted) return;
      if (got['linked_owner'] == true) {
        ThemeConstants.showSuccessSnackBar(context, sw ? 'Ameunganishwa na akaunti yake ya mmiliki.' : 'Tied to their own owner account.');
      } else if (got['temporary_password'] != null) {
        await showTemporaryPasswords(context, <TemporaryCredential>[
          TemporaryCredential(name: m.fullName, password: '${got['temporary_password']}', contact: '${got['login'] ?? m.phone}'),
        ]);
      }
      await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _edit(final GroupMember m) async {
    final GroupMemberFile? saved = await Navigator.push<GroupMemberFile>(context, MaterialPageRoute<GroupMemberFile>(builder: (_) => MemberFormScreen(api: widget.api, me: widget.me, member: m)));
    if (saved != null) await _load();
  }

  Future<void> _recordPayment(final GroupMemberFile f) async {
    List<GroupObligation> owing = const <GroupObligation>[];
    if (widget.me.seesContributions) {
      try {
        owing = (await widget.api.statement(memberId: f.member.id))?.owing ?? const <GroupObligation>[];
      } on Exception {
        owing = const <GroupObligation>[];
      }
    }
    if (!mounted) return;
    if (await showPaymentForm(context, api: widget.api, me: widget.me, member: f.member, paid: f.balances ?? const <String, double>{}, owing: owing)) await _load();
  }

  Future<void> _dependant(final GroupMember m, [final GroupDependant? d]) async {
    final Map<String, dynamic>? got = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _DependantDialog(dependant: d));
    if (got == null || !mounted) return;
    final bool sw = _sw;
    if (got['__delete'] == true && d != null) {
      final bool ok = await groupConfirm(
        context,
        title: sw ? 'Ondoa mtegemezi?' : 'Remove this dependant?',
        message: '${d.name} (${relationshipLabel(sw: sw, relationship: d.relationship)})',
        yes: sw ? 'Ondoa' : 'Remove',
        tone: GroupTone.danger,
      );
      if (ok) await _run(() => widget.api.deleteDependant(m.id, d.id), sw ? 'Ameondolewa.' : 'Removed.');
      return;
    }
    await _run(() => widget.api.saveDependant(m.id, got, id: d?.id), sw ? 'Imehifadhiwa.' : 'Saved.');
  }

  Future<void> _moreActions(final GroupMember m) async {
    final bool sw = _sw;
    final GroupMe me = widget.me;
    final String? picked = await groupActions(
      context,
      title: m.fullName,
      actions: <GroupSheetAction>[
        if (me.can('manage_members')) GroupSheetAction(icon: Icons.edit_outlined, label: sw ? 'Badili taarifa' : 'Edit details', value: 'edit'),
        if (me.can('record_payments') && <String>['submitted', 'active', 'suspended'].contains(m.status))
          GroupSheetAction(icon: Icons.payments_outlined, label: sw ? 'Rekodi malipo' : 'Record a payment', value: 'pay'),
        if (me.seesContributions) GroupSheetAction(icon: Icons.receipt_long_outlined, label: sw ? 'Taarifa ya fedha' : 'Statement', value: 'statement'),
        if (!_isSelf && me.can('manage_offices') && m.isActive) GroupSheetAction(icon: Icons.workspace_premium_outlined, label: sw ? 'Cheo' : 'Office', value: 'office'),
        if (me.can('manage_members') && (m.isActive || m.status == 'suspended'))
          GroupSheetAction(
            icon: Icons.key_outlined,
            label: m.hasSignIn ? (sw ? 'Nenosiri jipya la muda' : 'New one-time password') : (sw ? 'Mpe akaunti ya kuingia' : 'Give a sign-in'),
            value: 'sign_in',
          ),
        if (!_isSelf && me.can('approve_members') && m.isActive)
          GroupSheetAction(icon: Icons.pause_circle_outline, label: sw ? 'Simamisha' : 'Suspend', value: 'suspend', tone: GroupTone.danger),
        if (!_isSelf && me.can('approve_members') && m.status == 'suspended')
          GroupSheetAction(icon: Icons.play_circle_outline, label: sw ? 'Mrudishe' : 'Reinstate', value: 'reinstate', tone: GroupTone.positive),
        if (!_isSelf && me.can('approve_members') && (m.isActive || m.status == 'suspended')) ...<GroupSheetAction>[
          GroupSheetAction(icon: Icons.logout_rounded, label: sw ? 'Ameondoka' : 'Left the group', value: 'exit', tone: GroupTone.danger),
          GroupSheetAction(icon: Icons.local_florist_outlined, label: sw ? 'Amefariki' : 'Passed away', value: 'deceased', tone: GroupTone.danger),
        ],
      ],
    );
    if (picked == null || !mounted) return;
    switch (picked) {
      case 'edit':
        await _edit(m);
      case 'pay':
        await _recordPayment(_file!);
      case 'statement':
        await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => GroupStatementScreen(api: widget.api, memberId: m.id, memberName: m.fullName)));
      case 'office':
        await _office(m);
      case 'sign_in':
        await _signIn(m);
      case 'reinstate':
        await _reinstate(m);
      default:
        await _withReason(m, picked);
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final GroupMemberFile? f = _file;

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(
        f?.member.fullName ?? (sw ? 'Mwanachama' : 'Member'),
        flat: true,
        actions: <Widget>[
          if (f != null) IconButton(key: const Key('grp_member_actions'), icon: const Icon(Icons.more_vert), tooltip: sw ? 'Hatua' : 'Actions', onPressed: () => _moreActions(f.member)),
        ],
      ),
      body: SafeArea(
        child: f == null
            ? Center(child: _error == null ? const CircularProgressIndicator() : GroupEmpty(_error!))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: joinGlowCards(<Widget>[
                    // One card: the parts are told apart by the glowing line and their gold titles, with no gap between.
                    GlowSections(
                      key: const Key('grp_member_sections'),
                      children: <Widget>[
                        _headCard(f, sw),
                        if (f.member.isApplication) _applicationCard(f, sw),
                        _detailsCard(f.member, sw),
                        MemberDocumentsCard(api: widget.api, me: widget.me, memberId: f.member.id, documents: f.documents, photoUrl: f.photoUrl, onChanged: _load),
                        if (f.balances != null) _moneyCard(f, sw),
                        _dependantsCard(f, sw),
                        if (f.referrals.isNotEmpty) _referralsCard(f, sw),
                        if (f.events.isNotEmpty) _historyCard(f, sw),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  /// The photo, in its frame, opens a larger view or lets whoever registers members change it.
  Future<void> _photoTap(final GroupMemberFile f, final bool sw) async {
    final bool mayEdit = widget.me.can('manage_members');
    final String? pick = await groupActions(context, title: f.member.fullName, actions: <GroupSheetAction>[
      if (f.photoUrl != null) GroupSheetAction(icon: Icons.zoom_in_rounded, label: sw ? 'Ona picha kubwa' : 'View the photo', value: 'view'),
      if (mayEdit) GroupSheetAction(icon: Icons.photo_camera_outlined, label: f.photoUrl == null ? (sw ? 'Weka picha' : 'Add a photo') : (sw ? 'Badilisha picha' : 'Change the photo'), value: 'change'),
    ]);
    if (pick == null || !mounted) return;
    if (pick == 'view') {
      await showDialog<void>(
        context: context,
        builder: (final BuildContext c) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: ClipRRect(borderRadius: BorderRadius.circular(20), child: InteractiveViewer(child: Image.network(f.photoUrl!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox(height: 200, child: Icon(Icons.person_rounded, color: Colors.white38, size: 80))))),
        ),
      );
    } else if (await addMemberDocument(context, api: widget.api, me: widget.me, memberId: f.member.id, photoOnly: true)) {
      await _load();
    }
  }

  Widget _headCard(final GroupMemberFile f, final bool sw) {
    final GroupMember m = f.member;
    return GlowCard(
        children: <Widget>[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(m.memberNumber ?? m.applicationRef ?? '', key: const Key('grp_detail_number'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(officeLabel(sw: sw, office: m.office), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: GroupPill(statusLabel(sw: sw, status: m.status), color: statusColor(m.status))),
              ]),
            ),
            const SizedBox(width: 12),
            MemberAvatar(name: m.fullName, photoUrl: f.photoUrl, ringColor: statusColor(m.status), editable: widget.me.can('manage_members'), onTap: () => _photoTap(f, sw)),
          ]),
          if (m.statusReason != null) GroupDetailRow(sw ? 'Sababu' : 'Reason', m.statusReason!),
          if (m.joinedOn != null) GroupDetailRow(sw ? 'Alijiunga' : 'Joined', dateLabel(m.joinedOn)),
          GroupDetailRow(sw ? 'Akaunti ya kuingia' : 'Sign-in', m.hasSignIn ? (sw ? 'Anayo' : 'Yes') : (sw ? 'Hana' : 'None')),
        ],
      );
  }

  Widget _applicationCard(final GroupMemberFile f, final bool sw) {
    final GroupMember m = f.member;
    final bool mayDecide = widget.me.can('approve_members') && !_isSelf;
    return GlowCard(
      title: sw ? 'Ombi la uanachama' : 'Membership application',
      children: <Widget>[
        if (f.approvalBlockers.isEmpty)
          Text(sw ? 'Malipo ya kujiunga yamethibitishwa; linaweza kuidhinishwa.' : 'The joining payments are verified; it can be approved.',
              style: const TextStyle(color: ThemeConstants.successGreen))
        else
          for (final String b in f.approvalBlockers)
            Row(children: <Widget>[
              const Icon(Icons.schedule_rounded, color: ThemeConstants.warningAmber, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(blockerLabel(sw: sw, blocker: b), key: Key('grp_blocker_$b'), style: const TextStyle(color: Colors.white70))),
            ]),
        if (widget.me.can('record_payments') && f.approvalBlockers.isNotEmpty)
          OutlinedButton.icon(
            key: const Key('grp_app_record_payment'),
            style: OutlinedButton.styleFrom(foregroundColor: ThemeConstants.primaryOrange, side: const BorderSide(color: ThemeConstants.primaryOrange)),
            onPressed: () => _recordPayment(f),
            icon: const Icon(Icons.payments_outlined),
            label: Text(sw ? 'Rekodi malipo' : 'Record a payment'),
          ),
        if (mayDecide)
          Row(children: <Widget>[
            Expanded(
              child: OutlinedButton(
                key: const Key('grp_app_reject'),
                style: OutlinedButton.styleFrom(foregroundColor: ThemeConstants.errorRed, side: const BorderSide(color: ThemeConstants.errorRed)),
                onPressed: () => _withReason(m, 'reject'),
                child: Text(sw ? 'Kataa' : 'Reject'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('grp_app_approve'),
                style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen),
                onPressed: f.approvalBlockers.isEmpty ? () => _approve(m) : null,
                child: Text(sw ? 'Idhinisha' : 'Approve'),
              ),
            ),
          ]),
      ],
    );
  }

  Widget _detailsCard(final GroupMember m, final bool sw) => GlowCard(
        title: sw ? 'Taarifa' : 'Details',
        children: <Widget>[
          GroupDetailRow(sw ? 'Simu' : 'Phone', m.phone),
          if (m.altPhone != null) GroupDetailRow(sw ? 'Simu nyingine' : 'Other phone', m.altPhone!),
          if (m.email != null) GroupDetailRow(sw ? 'Barua pepe' : 'Email', m.email!),
          if (m.nida != null) GroupDetailRow('NIDA', m.nida!),
          if (m.gender != null) GroupDetailRow(sw ? 'Jinsia' : 'Gender', m.gender == 'male' ? (sw ? 'Mwanaume' : 'Male') : (sw ? 'Mwanamke' : 'Female')),
          if (m.dateOfBirth != null) GroupDetailRow(sw ? 'Kuzaliwa' : 'Born', dateLabel(m.dateOfBirth)),
          if (<String?>[m.street, m.ward, m.district, m.region].any((final String? s) => s != null))
            GroupDetailRow(sw ? 'Makazi' : 'Address', <String?>[m.street, m.ward, m.district, m.region].whereType<String>().join(', ')),
          if (m.occupation != null) GroupDetailRow(sw ? 'Kazi' : 'Occupation', m.occupation!),
          GroupDetailRow(sw ? 'Aliyemleta' : 'Referred by', m.referrerName ?? (m.founding ? (sw ? 'Mwanzilishi' : 'Founding member') : '-')),
        ],
      );

  Widget _moneyCard(final GroupMemberFile f, final bool sw) => GlowCard(
        title: sw ? 'Fedha' : 'Money',
        children: <Widget>[
          for (final MapEntry<String, double> b in f.balances!.entries) GroupDetailRow(categoryLabel(sw: sw, category: b.key), tsh(b.value)),
          if (_payments.isNotEmpty)
            Column(children: <Widget>[for (final GroupTransaction t in _payments.take(10)) GroupTransactionTile(t: t, sw: sw)]),
        ],
      );

  Widget _dependantsCard(final GroupMemberFile f, final bool sw) {
    final bool mayEdit = widget.me.can('manage_members');
    return GlowCard(
      title: sw ? 'Wategemezi' : 'Dependants',
      children: <Widget>[
        if (f.dependants.isEmpty) Text(sw ? 'Hakuna aliyeandikwa.' : 'None recorded.', style: const TextStyle(color: Colors.white60)),
        for (final GroupDependant d in f.dependants)
          ListTile(
            key: Key('grp_dep_${d.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(d.name, style: const TextStyle(color: Colors.white)),
            subtitle: Text(<String>[relationshipLabel(sw: sw, relationship: d.relationship), if (d.phone != null) d.phone!].join(' · '), style: const TextStyle(color: Colors.white60)),
            trailing: mayEdit ? const Icon(Icons.edit_outlined, color: Colors.white38, size: 18) : null,
            onTap: mayEdit ? () => _dependant(f.member, d) : null,
          ),
        if (mayEdit)
          TextButton.icon(
            key: const Key('grp_dep_add'),
            onPressed: () => _dependant(f.member),
            icon: const Icon(Icons.add, color: ThemeConstants.primaryOrange),
            label: Text(sw ? 'Ongeza mtegemezi' : 'Add a dependant', style: const TextStyle(color: ThemeConstants.primaryOrange)),
          ),
      ],
    );
  }

  Widget _referralsCard(final GroupMemberFile f, final bool sw) => GlowCard(
        title: sw ? 'Aliowaleta' : 'Brought in',
        children: <Widget>[
          for (final GroupMember r in f.referrals)
            GroupDetailRow(r.fullName, '${r.memberNumber ?? ''} · ${statusLabel(sw: sw, status: r.status)}'),
        ],
      );

  Widget _historyCard(final GroupMemberFile f, final bool sw) => GlowCard(
        title: sw ? 'Historia' : 'History',
        children: <Widget>[
          for (final GroupMemberEvent e in f.events)
            Text(
              '${dateLabel(e.at)} · '
              '${e.kind == 'office' ? '${officeLabel(sw: sw, office: e.from)} → ${officeLabel(sw: sw, office: e.to)}' : '${e.from == null ? '' : '${statusLabel(sw: sw, status: e.from!)} → '}${statusLabel(sw: sw, status: e.to ?? '')}'}'
              '${e.reason == null ? '' : ' · ${e.reason}'}'
              '${e.byName == null ? '' : ' · ${e.byName}'}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
        ],
      );
}

/// Add or change a dependant; with an existing one it can also be removed (returns {'__delete': true}).
class _DependantDialog extends StatefulWidget {
  const _DependantDialog({this.dependant});

  final GroupDependant? dependant;

  @override
  State<_DependantDialog> createState() => _DependantDialogState();
}

class _DependantDialogState extends State<_DependantDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.dependant?.name);
  late final TextEditingController _phone = TextEditingController(text: widget.dependant?.phone);
  late String _relationship = widget.dependant?.relationship ?? 'child';

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool ready = _name.text.trim().length >= 2;
    return AlertDialog(
      key: const Key('grp_dep_dialog'),
      backgroundColor: ThemeConstants.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(widget.dependant == null ? (sw ? 'Mtegemezi mpya' : 'New dependant') : (sw ? 'Mtegemezi' : 'Dependant'),
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          TextField(
            key: const Key('grp_dep_name'),
            controller: _name,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(sw ? 'Jina' : 'Name'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _relationship,
            dropdownColor: ThemeConstants.bgMid,
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(sw ? 'Uhusiano' : 'Relationship'),
            items: <DropdownMenuItem<String>>[
              for (final String r in relationships) DropdownMenuItem<String>(value: r, child: Text(relationshipLabel(sw: sw, relationship: r))),
            ],
            onChanged: (final String? v) => setState(() => _relationship = v ?? 'other'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(sw ? 'Simu (hiari)' : 'Phone (optional)'),
          ),
        ]),
      ),
      actions: <Widget>[
        if (widget.dependant != null)
          TextButton(
            key: const Key('grp_dep_delete'),
            onPressed: () => Navigator.pop(context, <String, dynamic>{'__delete': true}),
            child: Text(sw ? 'Ondoa' : 'Remove', style: const TextStyle(color: ThemeConstants.errorRed)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel', style: const TextStyle(color: Colors.white60))),
        TextButton(
          key: const Key('grp_dep_save'),
          onPressed: ready
              ? () => Navigator.pop(context, <String, dynamic>{
                    'name': _name.text.trim(),
                    'relationship': _relationship,
                    if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.replaceAll(' ', ''),
                  })
              : null,
          child: Text(sw ? 'Hifadhi' : 'Save', style: TextStyle(color: ready ? ThemeConstants.successGreen : Colors.white24, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
