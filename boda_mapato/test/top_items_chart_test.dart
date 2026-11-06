import 'package:boda_mapato/modules/inventory/screens/widgets/top_items_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const List<TopItem> _items = <TopItem>[
  TopItem(name: 'Box Braids', value: 120000),
  TopItem(name: 'Kuweka Weave (Sew-in)', value: 90000),
  TopItem(name: 'Senegalese Twist', value: 70000),
  TopItem(name: 'Kunyoosha Nywele', value: 15000),
  TopItem(name: 'Kucha za Gel', value: 35000),
];

Widget _host(final Widget child) => MaterialApp(home: Scaffold(backgroundColor: const Color(0xFF0D3C4D), body: Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: 380, child: child))));

void main() {
  testWidgets('draws the legend and the chart for the items', (t) async {
    await t.pumpWidget(_host(const TopItemsChart(items: _items, legend: 'Sales (TSH)', trendLabel: 'Trend line')));
    await t.pump(const Duration(milliseconds: 800));

    expect(find.text('Sales (TSH)'), findsOneWidget);
    expect(find.text('Trend line'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('top_items_chart')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('short money reads like the chart: 11.5M, 120K, 950', () {
    expect(shortAmount(11500000), '11.5M');
    expect(shortAmount(120000), '120K');
    expect(shortAmount(35000), '35.0K');
    expect(shortAmount(950), '950');
  });

  test('the bars use the eight colours in order and the trend line is navy', () {
    expect(kTopItemColors.length, 8);
    expect(kTopItemColors.first, const Color(0xFF007BFF));
    expect(kTopItemColors[5], const Color(0xFFFD7E14));
    expect(kTopItemsTrend, const Color(0xFF003580));
  });
}
