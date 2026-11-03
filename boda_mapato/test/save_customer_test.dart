import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A customer is saved once: typing a name or a number that is already saved gives back the customer who is there, and says so.
class _Api extends ApiService {
  _Api(this.answer, {this.fail = false});

  final Map<String, dynamic> answer;
  final bool fail;
  final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async => <String, dynamic>{'data': <dynamic>[]};

  @override
  Future<Map<String, dynamic>> get(String endpoint, {bool requireAuth = true, Map<String, dynamic>? queryParams}) async => <String, dynamic>{'data': <dynamic>[]};

  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> data, {bool requireAuth = true}) async {
    sent.add(data);
    if (fail) throw ApiException('offline');
    return answer;
  }
}

void main() {
  test('a new customer is saved and not reported as already there', () async {
    final InventoryProvider inv = InventoryProvider(api: _Api(<String, dynamic>{'message': 'Customer created', 'data': <String, dynamic>{'id': 7}}));

    final saved = await inv.saveCustomer(name: 'Asha', phone: '0711000111');

    expect(saved.id, 7);
    expect(saved.existed, isFalse);
  });

  test('a customer who is already saved comes back as that customer, with the name they are saved under', () async {
    final InventoryProvider inv = InventoryProvider(
      api: _Api(<String, dynamic>{
        'message': 'Mteja huyu tayari yupo. / This customer already exists.',
        'data': <String, dynamic>{'id': 5, 'existing': true, 'matched_by': 'name', 'name': 'Mama Chale', 'phone': '0711000777'},
      }),
    );

    final saved = await inv.saveCustomer(name: 'mama chale', phone: '0722000888');

    expect(saved.id, 5);
    expect(saved.existed, isTrue);
    expect(saved.name, 'Mama Chale');
    expect(await inv.createCustomer(name: 'mama chale', phone: '0722000888'), 5, reason: 'the older call still returns the id');
  });

  test('a failed save returns no customer', () async {
    final InventoryProvider inv = InventoryProvider(api: _Api(<String, dynamic>{}, fail: true));

    final saved = await inv.saveCustomer(name: 'Asha', phone: '0711000111');

    expect(saved.id, isNull);
    expect(saved.existed, isFalse);
  });
}
