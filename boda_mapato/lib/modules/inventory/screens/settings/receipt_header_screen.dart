import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/api_service.dart';
import '../../../../services/localization_service.dart';
import '../../providers/depot_provider.dart';
import '../widgets/inventory_widgets.dart';

/// Admin/manager screen for configuring every field that appears on the
/// printed sales receipt: shop identity, contact info, legal details and footer.
/// Changes are persisted immediately to [inventory_settings] on the backend.
class ReceiptHeaderScreen extends StatefulWidget {
  const ReceiptHeaderScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const ReceiptHeaderScreen(),
      );

  @override
  State<ReceiptHeaderScreen> createState() => _ReceiptHeaderScreenState();
}

class _ReceiptHeaderScreenState extends State<ReceiptHeaderScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = false;
  bool _saving = false;
  bool _previewExpanded = false;

  // controllers ----------------------------------------------------------------
  final _cName        = TextEditingController();
  final _cTagline     = TextEditingController();
  final _cAddress     = TextEditingController();
  final _cPhone       = TextEditingController();
  final _cEmail       = TextEditingController();
  final _cWebsite     = TextEditingController();
  final _cTin         = TextEditingController();
  final _cFooter      = TextEditingController();
  bool  _showBarcode  = true;
  bool  _showTin      = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _hydrate(context.read<DepotProvider>().settings);
    _loading = context.read<DepotProvider>().settings.isEmpty;
    if (_loading) _fetchAndHydrate();
  }

  void _hydrate(Map<String, String> s) {
    _cName.text    = s['depot_name']          ?? '';
    _cTagline.text = s['receipt_tagline']     ?? '';
    _cAddress.text = s['depot_address']       ?? '';
    _cPhone.text   = s['depot_phone']         ?? '';
    _cEmail.text   = s['receipt_email']       ?? '';
    _cWebsite.text = s['receipt_website']     ?? '';
    _cTin.text     = s['receipt_tin']         ?? '';
    _cFooter.text  = s['receipt_footer_note'] ?? '';
    _showBarcode   = (s['receipt_show_barcode'] ?? '1') == '1';
    _showTin       = (s['receipt_show_tin']     ?? '1') == '1';
  }

  Future<void> _fetchAndHydrate() async {
    await context.read<DepotProvider>().fetchSettings();
    if (!mounted) return;
    _hydrate(context.read<DepotProvider>().settings);
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await context.read<DepotProvider>().saveSettings({
      'depot_name':           _cName.text.trim(),
      'receipt_tagline':      _cTagline.text.trim(),
      'depot_address':        _cAddress.text.trim(),
      'depot_phone':          _cPhone.text.trim(),
      'receipt_email':        _cEmail.text.trim(),
      'receipt_website':      _cWebsite.text.trim(),
      'receipt_tin':          _cTin.text.trim(),
      'receipt_footer_note':  _cFooter.text.trim(),
      'receipt_show_barcode': _showBarcode ? '1' : '0',
      'receipt_show_tin':     _showTin     ? '1' : '0',
    });
    if (!mounted) return;
    setState(() => _saving = false);
    ThemeConstants.showInfoSnackBar(
      context,
      _saving
          ? ''
          : ok
              ? LocalizationService.instance.translate('receipt_settings_saved')
              : LocalizationService.instance.translate('operation_failed'),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [_cName, _cTagline, _cAddress, _cPhone, _cEmail, _cWebsite, _cTin, _cFooter]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    if (_loading) {
      return Scaffold(
        backgroundColor: ThemeConstants.primaryBlue,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: Text(loc.translate('receipt_settings_title')),
        ),
        body: const Center(child: CircularProgressIndicator(color: Colors.white70)),
      );
    }

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          loc.translate('receipt_settings_title'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: [
            Tab(text: loc.translate('settings_tab')),
            Tab(text: loc.translate('preview_tab')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildFormTab(loc),
          _buildPreviewTab(),
        ],
      ),
    );
  }

  // ── Form tab ────────────────────────────────────────────────────────────────

  Widget _buildFormTab(LocalizationService loc) => ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 32.h),
        children: [
          _section(
            icon: Icons.store_rounded,
            title: loc.translate('shop_identity'),
            children: [
              _field(_cName,    loc.translate('shop_name_required'), hint: context.watch<DepotProvider>().capabilities.depotWording ? 'e.g. DEPOT DODOMA' : 'e.g. MAMA ASHA SHOP', required: true),
              _field(_cTagline, loc.translate('tagline'), hint: 'e.g. Karibu Kununua!'),
            ],
          ),
          SizedBox(height: 12.h),
          _section(
            icon: Icons.contact_phone_rounded,
            title: loc.translate('contact_info'),
            children: [
              _field(_cPhone,   loc.translate('phone_number'), hint: 'e.g. +255 700 000 000'),
              _field(_cAddress, loc.translate('address'),      hint: 'e.g. Barabara Kuu, Block B'),
              _field(_cEmail,   loc.translate('email'),        hint: 'e.g. info@duka.co.tz'),
              _field(_cWebsite, loc.translate('website'),      hint: 'e.g. www.duka.co.tz'),
            ],
          ),
          SizedBox(height: 12.h),
          _section(
            icon: Icons.receipt_long_rounded,
            title: loc.translate('legal'),
            children: [
              _field(_cTin, loc.translate('tin_number'), hint: 'e.g. 100-000-000'),
              _toggle(
                label: loc.translate('show_tin_on_receipt'),
                value: _showTin,
                onChanged: (v) => setState(() => _showTin = v),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          _section(
            icon: Icons.text_snippet_rounded,
            title: loc.translate('footer_message'),
            children: [
              _fieldMultiline(
                _cFooter,
                loc.translate('footer_note'),
                hint: LocalizationService.instance.translate('e_g_no_returns_without_a'),
              ),
              _toggle(
                label: loc.translate('show_barcode_on_receipt'),
                value: _showBarcode,
                onChanged: (v) => setState(() => _showBarcode = v),
              ),
            ],
          ),
          SizedBox(height: 20.h),
          // Quick preview expander
          InkWell(
            onTap: () {
              setState(() => _previewExpanded = !_previewExpanded);
              if (_previewExpanded) {
                Future.delayed(const Duration(milliseconds: 200), () {
                  _tabs.animateTo(1);
                });
              }
            },
            borderRadius: BorderRadius.circular(12.r),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  const Icon(Icons.preview_rounded, color: Colors.white70, size: 18),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Text(
                      loc.translate('preview_receipt_layout'),
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                ],
              ),
            ),
          ),
          SizedBox(height: 16.h),
          InvPrimaryButton(busy: _saving, onPressed: _save, label: loc.translate('save_settings')),
        ],
      );

  Widget _section({required IconData icon, required String title, required List<Widget> children}) =>
      Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: Colors.white12),
        ),
        padding: EdgeInsets.all(14.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white70, size: 16.sp),
                SizedBox(width: 8.w),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.sp,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            ...children,
          ],
        ),
      );

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    bool required = false,
  }) =>
      Padding(
        padding: EdgeInsets.only(bottom: 10.h),
        child: InvTextField(
          controller: c,
          label: label,
          hint: hint,
          validator: required
              ? (v) => (v == null || v.trim().isEmpty) ? LocalizationService.instance.translateWith('field_x_required', <Object?>[label]) : null
              : null,
        ),
      );

  Widget _fieldMultiline(TextEditingController c, String label, {String? hint}) =>
      Padding(
        padding: EdgeInsets.only(bottom: 10.h),
        child: InvTextField(
          controller: c,
          label: label,
          hint: hint,
          maxLines: 3,
        ),
      );

  Widget _toggle({required String label, required bool value, required ValueChanged<bool> onChanged}) =>
      Padding(
        padding: EdgeInsets.only(bottom: 6.h),
        child: Row(
          children: [
            Expanded(child: Text(label, style: ThemeConstants.bodyStyle.copyWith(fontSize: 12.sp))),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.white,
              activeTrackColor: ThemeConstants.primaryBlue.withOpacity(0.5),
              inactiveThumbColor: Colors.white38,
              inactiveTrackColor: Colors.white12,
            ),
          ],
        ),
      );

  // ── Preview tab ─────────────────────────────────────────────────────────────

  Widget _buildPreviewTab() => SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
        child: Column(
          children: [
            // Live-reload note
            Container(
              margin: EdgeInsets.only(bottom: 12.h),
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: Colors.amber.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 16),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      LocalizationService.instance.translate('this_layout_changes_automatically_when_you'),
                      style: TextStyle(color: Colors.amber, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            // Live receipt preview
            AnimatedBuilder(
              animation: Listenable.merge([
                _cName, _cTagline, _cAddress, _cPhone,
                _cEmail, _cWebsite, _cTin, _cFooter,
              ]),
              builder: (context, _) => _ReceiptPreview(
                shopName:    _cName.text.trim().isEmpty    ? LocalizationService.instance.translate('shop_name').toUpperCase() : _cName.text.trim(),
                tagline:     _cTagline.text.trim(),
                address:     _cAddress.text.trim(),
                phone:       _cPhone.text.trim(),
                email:       _cEmail.text.trim(),
                website:     _cWebsite.text.trim(),
                tin:         _cTin.text.trim(),
                footerNote:  _cFooter.text.trim(),
                showBarcode: _showBarcode,
                showTin:     _showTin,
              ),
            ),
          ],
        ),
      );
}

