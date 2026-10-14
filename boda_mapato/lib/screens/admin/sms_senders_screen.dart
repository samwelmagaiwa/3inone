import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:intl/intl.dart";
import "package:share_plus/share_plus.dart";

import "../../constants/theme_constants.dart";
import "../../models/sms_sender.dart";
import "../../services/api_service.dart";
import "../../services/localization_service.dart";
import "../../utils/server_message.dart";
import "../../widgets/scrolling_chip_row.dart";

/// Where the screen gets and saves the sender names. The app uses [ApiSmsSendersDataSource]; tests supply a fake.
abstract class SmsSendersDataSource {
  Future<SmsSenderPage> load({String status = "all", String? query, int page = 1, int perPage = 50});

  Future<SmsSenderEntry> save(String businessId, SmsSenderEdit edit);

  Future<SmsSenderTestResult> test(String businessId, {String? phone, String? senderId, String? apiKey, String? apiSecret});
}

class ApiSmsSendersDataSource implements SmsSendersDataSource {
  ApiSmsSendersDataSource() {
    _api.initialize();
  }

  final ApiService _api = ApiService();

  @override
  Future<SmsSenderPage> load({final String status = "all", final String? query, final int page = 1, final int perPage = 50}) async {
    final Map<String, dynamic> res = await _api.getSmsSenders(status: status, query: query, page: page, perPage: perPage);
    final Object? data = res["data"];
    final Map<dynamic, dynamic> meta = res["meta"] is Map ? res["meta"] as Map : <dynamic, dynamic>{};
    final Map<dynamic, dynamic> counts = meta["counts"] is Map ? meta["counts"] as Map : <dynamic, dynamic>{};
    final Map<dynamic, dynamic> paging = meta["pagination"] is Map ? meta["pagination"] as Map : <dynamic, dynamic>{};
    return SmsSenderPage(
      items: data is List
          ? data.whereType<Map>().map((final Map m) => SmsSenderEntry.fromJson(Map<String, dynamic>.from(m))).toList()
          : <SmsSenderEntry>[],
      counts: <String, int>{for (final MapEntry<dynamic, dynamic> e in counts.entries) e.key.toString(): (e.value as num?)?.toInt() ?? 0},
      platformSender: (meta["platform_sender"] ?? "").toString(),
      smsDelivering: meta["sms_delivering"] != false,
      page: (paging["current_page"] as num?)?.toInt() ?? page,
      hasMore: paging["has_more_pages"] == true,
    );
  }

  @override
  Future<SmsSenderEntry> save(final String businessId, final SmsSenderEdit edit) async {
    final Map<String, dynamic> res = await _api.saveSmsSender(businessId, edit.toJson());
    return SmsSenderEntry.fromJson(Map<String, dynamic>.from(res["data"] as Map));
  }

  @override
  Future<SmsSenderTestResult> test(final String businessId, {final String? phone, final String? senderId, final String? apiKey, final String? apiSecret}) async {
    final Map<String, dynamic> res = await _api.testSmsSender(businessId, phone: phone, senderId: senderId, apiKey: apiKey, apiSecret: apiSecret);
    return SmsSenderTestResult.fromJson(Map<String, dynamic>.from(res["data"] as Map));
  }
}

Color _statusColor(final SmsSenderInfo s) {
  if (s.needsAttention) return Colors.orangeAccent;
  return switch (s.status) {
    "approved" => Colors.greenAccent,
    "pending" => Colors.amberAccent,
    "rejected" => Colors.redAccent,
    _ => Colors.white54,
  };
}

String _statusLabel(final SmsSenderInfo s, final bool sw) {
  if (s.needsAttention) return sw ? "Inahitaji kuangaliwa" : "Needs attention";
  return switch (s.status) {
    "approved" => sw ? "Imeidhinishwa" : "Approved",
    "pending" => sw ? "Inasubiri" : "Waiting",
    "rejected" => sw ? "Imekataliwa" : "Rejected",
    _ => sw ? "Haijawekwa" : "Not set",
  };
}

