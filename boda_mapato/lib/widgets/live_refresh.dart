import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// Keeps a screen's figures fresh without anyone pulling down: [onRefresh] runs by itself
///
///   - a moment after the server accepts a change anywhere in the app (a sale, an expense, a payment, an edit, a delete: see
///     [ApiService.changes]), so a total moves as soon as the data does;
///   - when the app comes back to the front;
///   - every [interval], for changes made by other people on other phones.
///
/// A screen that is not showing (another tab, or covered by a page on top) does not refresh; it notes that it is behind and
/// catches up the moment it is shown again. Refreshes never overlap, and [onRefresh] should read quietly (no spinner).
class LiveRefresh extends StatefulWidget {
  const LiveRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.interval = const Duration(seconds: 45),
    this.settle = const Duration(milliseconds: 700),
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// How often it reads again when nothing in this app changed.
  final Duration interval;

  /// How long it waits after a change, so a burst of changes is read once.
  final Duration settle;

  @override
  State<LiveRefresh> createState() => _LiveRefreshState();
}

class _LiveRefreshState extends State<LiveRefresh> with WidgetsBindingObserver {
  Timer? _timer;
  Timer? _settleTimer;
  bool _running = false;
  bool _behind = false;
  bool _showing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ApiService.changes.addListener(_changed);
    _timer = Timer.periodic(widget.interval, (_) => _refresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // An inactive tab (or a screen under another page) has its tickers switched off: that is how it is told apart.
    final bool wasShowing = _showing;
    _showing = TickerMode.of(context);
    if (_showing && !wasShowing && _behind) _refresh();
  }

  @override
  void didChangeAppLifecycleState(final AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _changed() {
    _settleTimer?.cancel();
    _settleTimer = Timer(widget.settle, _refresh);
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    if (!_showing) {
      _behind = true;
      return;
    }
    if (_running) return;
    _running = true;
    _behind = false;
    try {
      await widget.onRefresh();
    } on Object {
      // a failed quiet read leaves the figures as they are; the next one tries again
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _settleTimer?.cancel();
    ApiService.changes.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) => widget.child;
}