// ── Receipt preview widget ────────────────────────────────────────────────────

class _ReceiptPreview extends StatelessWidget {
  const _ReceiptPreview({
    required this.shopName,
    required this.tagline,
    required this.address,
    required this.phone,
    required this.email,
    required this.website,
    required this.tin,
    required this.footerNote,
    required this.showBarcode,
    required this.showTin,
  });

  final String shopName;
  final String tagline;
  final String address;
  final String phone;
  final String email;
  final String website;
  final String tin;
  final String footerNote;
  final bool showBarcode;
  final bool showTin;

  static const _stars = '* * * * * * * * * * * * * * * * * * *';
  static const _header = TextStyle(
    fontFamily: 'Courier',
    fontSize: 16,
    fontWeight: FontWeight.w900,
    letterSpacing: 1.5,
    color: Color(0xFF111111),
  );
  static const _sub = TextStyle(
    fontFamily: 'Courier',
    fontSize: 11,
    color: Color(0xFF555555),
    height: 1.5,
  );
  static const _starStyle = TextStyle(
    fontFamily: 'Courier',
    fontSize: 11,
    color: Color(0xFF999999),
  );
  static const _body = TextStyle(
    fontFamily: 'Courier',
    fontSize: 11,
    color: Color(0xFF222222),
    height: 1.6,
  );
  static const _bodyBold = TextStyle(
    fontFamily: 'Courier',
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: Color(0xFF111111),
    height: 1.6,
  );
  static const _sectionHead = TextStyle(
    fontFamily: 'Courier',
    fontSize: 12,
    fontWeight: FontWeight.w800,
    letterSpacing: 2.5,
    color: Color(0xFF111111),
  );

