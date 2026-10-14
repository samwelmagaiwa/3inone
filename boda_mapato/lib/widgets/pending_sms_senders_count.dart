import 'package:flutter/material.dart';

import '../screens/admin/sms_senders_screen.dart';

/// How many sender names are waiting for the super admin to register and approve them, fetched when it appears and
/// again on [PendingSmsSendersCountState.refresh]. [builder] gets `null` while it is loading or when it could not be
/// found out (no connection): the badge then simply says nothing rather than something wrong.
class PendingSmsSendersCount extends StatefulWidget {
  const PendingSmsSendersCount({super.key, required this.builder, this.source});

  final Widget Function(BuildContext context, int? pending) builder;

  /// Where the number comes from. The app uses the server; tests supply a fake.
  final SmsSendersDataSource? source;

  @override
  State<PendingSmsSendersCount> createState() => PendingSmsSendersCountState();
}

class PendingSmsSendersCountState extends State<PendingSmsSendersCount> {
  int? _pending;
  late final SmsSendersDataSource _source = widget.source ?? ApiSmsSendersDataSource();

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final page = await _source.load(status: 'pending', perPage: 1);
      if (!mounted) return;
      setState(() => _pending = page.count('pending'));
    } on Exception {
      if (!mounted) return;
      setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _pending);
}
