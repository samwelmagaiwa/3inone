import 'package:boda_mapato/modules/inventory/screens/widgets/glow_list_card.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/joined_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The list card of the inventory screens: every row in ONE card, each divided from the next by the glowing line, with no gaps.
Future<void> _show(WidgetTester t, List<Widget> rows, {String? dividerKey}) => t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: GlowListCard(dividerKey: dividerKey, children: rows)))));

void main() {
  testWidgets('n rows have n - 1 glowing lines between them', (t) async {
    await _show(t, const <Widget>[Text('one'), Text('two'), Text('three')]);

    expect(find.byType(SectionGlowDivider), findsNWidgets(2));
    expect(find.text('one'), findsOneWidget);
    expect(find.text('three'), findsOneWidget);
  });

  testWidgets('one row has no line, and no rows is just the empty card', (t) async {
    await _show(t, const <Widget>[Text('only')]);
    expect(find.byType(SectionGlowDivider), findsNothing);

    await _show(t, const <Widget>[]);
    expect(find.byType(SectionGlowDivider), findsNothing);
  });

  testWidgets('each line is named with its number, so a screen can be checked', (t) async {
    await _show(t, const <Widget>[Text('a'), Text('b'), Text('c')], dividerKey: 'x');

    expect(find.byKey(const ValueKey<String>('x_1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('x_2')), findsOneWidget);
  });

  testWidgets('the rows follow each other with only the line and the row padding between them (no gap)', (t) async {
    await _show(t, const <Widget>[Text('one'), Text('two')]);

    final double gap = t.getTopLeft(find.text('two')).dy - t.getBottomLeft(find.text('one')).dy;
    expect(gap, lessThan(40), reason: 'padding and a 2.5 px line, not a card margin');
  });
}
