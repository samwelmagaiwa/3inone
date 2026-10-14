import 'package:boda_mapato/models/plan_prices.dart';
import 'package:boda_mapato/models/business_registration.dart';
import 'package:boda_mapato/utils/plan_text.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({bool configured = true, List<Map<String, dynamic>>? plans}) => <String, dynamic>{
      'currency': 'TZS',
      'periods': <int>[1, 3, 6, 12],
      'trial_days': 30,
      'total_services': 3,
      'configured': configured,
      'updated_at': '2026-10-15T10:00:00+03:00',
      'plans': plans ??
          <Map<String, dynamic>>[
            // deliberately out of order: the model sorts by what a plan covers
            <String, dynamic>{
              'plan': 'premium',
              'services_included': 3,
              'prices': <Map<String, dynamic>>[
                <String, dynamic>{'months': 1, 'amount': 70000},
                <String, dynamic>{'months': 3, 'amount': 200000.5},
                <String, dynamic>{'months': 6, 'amount': null},
              ],
            },
            <String, dynamic>{
              'plan': 'basic',
              'services_included': 1,
              'prices': <Map<String, dynamic>>[
                <String, dynamic>{'months': 1, 'amount': 30000},
                <String, dynamic>{'months': 3, 'amount': 85000},
              ],
            },
            <String, dynamic>{'plan': 'standard', 'services_included': 2, 'prices': <Map<String, dynamic>>[]},
          ],
    };

