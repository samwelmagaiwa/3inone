import '../modules/inventory/models/salon_models.dart';
import '../modules/inventory/services/salon_api.dart';
import 'api_service.dart';

/// The branches of a Transport or Rental business (yards, offices): the same three calls the shop and salon use, on the
/// service's own address. It looks like a [SalonApi] so the one branches screen serves every service.
class ServiceBranchApi extends SalonApi {
  ServiceBranchApi(this.service, {final ApiService? api})
      : _client = api ?? ApiService(),
        super(api: api);

  /// 'transport' or 'rental'.
  final String service;
  final ApiService _client;

  String get _path => service == 'transport' ? '/admin/branches' : '/rental/branches';

  @override
  Future<List<SalonBranchInfo>> branches() async {
    final Map<String, dynamic> res = await _client.get(_path);
    final dynamic rows = res['data'];
    return <SalonBranchInfo>[
      if (rows is List)
        for (final dynamic r in rows)
          if (r is Map) SalonBranchInfo.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  @override
  Future<void> saveBranch({final int? id, required final String name, final String? address, final String? phone, final bool? active}) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'name': name,
      if (address != null) 'address': address,
      if (phone != null) 'phone': phone,
      if (active != null) 'active': active,
    };
    if (id == null) {
      await _client.post(_path, body);
    } else {
      await _client.put('$_path/$id', body);
    }
  }

  @override
  Future<void> deleteBranch(final int id) async {
    await _client.delete('$_path/$id');
  }
}
