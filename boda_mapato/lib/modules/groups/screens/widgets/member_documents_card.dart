import 'dart:typed_data';
import 'dart:ui' as ui;

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

/// The biggest a profile photo may be, and the smallest each side of it (a face must be recognisable). Other papers may be up to 5 MB.
const int memberPhotoMaxBytes = 2 * 1024 * 1024;
const int memberPaperMaxBytes = 5 * 1024 * 1024;
const int memberPhotoMinSide = 200;

/// What is wrong with a photo, in words for the person, or null when it is fine: a JPG or PNG, up to 2 MB, at least 200 x 200 pixels.
Future<String?> memberPhotoProblem({required final Uint8List bytes, required final String name, required final bool sw}) async {
  final String lower = name.toLowerCase();
  if (!(lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png'))) {
    return sw ? 'Picha lazima iwe JPG au PNG.' : 'A photo must be a JPG or PNG.';
  }
  if (bytes.length > memberPhotoMaxBytes) {
    return sw ? 'Picha ni kubwa mno (zaidi ya MB 2). Chagua ndogo zaidi.' : 'The photo is too big (over 2 MB). Choose a smaller one.';
  }
  try {
    final ui.Image image = await decodeImageFromList(bytes);
    final bool small = image.width < memberPhotoMinSide || image.height < memberPhotoMinSide;
    image.dispose();
    if (small) return sw ? 'Picha ni ndogo mno; iwe angalau pikseli 200 kwa 200.' : 'The photo is too small; it must be at least 200 by 200 pixels.';
  } on Exception {
    return sw ? 'Faili hii si picha inayosomeka.' : 'This file is not a readable picture.';
  }
  return null;
}

/// Picks a file (a photo from the camera or the phone, or a paper), checks it, asks Yes/No and sends it. [photoOnly] goes straight to a photo
/// (the profile picture). True when something was kept.
Future<bool> addMemberDocument(
  final BuildContext context, {
  required final GroupsApi api,
  required final GroupMe me,
  required final int memberId,
  final bool photoOnly = false,
}) async {
  final bool sw = context.read<LocalizationService>().isSwahili;
  final String? kind = await groupActions(context, title: photoOnly ? (sw ? 'Picha ya wasifu' : 'Profile photo') : (sw ? 'Ongeza' : 'Add'), actions: <GroupSheetAction>[
    GroupSheetAction(icon: Icons.photo_camera_outlined, label: sw ? 'Picha (kamera)' : 'Photo (camera)', value: 'photo_camera'),
    GroupSheetAction(icon: Icons.photo_library_outlined, label: sw ? 'Picha (kwenye simu)' : 'Photo (from the phone)', value: 'photo_gallery'),
    if (!photoOnly && me.can('view_sensitive')) GroupSheetAction(icon: Icons.badge_outlined, label: documentKindLabel(sw: sw, kind: 'id'), value: 'id'),
    if (!photoOnly) GroupSheetAction(icon: Icons.description_outlined, label: documentKindLabel(sw: sw, kind: 'other'), value: 'other'),
  ]);
  if (kind == null || !context.mounted) return false;
  Uint8List? bytes;
  String name = 'file';
  final bool isPhoto = kind.startsWith('photo');
  if (isPhoto) {
    final XFile? f = await ImagePicker().pickImage(source: kind == 'photo_camera' ? ImageSource.camera : ImageSource.gallery, imageQuality: 80, maxWidth: 1600);
    if (f == null) return false;
    bytes = await f.readAsBytes();
    name = f.name.toLowerCase().endsWith('.png') ? f.name : (f.name.toLowerCase().endsWith('.jpeg') ? f.name : 'photo.jpg');
  } else {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: <String>['jpg', 'jpeg', 'png', 'pdf'], withData: true);
    final PlatformFile? f = r?.files.firstOrNull;
    if (f?.bytes == null) return false;
    bytes = f!.bytes;
    name = f.name;
  }
  if (!context.mounted || bytes == null) return false;
  final String? problem = isPhoto
      ? await memberPhotoProblem(bytes: bytes, name: name, sw: sw)
      : (bytes.length > memberPaperMaxBytes ? (sw ? 'Faili ni kubwa mno (zaidi ya MB 5).' : 'The file is too big (over 5 MB).') : null);
  if (problem != null) {
    if (context.mounted) ThemeConstants.showErrorSnackBar(context, problem);
    return false;
  }
  if (!context.mounted) return false;
  final bool ok = await groupConfirm(
    context,
    title: isPhoto ? (sw ? 'Weka kuwa picha ya wasifu?' : 'Keep as the profile photo?') : (sw ? 'Hifadhi faili?' : 'Keep this file?'),
    message: '${documentKindLabel(sw: sw, kind: isPhoto ? 'photo' : kind)} · $name',
    yes: sw ? 'Hifadhi' : 'Keep',
    tone: GroupTone.positive,
  );
  if (!ok || !context.mounted) return false;
  try {
    await api.uploadDocument(memberId, bytes, name, kind: isPhoto ? 'photo' : kind);
    if (context.mounted) ThemeConstants.showSuccessSnackBar(context, sw ? 'Imehifadhiwa.' : 'Kept.');
    return true;
  } on Exception catch (e) {
    if (context.mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    return false;
  }
}

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
    setState(() => _busy = true);
    try {
      if (await addMemberDocument(context, api: widget.api, me: widget.me, memberId: widget.memberId)) await widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
