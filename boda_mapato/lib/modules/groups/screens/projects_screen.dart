import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../widgets/scrolling_chip_row.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_models.dart';
import '../models/group_project_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'widgets/groups_ui.dart';
import 'widgets/member_picker.dart';

/// Projects (miradi): every member sees the projects that run or finished and the ones they proposed; leaders see every proposal too. Any
/// member may propose one. The committee recommends, the chair decides, the Projects Chairperson runs them (the server enforces it all).
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen(
      {required this.me,
      required this.api,
      required this.onChanged,
      super.key});

  final GroupMe me;
  final GroupsApi api;
  final Future<void> Function() onChanged;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  String? _status;
  List<GroupProject> _rows = const <GroupProject>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Whoever has projects waiting for them starts on the proposals.
    if (widget.me.can('view_projects') &&
        ((widget.me.waiting['projects_to_review'] ?? 0) > 0 ||
            (widget.me.waiting['projects_to_approve'] ?? 0) > 0))
      _status = 'proposed';
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<GroupProject> rows =
          await widget.api.projects(status: _status);
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _error = readableErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(final GroupProject p) async {
    await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
            builder: (_) =>
                ProjectDetailScreen(me: widget.me, api: widget.api, id: p.id)));
    await _load();
    await widget.onChanged();
  }

  Future<void> _propose() async {
    final bool? sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeConstants.bgMid,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (final BuildContext c) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
          child: ProjectForm(api: widget.api)),
    );
    if (sent ?? false) await _load();
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool canPropose =
        widget.me.member != null || widget.me.can('manage_projects');
    final List<(String?, String)> filters = <(String?, String)>[
      (null, sw ? 'Yote' : 'All'),
      ('proposed', projectStateLabel(sw: sw, state: 'proposed')),
      ('active', projectStateLabel(sw: sw, state: 'active')),
      ('completed', projectStateLabel(sw: sw, state: 'completed')),
      ('rejected', projectStateLabel(sw: sw, state: 'rejected')),
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canPropose
          ? FloatingActionButton.extended(
              key: const Key('grp_project_propose'),
              backgroundColor: ThemeConstants.primaryOrange,
              foregroundColor: Colors.white,
              onPressed: _propose,
              icon: const Icon(Icons.add_rounded),
              label: Text(sw ? 'Pendekeza mradi' : 'Propose a project'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: joinGlowCards(<Widget>[
            ScrollingChipRow(padding: EdgeInsets.zero, children: <Widget>[
                for (final (String?, String) f in filters)
                  ScrollChoiceChip(chipKey: Key('grp_project_filter_${f.$1 ?? 'all'}'),
                      label: f.$2,
                      selected: _status == f.$1,
                      onSelected: (_) {
                        setState(() => _status = f.$1);
                        _load();
                      },
                    ),
              ]),
            const SizedBox(height: 10),
            if (_error != null) GroupEmpty(_error!),
            if (!_loading && _error == null && _rows.isEmpty)
              GroupEmpty(sw ? 'Hakuna mradi hapa.' : 'No projects here.'),
            if (_rows.isNotEmpty)
              GlowListCard(
                dividerKey: 'grp_project_div',
                padding: const EdgeInsets.symmetric(horizontal: 4),
                children: <Widget>[
                  for (final GroupProject p in _rows)
                    ProjectTile(p: p, sw: sw, onTap: () => _open(p))
                ],
              ),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator())),
          ]),
        ),
      ),
    );
  }
}

/// A project in a list: its title, who proposed or runs it, the budget, how far it is.
class ProjectTile extends StatelessWidget {
  const ProjectTile({required this.p, required this.sw, super.key, this.onTap});

  final GroupProject p;
  final bool sw;
  final VoidCallback? onTap;

  @override
  Widget build(final BuildContext context) => ListTile(
        key: Key('grp_project_${p.id}'),
        onTap: onTap,
        title: Text(p.title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  <String>[
                    tsh(p.budget),
                    if (p.managerName != null)
                      '${sw ? 'Msimamizi' : 'Manager'}: ${p.managerName}'
                    else if (p.proposerName != null)
                      '${sw ? 'Ameapendekeza' : 'Proposed by'} ${p.proposerName}',
                  ].join(' · '),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                if (p.status == 'active' ||
                    p.status == 'completed') ...<Widget>[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                        value: p.progress / 100,
                        minHeight: 6,
                        backgroundColor: Colors.white12,
                        color: projectStateColor(p.status)),
                  ),
                ],
              ]),
        ),
        trailing: GroupPill(
            p.status == 'active'
                ? '${p.progress}%'
                : projectStateLabel(sw: sw, state: p.status),
            color: projectStateColor(p.status)),
      );
}

