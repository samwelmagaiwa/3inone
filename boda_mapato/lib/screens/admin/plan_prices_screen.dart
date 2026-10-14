import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../../constants/theme_constants.dart";
import "../../models/plan_prices.dart";
import "../../services/api_service.dart";
import "../../services/localization_service.dart";
import "../../utils/plan_text.dart";
import "../../utils/server_message.dart";

/// Where the screen gets and saves the prices. The app uses [ApiPlanPricesDataSource]; tests supply a fake.
abstract class PlanPricesDataSource {
  Future<PlanCatalog> load();

  /// Only what changed: `{plan: {months: amount}}`, an amount of null clearing that price.
  Future<PlanCatalog> save(Map<String, Map<int, double?>> changes);
}

class ApiPlanPricesDataSource implements PlanPricesDataSource {
  ApiPlanPricesDataSource() {
    _api.initialize();
  }

  final ApiService _api = ApiService();

  PlanCatalog _catalog(final Map<String, dynamic> res) => PlanCatalog.fromJson(Map<String, dynamic>.from(res["data"] as Map));

  @override
  Future<PlanCatalog> load() async => _catalog(await _api.getPlanPrices());

  @override
  Future<PlanCatalog> save(final Map<String, Map<int, double?>> changes) async => _catalog(
        await _api.savePlanPrices(<String, Map<String, double?>>{
          for (final MapEntry<String, Map<int, double?>> e in changes.entries)
            e.key: <String, double?>{for (final MapEntry<int, double?> p in e.value.entries) "${p.key}": p.value},
        }),
      );
}

/// Super admin: what each plan costs for 1, 3, 6 and 12 months. Basic covers one service, Standard two and Premium all
/// three; what is set here shows on the registration form straight away, so nothing needs changing in the code or on
/// the server when a price changes.
class PlanPricesScreen extends StatefulWidget {
  const PlanPricesScreen({super.key, this.dataSource});

  final PlanPricesDataSource? dataSource;

  @override
  State<PlanPricesScreen> createState() => _PlanPricesScreenState();
}

class _PlanPricesScreenState extends State<PlanPricesScreen> {
  late final PlanPricesDataSource _source = widget.dataSource ?? ApiPlanPricesDataSource();
  final Map<String, TextEditingController> _fields = <String, TextEditingController>{};
  final Map<String, double?> _saved = <String, double?>{};

  PlanCatalog _catalog = PlanCatalog.fallback;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _sw => LocalizationService.instance.isSwahili;

  static String _id(final String plan, final int months) => "$plan:$months";

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final TextEditingController c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _show(final double? v) => v == null ? "" : (v == v.roundToDouble() ? v.round().toString() : v.toString());