/// Super admin: which registered sender name each business's texts go out under, and the page where a name (and,
/// if the business has an account of its own with the SMS provider, its API key) is entered once the provider
/// has approved it. Nothing needs changing in the code or on the server for a new business.
class SmsSendersScreen extends StatefulWidget {
  const SmsSendersScreen({super.key, this.dataSource, this.onShare});

  final SmsSendersDataSource? dataSource;

  /// How the list of names to register is shared. The app opens the share sheet; tests supply a fake.
  final Future<void> Function(String text)? onShare;

  @override
  State<SmsSendersScreen> createState() => _SmsSendersScreenState();
}

class _SmsSendersScreenState extends State<SmsSendersScreen> {
  late final SmsSendersDataSource _source = widget.dataSource ?? ApiSmsSendersDataSource();
  final TextEditingController _search = TextEditingController();

  String _status = "all";
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<SmsSenderEntry> _items = <SmsSenderEntry>[];
  SmsSenderPage _meta = const SmsSenderPage(items: <SmsSenderEntry>[]);

  bool get _sw => LocalizationService.instance.isSwahili;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({final bool spinner = true}) async {
    if (spinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final SmsSenderPage page = await _source.load(status: _status, query: _search.text);
      if (!mounted) return;
      setState(() {
        _items = List<SmsSenderEntry>.of(page.items);
        _meta = page;
        _loading = false;
        _error = null;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = readableErrorMessage(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_meta.hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final SmsSenderPage page = await _source.load(status: _status, query: _search.text, page: _meta.page + 1);
      if (!mounted) return;
      setState(() {
        _items = <SmsSenderEntry>[..._items, ...page.items];
        _meta = page;
        _loadingMore = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = readableErrorMessage(e);
      });
    }
  }

  Future<void> _open(final SmsSenderEntry entry) async {
    final SmsSenderEntry? saved = await showModalBottomSheet<SmsSenderEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (final BuildContext sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: _SenderSheet(entry: entry, source: _source, sw: _sw, platformSender: _meta.platformSender),
      ),
    );
    if (saved != null && mounted) await _load(spinner: false);
  }

  /// The names that are waiting, as lines to take to the provider (name, business, TIN, owner).
  Future<void> _sharePending() async {
    try {
      final SmsSenderPage waiting = await _source.load(status: "pending", perPage: 100);
      final String text = smsSenderRegistrationList(waiting.items);
      if (!mounted) return;
      if (text.isEmpty) {
        ThemeConstants.showWarningSnackBar(context, _sw ? "Hakuna jina linalosubiri kusajiliwa." : "No name is waiting to be registered.");
        return;
      }
      await (widget.onShare ?? (final String t) async => Share.share(t, subject: "SMS sender IDs"))(text);
    } on Exception catch (e) {
      if (!mounted) return;
      ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final int waiting = _meta.count("pending");
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(
        _sw ? "Majina ya SMS (Sender ID)" : "SMS Sender Names",
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>("share_pending"),
            tooltip: _sw ? "Shiriki orodha ya kusajili" : "Share the list to register",
            onPressed: waiting > 0 ? _sharePending : null,
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                key: const ValueKey<String>("senders_search"),
                controller: _search,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.search,
                onSubmitted: (final String _) => _load(),
                decoration: InputDecoration(
                  hintText: _sw ? "Tafuta biashara, mmiliki, TIN au jina" : "Search business, owner, TIN or name",
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ),
            ScrollingChipRow(
              children: <Widget>[
                _chip("all", _sw ? "Zote" : "All", _meta.count("total")),
                _chip("pending", _sw ? "Zinasubiri" : "Waiting", _meta.count("pending")),
                _chip("attention", _sw ? "Zinahitaji kuangaliwa" : "Needs attention", _meta.count("attention")),
                _chip("approved", _sw ? "Zimeidhinishwa" : "Approved", _meta.count("approved")),
                _chip("rejected", _sw ? "Zimekataliwa" : "Rejected", _meta.count("rejected")),
                _chip("none", _sw ? "Hazijawekwa" : "Not set", _meta.count("none")),
              ],
            ),
            _notice(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _chip(final String status, final String label, final int count) => ScrollChoiceChip(
        key: ValueKey<String>("filter_$status"),
        label: "$label ($count)",
        selected: _status == status,
        onSelected: (final bool _) {
          if (_status == status) return;
          setState(() => _status = status);
          _load();
        },
      );

  /// What the businesses fall back to, and a warning when no real SMS provider is on.
  Widget _notice() {
    final String platform = _meta.platformSender;
    final List<Widget> lines = <Widget>[
      if (platform.isNotEmpty)
        Text(
          _sw
              ? "Biashara isiyo na jina lake hutuma kwa jina la jukwaa: $platform."
              : "A business with no name of its own sends under the platform name: $platform.",
          key: const ValueKey<String>("platform_sender_note"),
          style: const TextStyle(color: Colors.white60, fontSize: 12.5),
        ),
      if (!_meta.smsDelivering)
        Padding(
          padding: EdgeInsets.only(top: platform.isNotEmpty ? 6 : 0),
          child: Text(
            _sw
                ? "SMS imezimwa kwenye seva: ujumbe unaandikwa kwenye log tu, haupelekwi kwa simu."
                : "SMS is switched off on the server: texts are only written to a log, not sent to phones.",
            key: const ValueKey<String>("not_delivering_note"),
            style: const TextStyle(color: Colors.orangeAccent, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Align(alignment: Alignment.centerLeft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines)),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) {
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
    if (_items.isEmpty) {
      return Center(
        child: Text(
          _sw ? "Hakuna biashara hapa." : "No businesses here.",
          key: const ValueKey<String>("senders_empty"),
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _items.length + (_meta.hasMore ? 1 : 0),
        separatorBuilder: (final BuildContext _, final int __) => const SizedBox(height: 10),
        itemBuilder: (final BuildContext _, final int i) {
          if (i >= _items.length) {
            return Center(
              child: _loadingMore
                  ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())
                  : OutlinedButton(key: const ValueKey<String>("load_more"), onPressed: _loadMore, child: Text(_sw ? "Pakia zaidi" : "Load more")),
            );
          }
          return _card(_items[i]);
        },
      ),
    );
  }

  Widget _card(final SmsSenderEntry e) {
    final SmsSenderInfo s = e.sender;
    final Color tone = _statusColor(s);
    final String last = s.lastSentAt == null ? "" : DateFormat("dd MMM").format(s.lastSentAt!);

    return ThemeConstants.buildGlassCard(
      onTap: () => _open(e),
      child: Padding(
        key: ValueKey<String>("sender_${e.id}"),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tone.withValues(alpha: 0.5)),
                  ),
                  child: Text(_statusLabel(s, _sw), style: TextStyle(color: tone, fontSize: 12)),
                ),
              ],
            ),
            if (e.ownerName.isNotEmpty || e.ownerPhone.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                <String>[e.ownerName, e.ownerPhone].where((final String t) => t.isNotEmpty).join("  ·  "),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: ThemeConstants.textSecondary, fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
            if (s.hasSender)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(
                    s.senderId!.toUpperCase(),
                    key: ValueKey<String>("sender_name_${e.id}"),
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                  ),
                  if ((s.displayName ?? "").isNotEmpty) Text("“${s.displayName}”", style: const TextStyle(color: Colors.white60, fontSize: 13)),
                  if (s.hasApiKey)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(8)),
                      child: Text(_sw ? "akaunti yake" : "own account", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ),
                ],
              )
            else
              Text(_sw ? "Bado hana jina la SMS - gusa kuliweka" : "No SMS name yet - tap to set one", style: const TextStyle(color: Colors.white38, fontSize: 13)),
            if (s.sentCount > 0) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                _sw
                    ? "Zimetumwa: ${s.sentCount} · kwa jina lake: ${s.ownCount}${last.isEmpty ? "" : " · mwisho $last"}"
                    : "Sent: ${s.sentCount} · under its own name: ${s.ownCount}${last.isEmpty ? "" : " · last $last"}",
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            if (s.needsAttention && (s.lastError ?? "").isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(readableServerMessage(s.lastError!), key: ValueKey<String>("sender_error_${e.id}"), style: const TextStyle(color: Colors.orangeAccent, fontSize: 12))),
                ],
              ),
            ],
            if (s.isRejected && (s.note ?? "").isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(s.note!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

/// One business's sender name: set it, try it with a real text, approve it. Pops with the saved entry.
class _SenderSheet extends StatefulWidget {
  const _SenderSheet({required this.entry, required this.source, required this.sw, required this.platformSender});

  final SmsSenderEntry entry;
  final SmsSendersDataSource source;
  final bool sw;
  final String platformSender;

  @override
  State<_SenderSheet> createState() => _SenderSheetState();
}

class _SenderSheetState extends State<_SenderSheet> {
  static final RegExp _valid = RegExp(r"^[A-Za-z][A-Za-z0-9]{2,10}$");

  late final TextEditingController _senderId = TextEditingController(text: widget.entry.sender.senderId ?? "");
  late final TextEditingController _displayName = TextEditingController(text: widget.entry.sender.displayName ?? "");
  final TextEditingController _apiKey = TextEditingController();
  final TextEditingController _apiSecret = TextEditingController();
  late final TextEditingController _note = TextEditingController(text: widget.entry.sender.isRejected ? (widget.entry.sender.note ?? "") : "");
  final TextEditingController _testPhone = TextEditingController();

  /// A name that is entered here has usually just been approved by the provider, so "approved" is the starting point.
  late String _status = widget.entry.sender.status == "none" ? "approved" : widget.entry.sender.status;
  late bool _fallback = widget.entry.sender.hasApiKey ? widget.entry.sender.fallbackPlatform : false;
  bool _fallbackTouched = false;
  bool _showSecrets = false;
  bool _busy = false;
  bool _testing = false;
  bool _copied = false;
  String? _error;
  SmsSenderTestResult? _testResult;

  bool get _sw => widget.sw;
  SmsSenderInfo get _info => widget.entry.sender;
  bool get _usesOwnAccount => _info.hasApiKey || _apiKey.text.trim().isNotEmpty;

  @override
  void dispose() {
    _senderId.dispose();
    _displayName.dispose();
    _apiKey.dispose();
    _apiSecret.dispose();
    _note.dispose();
    _testPhone.dispose();
    super.dispose();
  }

  SmsSenderEdit _edit({final bool clearCredentials = false}) => SmsSenderEdit(
        senderId: _senderId.text,
        displayName: _displayName.text,
        status: _status,
        note: _status == "rejected" ? _note.text : "",
        apiKey: clearCredentials ? "" : _apiKey.text,
        apiSecret: clearCredentials ? "" : _apiSecret.text,
        clearCredentials: clearCredentials,
        // Only said when there is an account of its own and the switch was touched; otherwise the server decides.
        fallbackPlatform: (_usesOwnAccount && _fallbackTouched && !clearCredentials) ? _fallback : null,
      );

  String? _problem() {
    final String name = _senderId.text.trim();
    if (name.isNotEmpty && !_valid.hasMatch(name)) {
      return _sw
          ? "Jina la mtumaji liwe na herufi 3 hadi 11 (herufi na tarakimu tu), likianza na herufi."
          : "The sender name must be 3 to 11 letters or digits and start with a letter.";
    }
    if (name.isEmpty && _apiKey.text.trim().isNotEmpty) {
      return _sw ? "Weka jina la mtumaji pamoja na API key." : "Enter the sender name together with the API key.";
    }
    if (_apiSecret.text.trim().isNotEmpty && _apiKey.text.trim().isEmpty && !_info.hasApiKey) {
      return _sw ? "Weka API key pamoja na secret." : "Enter the API key together with the secret.";
    }
    return null;
  }

  Future<void> _save({final bool clearCredentials = false}) async {
    final String? problem = _problem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final SmsSenderEntry saved = await widget.source.save(widget.entry.id, _edit(clearCredentials: clearCredentials));
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = readableErrorMessage(e);
      });
    }
  }

  Future<void> _removeKey() async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (final BuildContext c) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        title: Text(_sw ? "Ondoa API key?" : "Remove the API key?", style: const TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(
          _sw
              ? "Biashara hii itarudi kutumia akaunti ya jukwaa. Jina la mtumaji linabaki."
              : "This business goes back to the platform's account. The sender name stays.",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: Text(_sw ? "Ghairi" : "Cancel")),
          FilledButton(key: const ValueKey<String>("confirm_remove_key"), onPressed: () => Navigator.of(c).pop(true), child: Text(_sw ? "Ondoa" : "Remove")),
        ],
      ),
    );
    if (yes == true) await _save(clearCredentials: true);
  }

  Future<void> _test() async {
    final String name = _senderId.text.trim();
    if (!_valid.hasMatch(name)) {
      setState(() => _error = _problem() ?? (_sw ? "Weka jina la mtumaji kwanza." : "Enter the sender name first."));
      return;
    }
    setState(() {
      _testing = true;
      _error = null;
      _testResult = null;
    });
    try {
      final SmsSenderTestResult result = await widget.source.test(
        widget.entry.id,
        phone: _testPhone.text,
        senderId: name,
        apiKey: _apiKey.text,
        apiSecret: _apiSecret.text,
      );
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testResult = result;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _error = readableErrorMessage(e);
      });
    }
  }

  String _testMessage(final SmsSenderTestResult r) {
    final String phone = _testPhone.text.trim();
    final String where = phone.isEmpty ? (_sw ? "kwenye simu yako" : "on your own phone") : phone;
    return switch (r.outcome) {
      "accepted" => _sw
          ? "Kilakona imekubali. Angalia $where: ujumbe unapaswa kuonyesha ${r.senderId.toUpperCase()} kama mtumaji."
          : "Kilakona accepted it. Check $where: the text should show ${r.senderId.toUpperCase()} as the sender.",
      "refused" => _sw
          ? "Kilakona imekataa jina hili au API key. Hakikisha jina limesajiliwa na kuidhinishwa na key ni sahihi."
          : "Kilakona refused this name or API key. Make sure the name is registered and approved and the key is right.",
      "not_delivering" => _sw
          ? "SMS imezimwa kwenye seva (inaandikwa kwenye log tu), kwa hiyo jaribio halikutumwa."
          : "SMS is switched off on the server (only written to a log), so the test was not sent.",
      _ => _sw
          ? "Hakuna jibu kutoka Kilakona. Ujumbe unaweza kuwa umetumwa; angalia simu, au jaribu tena."
          : "No answer from Kilakona. The text may still arrive; check the phone, or try again.",
    };
  }

  Future<void> _copyDetails() async {
    final SmsSenderEntry e = widget.entry;
    await Clipboard.setData(ClipboardData(
      text: <String>[
        _senderId.text.trim().toUpperCase(),
        e.name,
        e.tin.isEmpty ? "-" : e.tin,
        e.ownerName.isEmpty ? "-" : e.ownerName,
        e.ownerPhone.isEmpty ? "-" : e.ownerPhone,
      ].join(" | "),
    ));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  InputDecoration _decoration(final String label, {final String? hint, final Widget? suffix, final String? helper}) => InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 3,
        suffixIcon: suffix,
        labelStyle: const TextStyle(color: Colors.white60),
        hintStyle: const TextStyle(color: Colors.white30),
        helperStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );

  @override
  Widget build(final BuildContext context) {
    final SmsSenderEntry e = widget.entry;
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.94;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      // A Material, not a DecoratedBox: the switch below is a ListTile and paints its ink on the nearest Material.
      child: Material(
        color: ThemeConstants.primaryBlue,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text(e.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                <String>[
                  if (e.ownerName.isNotEmpty) e.ownerName,
                  if (e.ownerPhone.isNotEmpty) e.ownerPhone,
                  if (e.tin.isNotEmpty) "TIN ${e.tin}",
                ].join("  ·  "),
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              if (_info.isPending && _info.hasSender) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _sw
                      ? "Mteja ameomba jina hili. Lisajili kwenye Kilakona, kisha liweke hapa na ubonyeze Hifadhi."
                      : "The customer asked for this name. Register it with Kilakona, then enter it here and press Save.",
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
                ),
              ],
              if (_info.needsAttention && (_info.lastError ?? "").isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(readableServerMessage(_info.lastError!), key: const ValueKey<String>("sheet_attention"), style: const TextStyle(color: Colors.orangeAccent, fontSize: 13)),
              ],
              const SizedBox(height: 18),
              TextField(
                key: const ValueKey<String>("sender_id_field"),
                controller: _senderId,
                enabled: !_busy,
                maxLength: 11,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z0-9]"))],
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1.2),
                onChanged: (final String _) => setState(() {}),
                decoration: _decoration(_sw ? "Sender ID (jina linaloonekana kwa mteja)" : "Sender ID (what the customer's phone shows)"),
              ),
              const SizedBox(height: 4),
              TextField(
                key: const ValueKey<String>("display_name_field"),
                controller: _displayName,
                enabled: !_busy,
                maxLength: 40,
                style: const TextStyle(color: Colors.white),
                decoration: _decoration(
                  _sw ? "Jina ndani ya ujumbe (si lazima)" : "Name inside the text (optional)",
                  hint: e.name,
                  helper: _sw ? "Likiachwa wazi, jina la biashara linatumika." : "Left empty, the business name is used.",
                ),
              ),
              const SizedBox(height: 12),
              Text(_sw ? "Hali" : "Status", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String st in <String>["approved", "pending", "rejected"])
                    ChoiceChip(
                      key: ValueKey<String>("status_$st"),
                      label: Text(switch (st) {
                        "approved" => _sw ? "Imeidhinishwa" : "Approved",
                        "pending" => _sw ? "Inasubiri" : "Waiting",
                        _ => _sw ? "Imekataliwa" : "Rejected",
                      }),
                      selected: _status == st,
                      onSelected: _busy ? null : (final bool _) => setState(() => _status = st),
                    ),
                ],
              ),
              if (_status == "approved")
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _sw
                        ? "Ujumbe wote wa biashara hii kwa wateja wake utatumia jina hili mara moja."
                        : "All of this business's texts to its customers use this name straight away.",
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 12.5),
                  ),
                ),
              if (_status == "rejected") ...<Widget>[
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey<String>("note_field"),
                  controller: _note,
                  enabled: !_busy,
                  maxLength: 255,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration(_sw ? "Sababu (mteja ataiona kwenye ujumbe)" : "Reason (the customer is told in a text)"),
                ),
              ],
              const Divider(color: Colors.white24, height: 28),
              Text(_sw ? "Akaunti ya SMS ya biashara hii" : "This business's SMS account", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                _sw
                    ? "Weka API key ya biashara hii kama ina akaunti yake ya Kilakona. Ikiachwa wazi, ujumbe unatoka kwenye akaunti ya jukwaa."
                    : "Enter this business's API key if it has its own Kilakona account. Left empty, its texts go out through the platform's account.",
                style: const TextStyle(color: Colors.white60, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey<String>("api_key_field"),
                controller: _apiKey,
                enabled: !_busy,
                obscureText: !_showSecrets,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(color: Colors.white),
                onChanged: (final String _) => setState(() {}),
                decoration: _decoration(
                  "API key",
                  hint: _info.hasApiKey ? (_sw ? "Imehifadhiwa (${_info.apiKeyHint ?? "****"}) - andika mpya kubadilisha" : "Saved (${_info.apiKeyHint ?? "****"}) - type a new one to replace it") : null,
                  suffix: IconButton(
                    key: const ValueKey<String>("toggle_secrets"),
                    icon: Icon(_showSecrets ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white54),
                    onPressed: () => setState(() => _showSecrets = !_showSecrets),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey<String>("api_secret_field"),
                controller: _apiSecret,
                enabled: !_busy,
                obscureText: !_showSecrets,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(color: Colors.white),
                decoration: _decoration(
                  "API secret",
                  hint: _info.hasApiSecret ? (_sw ? "Imehifadhiwa" : "Saved") : null,
                  helper: _sw ? "Si lazima. Ikiachwa wazi, secret ya jukwaa inatumika." : "Optional. Left empty, the platform's secret is used.",
                ),
              ),
              if (_usesOwnAccount) ...<Widget>[
                const SizedBox(height: 6),
                SwitchListTile(
                  key: const ValueKey<String>("fallback_switch"),
                  contentPadding: EdgeInsets.zero,
                  value: _fallback,
                  onChanged: _busy
                      ? null
                      : (final bool v) => setState(() {
                            _fallback = v;
                            _fallbackTouched = true;
                          }),
                  title: Text(
                    _sw ? "Akaunti yake ikishindikana, tumia ya jukwaa" : "If its account fails, use the platform's",
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  subtitle: Text(
                    _fallback
                        ? (_sw ? "Ujumbe utafika, lakini utatumia salio la jukwaa lako." : "The text still arrives, but it uses your platform credit.")
                        : (_sw ? "Ujumbe hautatumwa (hautumii salio lako); utaona onyo hapa." : "The text is not sent (your credit is not used); you will see a warning here."),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
              if (_info.hasApiKey)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey<String>("remove_key"),
                    onPressed: _busy ? null : _removeKey,
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                    label: Text(_sw ? "Ondoa API key" : "Remove API key", style: const TextStyle(color: Colors.redAccent)),
                  ),
                ),
              const Divider(color: Colors.white24, height: 28),
              Text(_sw ? "Jaribu kabla ya kuhifadhi" : "Try it before saving", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>("test_phone"),
                      controller: _testPhone,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(color: Colors.white),
                      decoration: _decoration(_sw ? "Namba ya simu" : "Phone number", hint: _sw ? "Acha wazi = simu yako" : "Empty = your own phone"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: OutlinedButton.icon(
                      key: const ValueKey<String>("send_test"),
                      onPressed: (_testing || _busy) ? null : _test,
                      icon: _testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_outlined, size: 18),
                      label: Text(_sw ? "Tuma jaribio" : "Send test"),
                    ),
                  ),
                ],
              ),
              if (_testResult != null)
                Container(
                  key: const ValueKey<String>("test_result"),
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_testResult!.accepted ? Colors.greenAccent : Colors.orangeAccent).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: (_testResult!.accepted ? Colors.greenAccent : Colors.orangeAccent).withValues(alpha: 0.5)),
                  ),
                  child: Text(_testMessage(_testResult!), style: const TextStyle(color: Colors.white, fontSize: 13)),
                ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(_error!, key: const ValueKey<String>("sender_error"), style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey<String>("save_sender"),
                      onPressed: _busy ? null : _save,
                      child: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_sw ? "Hifadhi" : "Save"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    key: const ValueKey<String>("copy_details"),
                    onPressed: _senderId.text.trim().isEmpty ? null : _copyDetails,
                    icon: Icon(_copied ? Icons.check : Icons.copy_outlined, size: 18),
                    label: Text(_copied ? (_sw ? "Imenakiliwa" : "Copied") : (_sw ? "Nakili kwa Kilakona" : "Copy for Kilakona")),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