/// One project: its facts, the committee's views, the progress log and -- by office -- what this person may do with it.
class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen(
      {required this.me, required this.api, required this.id, super.key});

  final GroupMe me;
  final GroupsApi api;
  final int id;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  GroupProject? _p;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final GroupProject p = await widget.api.project(widget.id);
      if (mounted) {
        setState(() {
          _p = p;
          _error = null;
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
  }

  /// Runs a change, shows its result, and reloads.
  Future<void> _run(
      final Future<GroupProject> Function() call, final String done) async {
    try {
      final GroupProject p = await call();
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, done);
      setState(() => _p = p);
    } on Exception catch (e) {
      if (mounted)
        ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _support(final GroupProject p, {required final bool yes}) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    String? note;
    if (yes) {
      if (!await groupConfirm(context,
          title: sw ? 'Pendekeza mradi huu?' : 'Recommend this project?',
          message: '${p.title} · ${tsh(p.budget)}',
          yes: sw ? 'Pendekeza' : 'Recommend',
          tone: GroupTone.positive)) return;
    } else {
      note = await groupReason(context,
          title: sw ? 'Kwa nini haupendekezi?' : 'Why do you not recommend it?',
          message: p.title,
          yes: sw ? 'Tuma' : 'Send');
      if (note == null) return;
    }
    await _run(() => widget.api.reviewProject(p.id, supports: yes, note: note),
        sw ? 'Maoni yamehifadhiwa.' : 'Your view is saved.');
  }

  Future<void> _decide(final GroupProject p,
      {required final bool approve}) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    String? note;
    if (approve) {
      if (!await groupConfirm(context,
          title: sw ? 'Idhinisha mradi?' : 'Approve the project?',
          message: '${p.title} · ${tsh(p.budget)}',
          yes: sw ? 'Idhinisha' : 'Approve',
          tone: GroupTone.positive)) return;
    } else {
      note = await groupReason(context,
          title: sw ? 'Kataa mradi' : 'Turn the project down',
          message: p.title,
          yes: sw ? 'Kataa' : 'Turn down');
      if (note == null) return;
    }
    await _run(
        () => widget.api.decideProject(p.id, approve: approve, note: note),
        approve
            ? (sw ? 'Mradi umeidhinishwa.' : 'Project approved.')
            : (sw ? 'Mradi umekataliwa.' : 'Project turned down.'));
  }

  Future<void> _progress(final GroupProject p) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final (int, String)? got = await showDialog<(int, String)>(
        context: context, builder: (_) => _ProgressDialog(from: p.progress));
    if (got == null || !mounted) return;
    await _run(
        () =>
            widget.api.logProjectProgress(p.id, progress: got.$1, note: got.$2),
        sw ? 'Maendeleo yamehifadhiwa.' : 'Progress saved.');
  }

  Future<void> _close(final GroupProject p,
      {required final bool completed}) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final String? note = await groupReason(
      context,
      title: completed
          ? (sw ? 'Funga mradi kama umekamilika' : 'Close as completed')
          : (sw ? 'Futa mradi' : 'Cancel the project'),
      message: p.title,
      yes: completed
          ? (sw ? 'Kamilisha' : 'Complete')
          : (sw ? 'Futa' : 'Cancel it'),
      tone: completed ? GroupTone.positive : GroupTone.danger,
    );
    if (note == null) return;
    await _run(
        () => widget.api.closeProject(p.id,
            outcome: completed ? 'completed' : 'cancelled', note: note),
        completed
            ? (sw ? 'Mradi umekamilika.' : 'Project completed.')
            : (sw ? 'Mradi umefutwa.' : 'Project cancelled.'));
  }

  Future<void> _manager(final GroupProject p) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final GroupMember? m = await pickGroupMember(context, api: widget.api);
    if (m == null || !mounted) return;
    await _run(
        () => widget.api
            .updateProject(p.id, <String, dynamic>{'manager_id': m.id}),
        sw ? 'Msimamizi amewekwa.' : 'Manager named.');
  }

  Future<void> _edit(final GroupProject p) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeConstants.bgMid,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (final BuildContext c) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
          child: ProjectForm(api: widget.api, project: p)),
    );
    if (saved ?? false) {
      await _load();
      if (mounted)
        ThemeConstants.showSuccessSnackBar(
            context, sw ? 'Imehifadhiwa.' : 'Saved.');
    }
  }

  Future<void> _withdraw(final GroupProject p) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    if (!await groupConfirm(context,
        title: sw ? 'Ondoa pendekezo?' : 'Withdraw the proposal?',
        message: p.title,
        yes: sw ? 'Ondoa' : 'Withdraw',
        tone: GroupTone.danger)) return;
    try {
      await widget.api.withdrawProject(p.id);
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(
          context, sw ? 'Pendekezo limeondolewa.' : 'Proposal withdrawn.');
      Navigator.pop(context);
    } on Exception catch (e) {
      if (mounted)
        ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Widget _button(final String key, final IconData icon, final String label,
          final Color color, final VoidCallback onTap) =>
      FilledButton.icon(
        key: Key(key),
        style: FilledButton.styleFrom(
            backgroundColor: color, foregroundColor: Colors.white),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final GroupProject? p = _p;
    final GroupMe me = widget.me;
    final int? myId = me.member?.id;
    final bool mine =
        p != null && p.proposedById != null && p.proposedById == myId;
    final bool manages = me.can('manage_projects');
    final bool myProject =
        p != null && p.managerId != null && p.managerId == myId;
    final List<Widget> actions = <Widget>[];
    if (p != null) {
      if (p.status == 'proposed') {
        if (me.can('recommend_projects') && !mine && myId != null) {
          actions
            ..add(_button(
                'grp_project_support',
                Icons.thumb_up_alt_rounded,
                sw ? 'Napendekeza' : 'Recommend',
                ThemeConstants.successGreen,
                () => _support(p, yes: true)))
            ..add(_button(
                'grp_project_oppose',
                Icons.thumb_down_alt_rounded,
                sw ? 'Sipendekezi' : 'Do not recommend',
                ThemeConstants.warningAmber,
                () => _support(p, yes: false)));
        }
        if (me.can('approve_projects') && !mine) {
          actions
            ..add(_button(
                'grp_project_approve',
                Icons.verified_rounded,
                sw ? 'Idhinisha' : 'Approve',
                ThemeConstants.successGreen,
                () => _decide(p, approve: true)))
            ..add(_button(
                'grp_project_reject',
                Icons.block_rounded,
                sw ? 'Kataa' : 'Turn down',
                ThemeConstants.errorRed,
                () => _decide(p, approve: false)));
        }
        if (mine)
          actions.add(_button(
              'grp_project_withdraw',
              Icons.undo_rounded,
              sw ? 'Ondoa pendekezo' : 'Withdraw',
              ThemeConstants.errorRed,
              () => _withdraw(p)));
      }
      if (p.status == 'active' && (manages || myProject)) {
        actions.add(_button(
            'grp_project_progress',
            Icons.trending_up_rounded,
            sw ? 'Weka maendeleo' : 'Log progress',
            ThemeConstants.invAccent,
            () => _progress(p)));
      }
      if (manages && p.isOpen) {
        actions
          ..add(_button(
              'grp_project_manager',
              Icons.person_pin_rounded,
              sw ? 'Weka msimamizi' : 'Name a manager',
              ThemeConstants.primaryOrange,
              () => _manager(p)))
          ..add(_button(
              'grp_project_edit',
              Icons.edit_rounded,
              sw ? 'Hariri' : 'Edit',
              ThemeConstants.primaryOrange,
              () => _edit(p)));
      }
      if (manages && p.status == 'active') {
        actions
          ..add(_button(
              'grp_project_complete',
              Icons.task_alt_rounded,
              sw ? 'Kamilisha' : 'Complete',
              ThemeConstants.successGreen,
              () => _close(p, completed: true)))
          ..add(_button(
              'grp_project_cancel',
              Icons.cancel_rounded,
              sw ? 'Futa mradi' : 'Cancel project',
              ThemeConstants.errorRed,
              () => _close(p, completed: false)));
      }
    }
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Mradi' : 'Project', flat: true),
      body: SafeArea(
        child: p == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : GroupEmpty(_error!))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: joinGlowCards(<Widget>[
                      GlowListCard(
                        dividerKey: 'grp_project_detail_div',
                        padding: const EdgeInsets.all(14),
                        children: <Widget>[
                          Row(children: <Widget>[
                            Expanded(
                                child: Text(p.title,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800))),
                            GroupPill(
                                projectStateLabel(sw: sw, state: p.status),
                                color: projectStateColor(p.status)),
                          ]),
                          const SizedBox(height: 8),
                          GroupDetailRow(
                              sw ? 'Bajeti' : 'Budget', tsh(p.budget)),
                          if (p.status == 'active' || p.status == 'completed') ...<Widget>[
                            GroupDetailRow(sw ? 'Imeidhinishwa kutumika' : 'Approved to spend', tsh(p.committed)),
                            GroupDetailRow(sw ? 'Imelipwa' : 'Paid out', tsh(p.spent)),
                          ],
                          GroupDetailRow(
                              sw ? 'Namba' : 'Reference', p.reference),
                          if (p.proposerName != null)
                            GroupDetailRow(sw ? 'Ameapendekeza' : 'Proposed by',
                                p.proposerName!),
                          if (p.managerName != null)
                            GroupDetailRow(
                                sw ? 'Msimamizi' : 'Manager', p.managerName!),
                          if (p.startDate != null)
                            GroupDetailRow(sw ? 'Kuanza' : 'Starts',
                                dateLabel(p.startDate)),
                          if (p.endDate != null)
                            GroupDetailRow(sw ? 'Kumalizika' : 'Ends',
                                dateLabel(p.endDate)),
                          if (p.status == 'proposed')
                            GroupDetailRow(sw ? 'Maoni ya kamati' : 'Committee',
                                '${p.supports} ${sw ? 'wanapendekeza' : 'for'} · ${p.opposes} ${sw ? 'hawapendekezi' : 'against'}'),
                          if (p.decisionNote != null)
                            GroupDetailRow(
                                sw ? 'Sababu' : 'Reason', p.decisionNote!),
                          if (p.closingNote != null)
                            GroupDetailRow(
                                sw ? 'Maelezo ya kufunga' : 'Closing note',
                                p.closingNote!),
                          if (p.description != null) ...<Widget>[
                            const Divider(color: Colors.white12, height: 20),
                            Text(p.description!,
                                style: const TextStyle(color: Colors.white70)),
                          ],
                          if (p.status == 'active' ||
                              p.status == 'completed') ...<Widget>[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                  value: p.progress / 100,
                                  minHeight: 10,
                                  backgroundColor: Colors.white12,
                                  color: projectStateColor(p.status)),
                            ),
                            const SizedBox(height: 4),
                            Text('${p.progress}%',
                                style: const TextStyle(
                                    color: Colors.white60, fontSize: 12)),
                          ],
                        ],
                      ),
                      if (actions.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: actions),
                      ],
                      if (p.reviews.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 14),
                        GlowCard(
                          dividerKey: 'grp_project_reviews_div',
                          title:
                              sw ? 'Maoni ya kamati' : "The committee's views",
                          children: <Widget>[
                            for (final GroupProjectReview r in p.reviews)
                              ListTile(
                                leading: Icon(
                                    r.supports
                                        ? Icons.thumb_up_alt_rounded
                                        : Icons.thumb_down_alt_rounded,
                                    color: r.supports
                                        ? ThemeConstants.successGreen
                                        : ThemeConstants.warningAmber),
                                title: Text(r.memberName,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700)),
                                subtitle: r.note == null
                                    ? null
                                    : Text(r.note!,
                                        style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 12)),
                              ),
                          ],
                        ),
                      ],
                      if (p.updates.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 14),
                        GlowCard(
                          dividerKey: 'grp_project_updates_div',
                          title: sw ? 'Maendeleo' : 'Progress log',
                          children: <Widget>[
                            for (final GroupProjectUpdate u in p.updates)
                              ListTile(
                                title: Text(u.note,
                                    style:
                                        const TextStyle(color: Colors.white)),
                                subtitle: Text(
                                    '${dateLabel(u.createdAt)}${u.byName == null ? '' : ' · ${u.byName}'}',
                                    style: const TextStyle(
                                        color: Colors.white60, fontSize: 12)),
                                trailing: GroupPill('${u.progress}%',
                                    color: ThemeConstants.invAccent),
                              ),
                          ],
                        ),
                      ],
                    ])),
              ),
      ),
    );
  }
}

