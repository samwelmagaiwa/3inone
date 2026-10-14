import 'package:flutter/material.dart';

import '../screens/admin/registrations_screen.dart';

/// How many business registrations are waiting for the super admin, fetched when it appears and again on
/// [PendingRegistrationsCountState.refresh]. [builder] gets `null` while it is loading or when it could not be
/// found out (no connection): the badge or card then simply says nothing rather than something wrong.
class PendingRegistrationsCount extends StatefulWidget {
  const PendingRegistrationsCount({super.key, required this.builder, this.source});

  final Widget Function(BuildContext context, int? pending) builder;

  /// Where the number comes from. The app uses the server; tests supply a fake.
  final RegistrationsDataSource? source;

  @override
  State<PendingRegistrationsCount> createState() => PendingRegistrationsCountState();
}

class PendingRegistrationsCountState extends State<PendingRegistrationsCount> {
  int? _pending;
  late final RegistrationsDataSource _source = widget.source ?? ApiRegistrationsDataSource();

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final RegistrationsPage page = await _source.load('pending');
      if (!mounted) return;
      setState(() => _pending = page.counts['pending'] ?? page.items.length);
    } on Exception {
      if (!mounted) return;
      setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _pending);
}

/// The small round number shown next to something that needs the super admin's attention. Nothing when zero.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    final int n = count ?? 0;
    if (n <= 0) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const ValueKey<String>('count_badge'),
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(11)),
      child: Text(
        n > 99 ? '99+' : '$n',
        style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}
