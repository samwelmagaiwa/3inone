import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:boda_mapato/modules/groups/screens/widgets/member_avatar.dart';
import 'package:boda_mapato/modules/groups/screens/widgets/member_documents_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _png(final int side) async {
  final ui.PictureRecorder rec = ui.PictureRecorder();
  ui.Canvas(rec).drawRect(Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()), ui.Paint()..color = const Color(0xFF1F6F8A));
  final ui.Image image = await rec.endRecording().toImage(side, side);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  test('initials are the first letters of the first and last name', () {
    expect(MemberAvatar.initials('Asha Mussa Juma'), 'AJ');
    expect(MemberAvatar.initials('  neema  '), 'N');
    expect(MemberAvatar.initials(''), '?');
  });

  testWidgets('with no photo the frame shows initials; whoever may change it sees the camera badge', (final WidgetTester t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: MemberAvatar(name: 'Asha Mussa Juma', ringColor: Colors.green, editable: true)))));
    expect(find.text('AJ'), findsOneWidget);
    expect(find.byKey(const Key('grp_member_avatar_edit')), findsOneWidget);
    expect(find.byKey(const Key('grp_member_photo')), findsNothing);
  });

  testWidgets('a member who may not be edited has no camera badge', (final WidgetTester t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: MemberAvatar(name: 'Asha Juma', ringColor: Colors.green)))));
    expect(find.byKey(const Key('grp_member_avatar_edit')), findsNothing);
  });

  testWidgets('a profile photo is a JPG or PNG, up to 2 MB and at least 200 by 200 pixels', (final WidgetTester t) async {
    await t.runAsync(() async {
      expect(await memberPhotoProblem(bytes: await _png(240), name: 'me.png', sw: false), isNull);
      expect(await memberPhotoProblem(bytes: await _png(240), name: 'me.gif', sw: false), contains('JPG or PNG'));
      expect(await memberPhotoProblem(bytes: await _png(50), name: 'me.png', sw: false), contains('too small'));
      expect(await memberPhotoProblem(bytes: Uint8List(memberPhotoMaxBytes + 1), name: 'me.jpg', sw: false), contains('too big'));
      expect(await memberPhotoProblem(bytes: Uint8List.fromList(<int>[1, 2, 3]), name: 'me.jpg', sw: false), contains('not a readable'));
      expect(await memberPhotoProblem(bytes: await _png(50), name: 'me.png', sw: true), contains('ndogo'));
    });
  });
}