/// The form to propose a project, or (given [project]) to change its title, details and budget.
class ProjectForm extends StatefulWidget {
  const ProjectForm({required this.api, super.key, this.project});

  final GroupsApi api;
  final GroupProject? project;

  @override
  State<ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends State<ProjectForm> {
  late final TextEditingController _title =
      TextEditingController(text: widget.project?.title);
  late final TextEditingController _description =
      TextEditingController(text: widget.project?.description);
  late final TextEditingController _budget = TextEditingController(
      text: widget.project == null
          ? ''
          : widget.project!.budget.toStringAsFixed(0));
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final double? budget = double.tryParse(_budget.text.trim());
    if (_title.text.trim().length < 3) {
      setState(() => _error =
          sw ? 'Andika jina la mradi.' : 'Write the name of the project.');
      return;
    }
    if (budget == null) {
      setState(() => _error = sw ? 'Andika bajeti.' : 'Write the budget.');
      return;
    }
    final bool editing = widget.project != null;
    if (!await groupConfirm(
      context,
      title: editing
          ? (sw ? 'Hifadhi mabadiliko?' : 'Save the changes?')
          : (sw ? 'Tuma pendekezo la mradi?' : 'Send the project proposal?'),
      message: '${_title.text.trim()} · ${tsh(budget)}',
      yes: editing ? (sw ? 'Hifadhi' : 'Save') : (sw ? 'Tuma' : 'Send'),
      tone: GroupTone.positive,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final Map<String, dynamic> body = <String, dynamic>{
      'title': _title.text.trim(),
      'budget': budget,
      'description':
          _description.text.trim().isEmpty ? null : _description.text.trim(),
    };
    try {
      if (editing) {
        await widget.api.updateProject(widget.project!.id, body);
      } else {
        await widget.api.proposeProject(body);
      }
      if (!mounted) return;
      if (!editing)
        ThemeConstants.showSuccessSnackBar(
            context, sw ? 'Pendekezo limetumwa.' : 'Proposal sent.');
      Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = readableErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                widget.project == null
                    ? (sw ? 'Pendekeza mradi' : 'Propose a project')
                    : (sw ? 'Hariri mradi' : 'Edit the project'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800),
              ),
              const Divider(color: Colors.white12, height: 24),
              TextField(
                  key: const Key('grp_project_title'),
                  controller: _title,
                  maxLength: 150,
                  style: const TextStyle(color: Colors.white),
                  decoration: ThemeConstants.darkField(
                      sw ? 'Jina la mradi' : 'Name of the project')),
              TextField(
                key: const Key('grp_project_budget'),
                controller: _budget,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                ],
                style: const TextStyle(color: Colors.white),
                decoration: ThemeConstants.darkField(
                    sw ? 'Bajeti (TSh)' : 'Budget (TSh)'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('grp_project_description'),
                controller: _description,
                maxLines: 4,
                minLines: 2,
                maxLength: 3000,
                style: const TextStyle(color: Colors.white),
                decoration: ThemeConstants.darkField(sw
                    ? 'Maelezo: unataka kufanya nini, faida yake'
                    : 'Details: what to do, and the benefit'),
              ),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        key: const Key('grp_project_error'),
                        style:
                            const TextStyle(color: ThemeConstants.errorText))),
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const Key('grp_project_send'),
                style: FilledButton.styleFrom(
                    backgroundColor: ThemeConstants.successGreen,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _busy ? null : _send,
                icon: const Icon(Icons.send_rounded),
                label: Text(widget.project == null
                    ? (sw ? 'Tuma pendekezo' : 'Send the proposal')
                    : (sw ? 'Hifadhi' : 'Save')),
              ),
            ]),
      ),
    );
  }
}