  // Strip literal "null" or blank
  static String _v(String s) => (s.trim() == 'null' || s.trim().isEmpty) ? '' : s.trim();

  @override
  Widget build(BuildContext context) {
    final name    = _v(shopName).isEmpty ? LocalizationService.instance.translate('shop_name').toUpperCase() : _v(shopName);
    final tag     = _v(tagline);
    final addr    = _v(address);
    final ph      = _v(phone);
    final em      = _v(email);
    final web     = _v(website);
    final tinVal  = showTin ? _v(tin) : '';
    final footer  = _v(footerNote);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(top: -8, left: 0, right: 0, child: _TornEdge(top: true)),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAF8),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.20), blurRadius: 18, offset: const Offset(0, 6)),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Logo + shop name side by side
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D0D0D),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Flexible(child: Text(name, style: _header, textAlign: TextAlign.left)),
                ],
              ),
              if (tag.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(tag, style: _sub.copyWith(fontStyle: FontStyle.italic), textAlign: TextAlign.center),
              ],
              // ── Phone left + TIN right
              if (ph.isNotEmpty || tinVal.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (ph.isNotEmpty)
                      Row(children: [
                        const Icon(Icons.phone_rounded, size: 11, color: Color(0xFF0D0D0D)),
                        const SizedBox(width: 3),
                        Text(ph, style: _sub.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF0D0D0D))),
                      ]),
                    const Spacer(),
                    if (tinVal.isNotEmpty)
                      Text('TIN: $tinVal', style: _sub.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF0D0D0D))),
                  ],
                ),
              ],
              // ── Remaining contact (address, email, website)
              if (addr.isNotEmpty || em.isNotEmpty || web.isNotEmpty) ...[
                const SizedBox(height: 2),
                for (final line in [
                  if (addr.isNotEmpty) addr,
                  if (em.isNotEmpty) em,
                  if (web.isNotEmpty) web,
                ])
                  Text(line, style: _sub, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 8),

              // ── Receipt title
              Row(children: [
                const Expanded(child: Divider(color: Color(0xFF0D0D0D), thickness: 1)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(LocalizationService.instance.translate('sale_receipt').toUpperCase(),
                      style: TextStyle(fontFamily: 'Courier', fontSize: 11,
                          fontWeight: FontWeight.w900, letterSpacing: 3, color: Color(0xFF0D0D0D))),
                ),
                const Expanded(child: Divider(color: Color(0xFF0D0D0D), thickness: 1)),
              ]),
              const SizedBox(height: 8),

              // ── Sample meta row
              _metaRow('🧾', LocalizationService.instance.translate('receipt_number_label'), 'S-20260903-0001', '📅', LocalizationService.instance.translate('date'), '03 Sep 2026'),
              const SizedBox(height: 4),
              _metaRow('⏰', LocalizationService.instance.translate('receipt_time'), '12:00', '💳', LocalizationService.instance.translate('payment_status_label'), LocalizationService.instance.translate('bill_paid')),
              const SizedBox(height: 8),

              // ── Items header
              Row(children: [
                Expanded(child: Text(LocalizationService.instance.translate('items_header'), style: _bodyBold.copyWith(fontSize: 10, letterSpacing: 1))),
                Text(LocalizationService.instance.translate('qty').toUpperCase(), style: _sub.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                SizedBox(width: 64, child: Text(LocalizationService.instance.translate('total').toUpperCase(), style: _sub.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.right)),
              ]),
              _dash(),
              _itemRow('Soda 300ml', '×12', '14,400'),
              _itemRow(LocalizationService.instance.translate('cold_water'), '×6',  '3,000'),
              _dash(),

              // ── Totals
              _tRow(LocalizationService.instance.translate('grand_total').toUpperCase(), 'TZS 16,900', bold: true),
              const SizedBox(height: 4),
              Row(children: [
                const Expanded(child: Divider(color: Color(0xFF0D0D0D), thickness: 1)),
                Padding(padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(LocalizationService.instance.translate('payments_section').toUpperCase(), style: TextStyle(fontFamily: 'Courier', fontSize: 10,
                        fontWeight: FontWeight.w900, letterSpacing: 3, color: Color(0xFF0D0D0D)))),
                const Expanded(child: Divider(color: Color(0xFF0D0D0D), thickness: 1)),
              ]),
              const SizedBox(height: 2),
              _tRow(LocalizationService.instance.translate('payment_method_label'), LocalizationService.instance.translate('method_cash')),
              _tRow(LocalizationService.instance.translate('paid_3'), 'TZS 20,000', bold: true),
              _tRow(LocalizationService.instance.translate('change'), 'TZS 3,100'),
              const SizedBox(height: 6),
              Text(LocalizationService.instance.translate('fully_paid').toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Courier', fontSize: 12,
                      fontWeight: FontWeight.w900, letterSpacing: 2, color: Color(0xFF1B5E20))),
              const SizedBox(height: 8),

              // ── Footer
              Text(_stars, style: _starStyle),
              const SizedBox(height: 4),
              Text(LocalizationService.instance.translate('thank_you_4').toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Courier', fontSize: 13,
                      fontWeight: FontWeight.w900, letterSpacing: 3, color: Color(0xFF0D0D0D))),
              const SizedBox(height: 3),
              Text(
                footer.isNotEmpty
                    ? footer
                    : (ApiService.activeService == 'salon'
                        ? LocalizationService.instance.translate('receipt_welcome_again')
                        : LocalizationService.instance.translate('sold_goods_cannot_be_returned_without')),
                style: _sub.copyWith(fontSize: 10, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(_stars, style: _starStyle),

              if (showBarcode) ...[
                const SizedBox(height: 8),
                _BarcodeStrip(),
                const SizedBox(height: 3),
                const Text('S-20260903-0001', style: TextStyle(fontFamily: 'Courier', fontSize: 9,
                    letterSpacing: 2, color: Color(0xFF333333))),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
        Positioned(bottom: -8, left: 0, right: 0, child: _TornEdge(top: false)),
      ],
    );
  }

  Widget _dash() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: CustomPaint(size: const Size(double.infinity, 1),
            painter: _DashPainter()),
      );

  Widget _itemRow(String name, String qty, String total) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(name, style: _body)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: const Color(0xFF0D0D0D), borderRadius: BorderRadius.circular(3)),
              child: Text(qty, style: const TextStyle(fontFamily: 'Courier', fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 64, child: Text('TZS $total', style: _body, textAlign: TextAlign.right)),
          ],
        ),
      );

  Widget _tRow(String label, String value, {bool bold = false}) {
    final ts = TextStyle(fontFamily: 'Courier', fontSize: 11,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
        color: const Color(0xFF1A1A1A), height: 1.2);
    return Row(children: [
      Expanded(child: Text(label, style: ts.copyWith(color: const Color(0xFF2A2A2A), fontWeight: FontWeight.w600))),
      Text(value, style: ts),
    ]);
  }

  Widget _metaRow(String li, String ll, String lv, String ri, String rl, String rv) =>
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$li  $ll', style: const TextStyle(fontFamily: 'Courier', fontSize: 9, color: Color(0xFF555555), fontWeight: FontWeight.w600)),
          Text(lv, style: const TextStyle(fontFamily: 'Courier', fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF0D0D0D))),
        ]),
        Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: CustomPaint(size: const Size(double.infinity, 1), painter: _DashPainter(color: const Color(0xFF999999))),
        )),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$rl  $ri', style: const TextStyle(fontFamily: 'Courier', fontSize: 9, color: Color(0xFF555555), fontWeight: FontWeight.w600)),
          Text(rv, style: const TextStyle(fontFamily: 'Courier', fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF0D0D0D))),
        ]),
      ]);
}