  /// Put the server's answer into the fields.
  void _fill(final PlanCatalog catalog) {
    _catalog = catalog;
    for (final PlanOffer o in catalog.offers) {
      for (final int m in catalog.periods) {
        final String id = _id(o.plan, m);
        final double? price = o.priceFor(m);
        _saved[id] = price;
        (_fields[id] ??= TextEditingController()).text = _show(price);
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final PlanCatalog catalog = await _source.load();
      if (!mounted) return;
      setState(() {
        _fill(catalog);
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = readableErrorMessage(e);
      });
    }
  }

  /// What is typed in a field: null when empty, NaN when it is not a usable price.
  double? _typed(final String plan, final int months) {
    final String t = (_fields[_id(plan, months)]?.text ?? "").replaceAll(",", "").trim();
    if (t.isEmpty) return null;
    final double? v = double.tryParse(t);
    return (v == null || v <= 0) ? double.nan : v;
  }

  bool _isBad(final String plan, final int months) => (_typed(plan, months) ?? 0).isNaN;

  bool get _anyBad => _catalog.offers.any((final PlanOffer o) => _catalog.periods.any((final int m) => _isBad(o.plan, m)));

  /// Only the prices that differ from what was saved.
  Map<String, Map<int, double?>> get _changes {
    final Map<String, Map<int, double?>> out = <String, Map<int, double?>>{};
    for (final PlanOffer o in _catalog.offers) {
      for (final int m in _catalog.periods) {
        final double? now = _typed(o.plan, m);
        if (now != null && now.isNaN) continue;
        if (now != _saved[_id(o.plan, m)]) (out[o.plan] ??= <int, double?>{})[m] = now;
      }
    }
    return out;
  }

  bool get _dirty => _changes.isNotEmpty;

  Future<void> _save() async {
    if (_anyBad) {
      setState(() => _error = _sw ? "Kuna bei isiyo sahihi. Weka namba kubwa kuliko sifuri, au iache wazi." : "A price is not valid. Enter a number above zero, or leave it empty.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final PlanCatalog catalog = await _source.save(_changes);
      if (!mounted) return;
      setState(() {
        _fill(catalog);
        _busy = false;
      });
      ThemeConstants.showSuccessSnackBar(context, _sw ? "Bei zimehifadhiwa. Zinaonekana kwenye usajili sasa." : "Prices saved. They show on the registration form now.");
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = readableErrorMessage(e);
      });
    }
  }

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(_sw ? "Mipango na Bei" : "Plans & Prices"),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && !_catalog.configured && _fields.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: Text(_sw ? "Jaribu tena" : "Retry")),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          _sw
              ? "Kila mpango ni idadi ya huduma: ${planNameText("basic", sw: true)} ni huduma MOJA, ${planNameText("standard", sw: true)} ni huduma 2, Premium ni huduma ZOTE 3. Bei unazoweka hapa zinaonekana mara moja kwenye fomu ya usajili ya mteja."
              : "Each plan is a number of services: Basic is ONE service, Standard is TWO, Premium is ALL THREE. The prices you set here show on the client's registration form straight away.",
          key: const ValueKey<String>("plans_intro"),
          style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.4),
        ),
        const SizedBox(height: 14),
        for (final PlanOffer o in _catalog.offers) ...<Widget>[_planCard(o), const SizedBox(height: 14)],
        ..._sanityNotes(),
        _preview(),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(_error!, key: const ValueKey<String>("prices_error"), style: const TextStyle(color: Colors.redAccent)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey<String>("save_prices"),
          onPressed: (_busy || !_dirty) ? null : _save,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_dirty ? (_sw ? "Hifadhi bei" : "Save prices") : (_sw ? "Hakuna mabadiliko" : "No changes")),
        ),
      ],
    );
  }

  Widget _planCard(final PlanOffer o) {
    const int cols = 2;
    final List<int> periods = _catalog.periods;
    return ThemeConstants.buildGlassCard(
      child: Padding(
        key: ValueKey<String>("plan_card_${o.plan}"),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(planNameText(o.plan, sw: _sw), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ThemeConstants.primaryCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ThemeConstants.primaryCyan.withValues(alpha: 0.5)),
                  ),
                  child: Text(planCoverText(o.servicesIncluded, sw: _sw), key: ValueKey<String>("plan_covers_${o.plan}"), style: const TextStyle(color: ThemeConstants.primaryCyan, fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < periods.length; i += cols)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (int j = i; j < i + cols && j < periods.length; j++) ...<Widget>[
                      if (j > i) const SizedBox(width: 10),
                      Expanded(child: _priceField(o.plan, periods[j])),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _priceField(final String plan, final int months) {
    final bool bad = _isBad(plan, months);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          key: ValueKey<String>("price_${plan}_$months"),
          controller: _fields[_id(plan, months)],
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r"[0-9.,]"))],
          style: const TextStyle(color: Colors.white),
          onChanged: (final String _) => setState(() => _error = null),
          decoration: InputDecoration(
            labelText: periodText(months, sw: _sw),
            labelStyle: const TextStyle(color: Colors.white60),
            prefixText: "${_catalog.currency} ",
            prefixStyle: const TextStyle(color: Colors.white54),
            errorText: bad ? (_sw ? "Si sahihi" : "Not valid") : null,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        _hint(plan, months),
      ],
    );
  }

  /// Under a price: what it comes to a month, and whether it saves anything against paying month by month.
  Widget _hint(final String plan, final int months) {
    final double? price = _typed(plan, months);
    if (price == null || price.isNaN) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, left: 4),
        child: Text(_sw ? "Bado haijawekwa" : "Not set yet", key: ValueKey<String>("hint_${plan}_$months"), style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
      );
    }
    if (months == 1) return const SizedBox(height: 4);

    final double perMonth = price / months;
    final double? monthly = _typed(plan, 1);
    String text = _sw ? "≈ ${moneyText(_catalog.currency, perMonth)} kwa mwezi" : "≈ ${moneyText(_catalog.currency, perMonth)} a month";
    Color color = Colors.white54;
    if (monthly != null && !monthly.isNaN && monthly > 0) {
      final double saving = (1 - perMonth / monthly) * 100;
      if (saving >= 0.5) {
        text += _sw ? " · unaokoa ${saving.round()}%" : " · saves ${saving.round()}%";
        color = Colors.greenAccent;
      } else if (saving <= -0.5) {
        text += _sw ? " · ghali kuliko kulipa kila mwezi" : " · dearer than paying monthly";
        color = Colors.amberAccent;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4),
      child: Text(text, key: ValueKey<String>("hint_${plan}_$months"), style: TextStyle(color: color, fontSize: 11.5)),
    );
  }

  /// A bigger plan that costs less than a smaller one is almost always a typing mistake: say so (it can still be saved).
  List<Widget> _sanityNotes() {
    final List<String> notes = <String>[];
    final List<PlanOffer> offers = _catalog.offers;
    for (final int m in _catalog.periods) {
      for (int i = 1; i < offers.length; i++) {
        final double? smaller = _typed(offers[i - 1].plan, m);
        final double? bigger = _typed(offers[i].plan, m);
        if (smaller != null && bigger != null && !smaller.isNaN && !bigger.isNaN && bigger < smaller) {
          notes.add(_sw
              ? "${planNameText(offers[i].plan, sw: true)} (${periodText(m, sw: true)}) ni rahisi kuliko ${planNameText(offers[i - 1].plan, sw: true)}. Hakikisha ni sahihi."
              : "${planNameText(offers[i].plan, sw: false)} (${periodText(m, sw: false)}) costs less than ${planNameText(offers[i - 1].plan, sw: false)}. Check it is right.");
        }
      }
    }
    if (notes.isEmpty) return <Widget>[];
    return <Widget>[
      Container(
        key: const ValueKey<String>("price_warnings"),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amberAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[for (final String n in notes) Text(n, style: const TextStyle(color: Colors.amberAccent, fontSize: 12.5))],
        ),
      ),
      const SizedBox(height: 14),
    ];
  }

  /// What a client will read for one month, from what is typed right now.
  Widget _preview() {
    return ThemeConstants.buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(_sw ? "Mteja ataona (mwezi 1)" : "What a client sees (1 month)", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final PlanOffer o in _catalog.offers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  () {
                    final double? p = _typed(o.plan, 1);
                    final String price = (p == null || p.isNaN) ? (_sw ? "bei haijawekwa" : "price not set") : moneyText(_catalog.currency, p);
                    return "${planNameText(o.plan, sw: _sw)} · ${planCoverText(o.servicesIncluded, sw: _sw)} · $price";
                  }(),
                  key: ValueKey<String>("preview_${o.plan}"),
                  style: const TextStyle(color: Colors.white70, fontSize: 13.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