class _ProgressDialog extends StatefulWidget {
  const _ProgressDialog({required this.from});

  final int from;

  @override
  State<_ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<_ProgressDialog> {
  late double _value = widget.from.toDouble();
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool ready = _note.text.trim().length >= 2;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: ThemeConstants.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(sw ? 'Maendeleo ya mradi' : 'Project progress',
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        const SizedBox(width: double.maxFinite),
        Text('${_value.round()}%',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        Slider(
            key: const Key('grp_project_slider'),
            value: _value,
            max: 100,
            divisions: 20,
            onChanged: (final double v) => setState(() => _value = v)),
        TextField(
          key: const Key('grp_project_note'),
          controller: _note,
          onChanged: (_) => setState(() {}),
          maxLength: 500,
          style: const TextStyle(color: Colors.white),
          decoration:
              ThemeConstants.darkField(sw ? 'Kilichofanyika' : 'What was done'),
        ),
      ]),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(sw ? 'Ghairi' : 'Cancel',
                style: const TextStyle(color: Colors.white60))),
        TextButton(
          key: const Key('grp_project_progress_save'),
          onPressed: ready
              ? () =>
                  Navigator.pop(context, (_value.round(), _note.text.trim()))
              : null,
          child: Text(sw ? 'Hifadhi' : 'Save',
              style: TextStyle(
                  color: ready ? ThemeConstants.successGreen : Colors.white24,
                  fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