class _DashPainter extends CustomPainter {
  const _DashPainter({this.color = const Color(0xFFCCCCCC)});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 1;
    double x = 0;
    while (x < size.width) { canvas.drawLine(Offset(x, 0), Offset(x + 4, 0), p); x += 8; }
  }
  @override bool shouldRepaint(covariant CustomPainter _) => false;
}

/// Minimal barcode stand-in (same painter as the real receipt screen).
class _BarcodeStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final rng = math.Random(12345);
    final bars = List.generate(48, (i) => rng.nextDouble() > 0.5 ? 1.8 : 0.9);
    return SizedBox(
      height: 46,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: bars.asMap().entries.map((e) => Container(
              width: e.value,
              margin: const EdgeInsets.symmetric(horizontal: 0.4),
              color: e.key.isEven ? const Color(0xFF1A1A1A) : Colors.transparent,
            )).toList(),
      ),
    );
  }
}

// Torn paper edge (shared with sale_receipt_screen.dart, duplicated to avoid
// cross-import between two screen files).
class _TornEdge extends StatelessWidget {
  const _TornEdge({required this.top});
  final bool top;
  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(double.infinity, 16),
        painter: _TornEdgePainter(top: top),
      );
}

class _TornEdgePainter extends CustomPainter {
  const _TornEdgePainter({required this.top});
  final bool top;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFFAFAF8);
    final path = Path();
    final rng = math.Random(top ? 11 : 22);
    if (top) {
      path.moveTo(0, 16);
      double x = 0;
      while (x < size.width) {
        final w = 6 + rng.nextDouble() * 10;
        final h = 4 + rng.nextDouble() * 9;
        path.lineTo(x + w / 2, h);
        path.lineTo(x + w, 16);
        x += w;
      }
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      double x = size.width;
      while (x > 0) {
        final w = 6 + rng.nextDouble() * 10;
        final h = 4 + rng.nextDouble() * 9;
        path.lineTo(x - w / 2, size.height - h);
        path.lineTo(x - w, 0);
        x -= w;
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
