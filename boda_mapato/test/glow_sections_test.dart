import 'package:boda_mapato/modules/inventory/screens/widgets/glow_list_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cards inside GlowSections are one card: one frame, no gap, a glowing line and the gold title between them', (final WidgetTester t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: const <Widget>[
            GlowSections(children: <Widget>[
              GlowCard(title: 'Details', children: <Widget>[Text('Born'), Text('Address')]),
              GlowCard(title: 'Money', children: <Widget>[Text('Savings')]),
            ]),
          ]),
        ),
      ),
    );

    expect(find.byKey(const ValueKey<String>('none')), findsNothing);
    final double endOfFirst = t.getBottomLeft(find.text('Address')).dy;
    final double startOfSecond = t.getTopLeft(find.text('Money')).dy;
    expect(startOfSecond - endOfFirst, lessThan(40), reason: 'no gap of a card between the parts, only the line');
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Money'), findsOneWidget);
  });

  testWidgets('a GlowCard on its own keeps its frame and the air below it', (final WidgetTester t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: GlowCard(title: 'Alone', children: <Widget>[Text('Row')]))));
    expect(find.text('Alone'), findsOneWidget);
    expect(find.byType(GlowSections), findsNothing);
  });

  testWidgets('joinGlowCards joins runs of cards (dropping the spacers between them) and leaves everything else where it is', (final WidgetTester t) async {
    final List<Widget> out = joinGlowCards(const <Widget>[
      GlowCard(title: 'A', children: <Widget>[Text('a')]),
      SizedBox(height: 12),
      GlowCard(title: 'B', children: <Widget>[Text('b')]),
      Text('heading'),
      GlowCard(title: 'C', children: <Widget>[Text('c')]),
      SizedBox(height: 90),
      GlowCard(title: 'D', children: <Widget>[Text('d')]),
    ]);

    // A and B joined; the heading stays; C alone; the tall gap is not a spacer, so D is alone too.
    expect(out.length, 5);
    expect(out[0], isA<GlowSections>());
    expect((out[0] as GlowSections).children.length, 2);
    expect(out[1], isA<Text>());
    expect(out[2], isA<GlowCard>());
    expect(out[3], isA<SizedBox>());
    expect(out[4], isA<GlowCard>());
  });
}
