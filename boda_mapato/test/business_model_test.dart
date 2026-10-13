import 'package:boda_mapato/models/business.dart';
import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/widgets/subscription_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({Map<String, dynamic>? billing}) => <String, dynamic>{
      'id': 'b-1',
      'owner_id': 'u-1',
      'name': 'Mama Duka',
      'address': 'Sinza, Dar',
      'tin': '123-456-789',
      'phone': '0712345678',
      'email': 'duka@example.test',
      'logo_url': 'https://example.test/api/files/public/business_logos/a.png',
      'billing': billing ??
          <String, dynamic>{
            'plan': 'trial',
            'valid_until': '2026-11-14T23:59:59+00:00',
            'days_left': 30,
            'is_expired': false,
            'in_grace': false,
            'enforced': false,
            'blocked': false,
          },
    };

void main() {
  group('Business', () {
    test('reads the profile and the billing the server sends', () {
      final Business b = Business.fromJson(_json());

      expect(b.name, 'Mama Duka');
      expect(b.address, 'Sinza, Dar');
      expect(b.tin, '123-456-789');
      expect(b.phone, '0712345678');
      expect(b.email, 'duka@example.test');
      expect(b.logoUrl, endsWith('business_logos/a.png'));
      expect(b.billing.plan, 'trial');
      expect(b.billing.daysLeft, 30);
      expect(b.billing.validUntil, isNotNull);
      expect(b.billing.neverExpires, isFalse);
    });

    test('missing pieces read as empty, never as null text', () {
      final Business b = Business.fromJson(<String, dynamic>{'id': 'b-2', 'name': 'Bare'});

      expect(b.address, '');
      expect(b.tin, '');
      expect(b.logoUrl, isNull);
      expect(b.billing.plan, 'free');
      expect(b.billing.validUntil, isNull);
      expect(b.billing.neverExpires, isTrue);
      expect(b.services, isEmpty);
    });

    test('an empty logo address means no logo', () {
      expect(Business.fromJson(<String, dynamic>{'id': 'b', 'name': 'x', 'logo_url': ''}).logoUrl, isNull);
    });

    test('the super admin\'s extras are read when present', () {
      final Business b = Business.fromJson(<String, dynamic>{
        ..._json(),
        'owner': <String, dynamic>{'id': 'u-1', 'name': 'Asha', 'email': 'a@x.test', 'phone_number': '0711', 'is_active': false},
        'services': <String>['inventory', 'rental'],
        'staff_count': 4,
      });

      expect(b.owner!.name, 'Asha');
      expect(b.owner!.isActive, isFalse);
      expect(b.services, <String>['inventory', 'rental']);
      expect(b.staffCount, 4);
    });
  });

  group('needsAttention', () {
    BusinessBilling billing({int? days, bool expired = false}) => BusinessBilling(
          plan: 'basic',
          validUntil: days == null ? null : DateTime.now().add(Duration(days: days)),
          daysLeft: days,
          isExpired: expired,
        );

    test('a business that never expires never needs attention', () {
      expect(billing().needsAttention(), isFalse);
    });

    test('a week or less to go, or already over, does', () {
      expect(billing(days: 30).needsAttention(), isFalse);
      expect(billing(days: 8).needsAttention(), isFalse);
      expect(billing(days: 7).needsAttention(), isTrue);
      expect(billing(days: 0).needsAttention(), isTrue);
      expect(billing(days: -2, expired: true).needsAttention(), isTrue);
    });
  });

  test('plans have readable names in both languages and unknown ones show as they are', () {
    expect(businessPlanLabel('trial', sw: true), 'Jaribio');
    expect(businessPlanLabel('trial', sw: false), 'Trial');
    expect(businessPlanLabel('free', sw: true), 'Bure');
    expect(businessPlanLabel('premium', sw: false), 'Premium');
    expect(businessPlanLabel('platinum', sw: true), 'platinum');
  });

  group('UserData', () {
    Map<String, dynamic> user(String role, {Object? business}) => <String, dynamic>{
          'id': 'u-1',
          'name': 'Asha',
          'email': 'asha@example.test',
          'role': role,
          if (business != null) 'business': business,
        };

    test('carries the business the server attached', () {
      final UserData u = UserData.fromJson(user('admin', business: _json()));

      expect(u.business, isNotNull);
      expect(u.business!.name, 'Mama Duka');
      expect(u.isBusinessOwner, isTrue);
    });

    test('a super admin has none, and only an owner role counts as the owner', () {
      expect(UserData.fromJson(user('super_admin')).business, isNull);
      expect(UserData.fromJson(user('landlord')).isBusinessOwner, isTrue);
      expect(UserData.fromJson(user('administrator')).isBusinessOwner, isTrue);
      for (final String role in <String>['manager', 'sales_officer', 'driver', 'tenant', 'caretaker']) {
        expect(UserData.fromJson(user(role)).isBusinessOwner, isFalse, reason: role);
      }
    });
  });

  group('SubscriptionBanner', () {
    Future<void> show(WidgetTester t, BusinessBilling billing, {bool sw = true}) => t.pumpWidget(
          MaterialApp(home: Scaffold(body: SubscriptionBanner(billing: billing, sw: sw))),
        );

    final Finder banner = find.byKey(const ValueKey<String>('subscription_banner'));

    testWidgets('says nothing while all is well', (t) async {
      await show(t, const BusinessBilling(plan: 'basic', daysLeft: 40));
      expect(banner, findsNothing);
      await show(t, const BusinessBilling(plan: 'free'));
      expect(banner, findsNothing);
    });

    testWidgets('warns in the last week', (t) async {
      await show(t, const BusinessBilling(plan: 'basic', daysLeft: 3));
      expect(banner, findsOneWidget);
      expect(find.textContaining('siku 3'), findsOneWidget);

      await show(t, const BusinessBilling(plan: 'basic', daysLeft: 0), sw: false);
      expect(find.text('The subscription ends today.'), findsOneWidget);
    });

    testWidgets('says it has ended, and when it is on hold', (t) async {
      await show(t, const BusinessBilling(plan: 'basic', daysLeft: -2, isExpired: true, inGrace: true), sw: false);
      expect(find.textContaining('ended 2 day(s) ago'), findsOneWidget);

      await show(t, const BusinessBilling(plan: 'basic', daysLeft: -20, isExpired: true, enforced: true, blocked: true), sw: false);
      expect(find.textContaining('on hold'), findsOneWidget);
    });
  });
}
