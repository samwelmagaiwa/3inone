import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../../inventory/screens/widgets/glow_list_card.dart';
import '../../models/group_models.dart';
import '../../models/group_records_models.dart';
import '../../services/groups_api.dart';
import 'groups_ui.dart';

String documentKindLabel({required final bool sw, required final String kind}) => switch (kind) {
      'photo' => sw ? 'Picha' : 'Photo',
      'id' => sw ? 'Nakala ya kitambulisho' : 'ID copy',
      _ => sw ? 'Hati nyingine' : 'Other paper',
    };

/// A member's photo and papers, kept privately (links expire). Whoever registers members adds and removes them; an ID copy only by whoever
/// may see NIDA numbers (the server hides ID copies from everyone else).
class MemberDocumentsCard extends StatefulWidget {
  const MemberDocumentsCard({required this.api, required this.me, required this.memberId, required this.documents, required this.onChanged, super.key, this.photoUrl});

  final GroupsApi api;
  final GroupMe me;
  final int memberId;
  final List<Map<String, dynamic>> documents;
  final String? photoUrl;
  final Future<void> Function() onChanged;

  @override
  State<MemberDocumentsCard> createState() => _MemberDocumentsCardState();
}

class _MemberDocumentsCardState extends State<MemberDocumentsCard> {
  bool _busy = false;

  Future<void> _add() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final String? kind = await groupActions(context, title: sw ? 'Ongeza' : 'Add', actions: <GroupSheetAction>[
      GroupSheetAction(icon: Icons.photo_camera_outlined, label: sw ? 'Picha (kamera)' : 'Photo (camera)', value: 'photo_camera'),
      GroupSheetAction(icon: Icons.photo_library_outlined, label: sw ? 'Picha (kwenye simu)' : 'Photo (from the phone)', value: 'photo_gallery'),
      if (widget.me.can('view_sensitive')) GroupSheetAction(icon: Icons.badge_outlined, label: documentKindLabel(sw: sw, kind: 'id'), value: 'id'),
      GroupSheetAction(icon: Icons.description_outlined, label: documentKindLabel(sw: sw, kind: 'other'), value: 'other'),
    ]);
    if (kind == null || !mounted) return;
    Uint8List? bytes;
    String name = 'file';
    if (kind.startsWith('photo')) {
      final XFile? f = await ImagePicker().pickImage(source: kind == 'photo_camera' ? ImageSource.camera : ImageSource.gallery, imageQuality: 75, maxWidth: 1600);
      if (f == null) return;
      bytes = await f.readAsBytes();
      name = f.name.toLowerCase().endsWith('.png') ? f.name : 'photo.jpg';
    } else {
      final FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: <String>['jpg', 'jpeg', 'png', 'pdf'], withData: true);
      final PlatformFile? f = r?.files.firstOrNull;
      if (f?.bytes == null) return;
      bytes = f!.bytes;
      name = f.name;
    }
    if (!mounted || bytes == null) return;
    if (bytes.length > 5 * 1024 * 1024) {
      ThemeConstants.showErrorSnackBar(context, sw ? 'Faili ni kubwa mno (zaidi ya MB 5).' : 'The file is too big (over 5 MB).');
      return;
    }
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Hifadhi faili?' : 'Keep this file?',
      message: '${documentKindLabel(sw: sw, kind: kind.startsWith('photo') ? 'photo' : kind)} · $name',
      yes: sw ? 'Hifadhi' : 'Keep',
      tone: GroupTone.positive,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await widget.api.uploadDocument(widget.memberId, bytes, name, kind: kind.startsWith('photo') ? 'photo' : kind);
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Imehifadhiwa.' : 'Kept.');
      await widget.onChanged();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove(final GroupDocument d) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final bool ok = await groupConfirm(context, title: sw ? 'Ondoa faili?' : 'Remove the file?', message: documentKindLabel(sw: sw, kind: d.kind), yes: sw ? 'Ondoa' : 'Remove', tone: GroupTone.danger);
    if (!ok) return;
    try {
      await widget.api.removeDocument(widget.memberId, d.id);
      await widget.onChanged();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final List<GroupDocument> docs = <GroupDocument>[for (final Map<String, dynamic> d in widget.documents) GroupDocument.fromJson(d)];
    final bool mayEdit = widget.me.can('manage_members');
    return GlowCard(
      title: sw ? 'Picha na hati' : 'Photo and papers',
      children: <Widget>[
        if (widget.photoUrl != null)
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(48),
              child: Image.network(widget.photoUrl!, key: const Key('grp_member_photo'), width: 96, height: 96, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: Colors.white38, size: 64)),
            ),
          ),
        if (docs.isEmpty) Text(sw ? 'Hakuna faili.' : 'No files.', style: const TextStyle(color: Colors.white60)),
        for (final GroupDocument d in docs)
          ListTile(
            key: Key('grp_doc_${d.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(d.kind == 'photo' ? Icons.image_outlined : (d.kind == 'id' ? Icons.badge_outlined : Icons.description_outlined), color: ThemeConstants.invAccent),
            title: Text(d.caption ?? documentKindLabel(sw: sw, kind: d.kind), style: const TextStyle(color: Colors.white)),
            onTap: d.url == null ? null : () => launchUrl(Uri.parse(d.url!), mode: LaunchMode.externalApplication),
            trailing: mayEdit ? IconButton(icon: const Icon(Icons.delete_outline, color: ThemeConstants.errorText), onPressed: () => _remove(d)) : null,
          ),
        if (mayEdit)
          TextButton.icon(
            key: const Key('grp_doc_add'),
            onPressed: _busy ? null : _add,
            icon: const Icon(Icons.upload_file_rounded, color: ThemeConstants.primaryOrange),
            label: Text(sw ? 'Ongeza picha au hati' : 'Add a photo or paper', style: const TextStyle(color: ThemeConstants.primaryOrange)),
          ),
      ],
    );
  }
}