void main() {
  group('PlanCatalog', () {
    test('reads the plans, what each covers and its prices, smallest first', () {
      final PlanCatalog c = PlanCatalog.fromJson(_json());

      expect(c.offers.map((PlanOffer o) => o.plan), <String>['basic', 'standard', 'premium']);
      expect(c.offers.map((PlanOffer o) => o.servicesIncluded), <int>[1, 2, 3]);
      expect(c.currency, 'TZS');
      expect(c.periods, <int>[1, 3, 6, 12]);
      expect(c.trialDays, 30);
      expect(c.totalServices, 3);
      expect(c.configured, isTrue);
      expect(c.updatedAt, isNotNull);

      expect(c.priceFor('basic', 1), 30000);
      expect(c.priceFor('premium', 3), 200000.5);
      expect(c.priceFor('premium', 6), isNull, reason: 'a price that is not set');
      expect(c.priceFor('standard', 1), isNull);
      expect(c.priceFor('basic', 12), isNull, reason: 'a period nobody priced');
      expect(c.priceFor('gold', 1), isNull, reason: 'a plan that is not sold');
      expect(c.offer('basic')!.hasPrice, isTrue);
      expect(c.offer('standard')!.hasPrice, isFalse);
    });

    test('a plan is a number of services: basic one, standard two, premium all three', () {
      final PlanCatalog c = PlanCatalog.fromJson(_json());

      expect(c.servicesIncluded('basic'), 1);
      expect(c.servicesIncluded('standard'), 2);
      expect(c.servicesIncluded('premium'), 3);
      expect(c.servicesIncluded('trial'), isNull, reason: 'a trial has no limit');

      expect(c.covers('basic', 1), isTrue);
      expect(c.covers('basic', 2), isFalse);
      expect(c.covers('standard', 2), isTrue);
      expect(c.covers('standard', 3), isFalse);
      expect(c.covers('premium', 3), isTrue);
      expect(c.covers('trial', 3), isTrue);
      expect(c.covers('free', 3), isTrue);

      expect(c.planFor(1), 'basic');
      expect(c.planFor(2), 'standard');
      expect(c.planFor(3), 'premium');
      expect(c.planFor(0), 'basic');
      expect(c.planFor(9), 'premium', reason: 'more than any covers: the biggest');
    });

    test('before the server has answered, the plans and what they cover are still known, without prices', () {
      const PlanCatalog c = PlanCatalog.fallback;

      expect(c.offers.map((PlanOffer o) => o.plan), kSellablePlans);
      expect(c.offers.map((PlanOffer o) => o.servicesIncluded), <int>[1, 2, 3]);
      expect(c.configured, isFalse);
      expect(c.priceFor('basic', 1), isNull);
      expect(c.planFor(2), 'standard');
      expect(kPlanServices, <String, int>{'basic': 1, 'standard': 2, 'premium': 3});
      expect(kPricePeriods, <int>[1, 3, 6, 12]);
    });

    test('an empty or odd answer falls back to the known plans instead of breaking', () {
      final PlanCatalog empty = PlanCatalog.fromJson(<String, dynamic>{});
      expect(empty.offers.map((PlanOffer o) => o.plan), kSellablePlans);
      expect(empty.configured, isFalse);
      expect(empty.currency, 'TZS');
      expect(empty.trialDays, 30);

      final PlanCatalog odd = PlanCatalog.fromJson(_json(plans: <Map<String, dynamic>>[
        <String, dynamic>{'plan': 'basic', 'prices': 'nonsense'},
      ]));
      expect(odd.offer('basic')!.servicesIncluded, 1, reason: 'taken from the rule when the server did not say');
      expect(odd.priceFor('basic', 1), isNull);
    });
  });

  group('the words', () {
    test('what a plan covers', () {
      expect(planCoverText(1, sw: true), 'Huduma MOJA');
      expect(planCoverText(1, sw: false), 'ONE service');
      expect(planCoverText(2, sw: true), 'Huduma 2');
      expect(planCoverText(2, sw: false), 'TWO services');
      expect(planCoverText(3, sw: true), 'Huduma ZOTE 3');
      expect(planCoverText(3, sw: false), 'ALL 3 services');
    });

    test('how long, and how much', () {
      expect(periodText(1, sw: true), 'Mwezi 1');
      expect(periodText(1, sw: false), '1 month');
      expect(periodText(3, sw: true), 'Miezi 3');
      expect(periodText(6, sw: false), '6 months');
      expect(periodText(12, sw: true), 'Mwaka 1');
      expect(periodText(12, sw: false), '1 year');
      expect(moneyText('TZS', 30000), 'TZS 30,000');
      expect(moneyText('TZS', 1234567), 'TZS 1,234,567');
    });

    test('a plan that is too small says so plainly, in one language', () {
      final String en = planTooSmallText('basic', 1, 2, 'standard', sw: false);
      expect(en, 'The Basic plan covers ONE service only, and you chose 2. Choose the Standard plan or fewer services.');
      final String sw = planTooSmallText('basic', 1, 2, 'standard', sw: true);
      expect(sw, startsWith('Mpango wa Msingi ni huduma MOJA tu, na umechagua 2.'));
      expect(sw, contains('Kawaida'));
      expect(planTooSmallText('standard', 2, 3, 'premium', sw: false), 'The Standard plan covers 2 services only, and you chose 3. Choose the Premium plan or fewer services.');
      expect(planTooSmallText('standard', 2, 3, 'premium', sw: true), contains('unahusu huduma 2 tu'));
    });
  });

  group('the registration carries the package', () {
    test('the request says which plan and for how many months', () {
      const BusinessRegistrationRequest r = BusinessRegistrationRequest(
        name: 'A', businessName: 'B', email: 'a@b.c', phoneNumber: '0743519100', password: 'x', passwordConfirmation: 'x',
        requestedServices: <String>['rental', 'transport'], requestedPlan: 'standard', requestedMonths: 3,
      );
      expect(r.toJson()['requested_plan'], 'standard');
      expect(r.toJson()['requested_months'], 3);

      const BusinessRegistrationRequest none = BusinessRegistrationRequest(
        name: 'A', businessName: 'B', email: 'a@b.c', phoneNumber: '0743519100', password: 'x', passwordConfirmation: 'x',
        requestedServices: <String>['rental'],
      );
      expect(none.toJson().containsKey('requested_plan'), isFalse);
    });

    test('the super admin reads the package, its months and the price set for it', () {
      final BusinessRegistration r = BusinessRegistration.fromJson(<String, dynamic>{
        'id': '1', 'status': 'pending', 'business_name': 'Asha', 'requested_services': <String>['rental', 'transport'],
        'requested_plan': 'standard', 'requested_months': 3, 'requested_price': 140000, 'user': <String, dynamic>{},
      });
      expect(r.requestedPlan, 'standard');
      expect(r.requestedMonths, 3);
      expect(r.requestedPrice, 140000);

      final BusinessRegistration old = BusinessRegistration.fromJson(<String, dynamic>{'id': '2', 'status': 'pending', 'business_name': 'Old'});
      expect(old.requestedPlan, isNull, reason: 'a registration from before packages existed');
      expect(old.requestedPrice, isNull);
    });
  });
}
