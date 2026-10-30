import '../../../services/api_service.dart';

/// One record in the Trash (or, for the sales tab, one cancelled sale kept for the record).
class TrashItem {
  const TrashItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.canRestore,
    required this.canRemove,
    this.amount,
    this.deletedAt,
    this.deletedBy,
    this.reason,
  });

  factory TrashItem.fromJson(final Map<String, dynamic> j) => TrashItem(
        id: j['id'] is num ? (j['id'] as num).toInt() : int.tryParse('${j['id']}') ?? 0,
        type: '${j['type'] ?? ''}',
        title: '${j['title'] ?? ''}',
        subtitle: '${j['subtitle'] ?? ''}',
        amount: j['amount'] is num ? (j['amount'] as num).toDouble() : null,
        deletedAt: DateTime.tryParse('${j['deleted_at'] ?? ''}'),
        deletedBy: j['deleted_by_name'] == null || '${j['deleted_by_name']}'.isEmpty ? null : '${j['deleted_by_name']}',
        reason: j['reason'] == null || '${j['reason']}'.trim().isEmpty ? null : '${j['reason']}',
        canRestore: j['can_restore'] != false,
        canRemove: j['can_remove'] != false,
      );

  final int id;
  final String type;
  final String title;
  final String subtitle;
  final double? amount;
  final DateTime? deletedAt;
  final String? deletedBy;
  final String? reason;
  final bool canRestore;
  final bool canRemove;
}

/// One page of the Trash for one kind, with how many records of every kind are in it.
class TrashPage {
  const TrashPage({required this.items, required this.counts, required this.page, required this.lastPage, required this.total});

  factory TrashPage.fromJson(final Map<String, dynamic> j) {
    final Map<String, dynamic> meta = j['meta'] is Map ? Map<String, dynamic>.from(j['meta'] as Map) : <String, dynamic>{};
    final Map<String, dynamic> counts = j['counts'] is Map ? Map<String, dynamic>.from(j['counts'] as Map) : <String, dynamic>{};
    int n(final dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

    return TrashPage(
      items: <TrashItem>[
        if (j['data'] is List)
          for (final dynamic r in j['data'] as List<dynamic>)
            if (r is Map) TrashItem.fromJson(Map<String, dynamic>.from(r)),
      ],
      counts: <String, int>{for (final MapEntry<String, dynamic> e in counts.entries) e.key: n(e.value)},
      page: n(meta['current_page']) == 0 ? 1 : n(meta['current_page']),
      lastPage: n(meta['last_page']) == 0 ? 1 : n(meta['last_page']),
      total: n(meta['total']),
    );
  }

  final List<TrashItem> items;
  final Map<String, int> counts;
  final int page;
  final int lastPage;
  final int total;
}

/// The Trash: what the owner or an admin deleted (expenses, customers, debts from before the app, products and services), and the way to
/// bring it back or remove it for good. Screens take one of these so a test can hand them a fake.
class TrashApi {
  TrashApi({final ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  /// What the Trash holds: [type] is expenses, customers, debts, products or sales (the cancelled ones); null = only the counts.
  Future<TrashPage> list({final String? type, final int page = 1}) async {
    final List<String> q = <String>[if (type != null) 'type=$type', if (page > 1) 'page=$page'];

    return TrashPage.fromJson(await _api.get('/inventory/trash${q.isEmpty ? '' : '?${q.join('&')}'}'));
  }

  /// Bring a record back. A product whose SKU was taken meanwhile needs [sku], a new one.
  Future<void> restore(final String type, final int id, {final String? sku}) async {
    await _api.post('/inventory/trash/$type/$id/restore', <String, dynamic>{if (sku != null && sku.trim().isNotEmpty) 'sku': sku.trim()});
  }

  /// Remove a record for good (the server refuses when it has history to keep).
  Future<void> remove(final String type, final int id) async {
    await _api.delete('/inventory/trash/$type/$id?confirm=DELETE');
  }
}
