<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\Rental\House;
use App\Models\Rental\Property;
use App\Models\Rental\RentalAgreement;
use App\Models\Rental\RentalPayment;
use App\Models\Rental\RentalReceipt;
use App\Models\Rental\RentBill;
use App\Models\User;
use App\Services\Rental\RentalService;
use App\Services\SmsService;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Receipts and text messages say WHOSE they are: the business's own name, address, phone and TIN,
 * not the platform's. Before, every business's customers read "Boda Mapato" / "Dear Customer".
 */
class BusinessIdentityTest extends TestCase
{
    use RefreshDatabase;

    private function owner(string $name, array $business, string $role = 'admin'): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => "{$name} Owner", 'role' => $role, 'is_active' => true,
        ]), 'transport', 'rental');
        Business::forOwnerId($owner->id)->update($business + ['name' => $name]);

        return $owner;
    }

    private function as(User $user, string $method, string $uri, array $body = [])
    {
        $token = $user->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    private function unscoped(callable $fn)
    {
        return TenantContext::withoutScope($fn);
    }

    /** The latest text this number received, or null. */
    private function lastTo(string $phone): ?string
    {
        $messages = $this->sms->to($phone);

        return $messages === [] ? null : end($messages)['message'];
    }

    // ----------------------------------------------------------- transport

    /** A driver created through the API (so it carries its business) with one completed payment. */
    private function driverWithPayment(User $owner, string $email): int
    {
        $this->as($owner, 'POST', '/api/admin/drivers', [
            'name' => 'Juma Driver', 'email' => $email, 'phone_number' => '07' . random_int(10000000, 99999999),
            'license_number' => 'LIC-' . Str::random(6), 'license_expiry' => now()->addYear()->toDateString(),
            'address' => 'Dar', 'emergency_contact' => '0755999888',
        ])->assertCreated();

        $driverId = $this->unscoped(fn () => \App\Models\Driver::query()->whereHas('user', fn ($u) => $u->where('email', $email))->value('id'));

        return DB::table('payments')->insertGetId([
            'reference_number' => 'PAY-' . Str::random(10), 'driver_id' => $driverId, 'amount' => 5000,
            'covers_days' => json_encode(['2026-03-01']), 'status' => 'completed', 'receipt_status' => 'pending',
            'payment_date' => now(), 'recorded_by' => $owner->id, 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function receiptHeading(User $by, int $paymentId): array
    {
        $receiptId = $this->as($by, 'POST', '/api/payment-receipts/generate', ['payment_id' => $paymentId])->assertCreated()->json('data.id');

        return $this->as($by, 'GET', "/api/payment-receipts/{$receiptId}/preview")->assertOk()->json('data.receipt_data');
    }

    public function test_a_transport_receipt_carries_the_drivers_own_business_not_the_platforms_name(): void
    {
        $alpha = $this->owner('Alpha Boda Ltd', ['address' => 'Kariakoo, Dar', 'phone' => '0712111222', 'tin' => '111-222-333', 'email' => 'info@alpha.example', 'logo_path' => 'business_logos/alpha.png']);
        $bravo = $this->owner('Bravo Transport', ['address' => 'Mwanza', 'phone' => '0713444555', 'tin' => '444-555-666']);

        $a = $this->receiptHeading($alpha, $this->driverWithPayment($alpha, 'a.driver@example.test'));
        $b = $this->receiptHeading($bravo, $this->driverWithPayment($bravo, 'b.driver@example.test'));

        $this->assertSame('Alpha Boda Ltd', $a['company_name']);
        $this->assertSame('Kariakoo, Dar', $a['company_address']);
        $this->assertSame('0712111222', $a['company_phone']);
        $this->assertSame('111-222-333', $a['company_tin']);
        $this->assertSame('info@alpha.example', $a['company_email']);
        $this->assertStringEndsWith('/api/files/public/business_logos/alpha.png', $a['company_logo_url']);

        $this->assertSame('Bravo Transport', $b['company_name']);
        $this->assertSame('444-555-666', $b['company_tin']);
        $this->assertNull($b['company_logo_url']);

        foreach ([$a, $b] as $receipt) {
            $this->assertNotSame(config('app.name'), $receipt['company_name']);
        }
    }

    public function test_a_super_admin_printing_a_receipt_still_gets_the_drivers_business(): void
    {
        $alpha = $this->owner('Alpha Boda Ltd', ['phone' => '0712111222']);
        $paymentId = $this->driverWithPayment($alpha, 'a.driver@example.test');
        $super = User::factory()->create(['role' => 'super_admin', 'is_active' => true]);

        $this->assertSame('Alpha Boda Ltd', $this->receiptHeading($super, $paymentId)['company_name']);
    }

    // ---------------------------------------------------------------- rental

    /** @return array{0: User, 1: House, 2: User} landlord, house, tenant with a bill of 100,000 */
    private function landlordTenantBill(string $businessName, array $business = []): array
    {
        $landlord = $this->owner($businessName, $business, 'landlord');
        $property = Property::create(['owner_id' => $landlord->id, 'name' => "{$businessName} Plot"]);
        $house = House::create(['property_id' => $property->id, 'house_number' => 'A1', 'rent_amount' => 100000]);

        $tenant = User::factory()->create(['role' => 'tenant', 'is_active' => true, 'created_by' => $landlord->id, 'phone_number' => '0766000111']);
        $agreement = RentalAgreement::create([
            'tenant_id' => $tenant->id, 'house_id' => $house->id, 'property_id' => $property->id,
            'start_date' => now()->subMonth()->toDateString(), 'rent_cycle' => 'monthly', 'rent_amount' => 100000, 'status' => 'active',
        ]);
        RentBill::create([
            'agreement_id' => $agreement->id, 'month_year' => now()->format('m-Y'), 'amount_due' => 100000,
            'balance' => 100000, 'due_date' => now()->subDays(2)->toDateString(), 'status' => 'unpaid',
        ]);

        return [$landlord, $house, $tenant];
    }

    public function test_the_overdue_text_comes_from_the_landlords_business_with_how_to_reach_it(): void
    {
        [, , $tenant] = $this->landlordTenantBill('Mama Rent', ['phone' => '0712999000']);

        app(RentalService::class)->processOverdueBills();

        $text = $this->lastTo($tenant->phone_number);
        $this->assertNotNull($text);
        $this->assertStringStartsWith('Mama Rent: URGENT', $text);
        $this->assertStringContainsString('OVERDUE', $text);
        $this->assertStringEndsWith('Contact: 0712999000.', $text);
    }

    public function test_two_landlords_texts_name_two_different_businesses(): void
    {
        [, , $t1] = $this->landlordTenantBill('Mama Rent', ['phone' => '0712999000']);
        // A second tenant with its own number, so each message can be told apart.
        [, , $t2] = $this->landlordTenantBill('Baba Homes', ['phone' => '0713888000']);
        $t2->forceFill(['phone_number' => '0766000222'])->save();

        app(RentalService::class)->processOverdueBills();

        $this->assertStringStartsWith('Mama Rent:', (string) $this->lastTo('0766000111'));
        $this->assertStringStartsWith('Baba Homes:', (string) $this->lastTo('0766000222'));
        $this->assertStringNotContainsString('Baba', (string) $this->lastTo('0766000111'));
    }

    public function test_a_rental_receipt_records_the_landlords_business(): void
    {
        [$landlord, , $tenant] = $this->landlordTenantBill('Mama Rent', ['address' => 'Sinza', 'phone' => '0712999000', 'tin' => '777-888-999']);
        $bill = RentBill::query()->firstOrFail();

        $this->as($landlord, 'POST', '/api/rental/payments/record', [
            'bill_id' => $bill->id, 'amount_paid' => 40000, 'payment_method' => 'cash',
        ])->assertOk();

        $receipt = RentalReceipt::query()->latest('created_at')->firstOrFail();
        $details = $receipt->details;
        $this->assertSame('Mama Rent', $details['business_name']);
        $this->assertSame('Sinza', $details['business_address']);
        $this->assertSame('0712999000', $details['business_phone']);
        $this->assertSame('777-888-999', $details['business_tin']);

        $text = $this->lastTo($tenant->phone_number);
        $this->assertStringContainsString('received by Mama Rent', (string) $text);
        $this->assertStringContainsString('Contact: 0712999000.', (string) $text);
    }

    // ------------------------------------------------------ the wording itself

    public function test_the_messages_read_as_they_always_did_when_there_is_no_business_to_name(): void
    {
        SmsService::sendPaymentReceipt('0700000001', 50000, 'R-1', 25000);
        $this->assertSame(
            'Dear Customer, payment of TZS 50,000 received. Receipt No: R-1. Remaining Balance: TZS 25,000. Thank you.',
            $this->lastTo('0700000001')
        );

        SmsService::sendOverdueAlert('0700000002', 'A1', 100000);
        $this->assertSame('URGENT: Your rent for House A1 is OVERDUE. Outstanding balance: TZS 100,000. Please settle immediately.', $this->lastTo('0700000002'));
    }

    public function test_every_rental_message_names_the_business_and_leaves_out_what_it_lacks(): void
    {
        $named = ['name' => 'Mama Rent', 'phone' => '0712999000'];
        $nameOnly = ['name' => 'Mama Rent', 'phone' => ''];

        SmsService::sendPaymentReceipt('0700000001', 50000, 'R-1', 0, $named);
        SmsService::sendRentReminder('0700000002', 'A1', 100000, '2026-11-01', $nameOnly);
        SmsService::sendOverdueAlert('0700000003', 'A1', 100000, $nameOnly);

        $this->assertSame(
            'Dear Customer, payment of TZS 50,000 received by Mama Rent. Receipt No: R-1. Remaining Balance: TZS 0. Thank you. Contact: 0712999000.',
            $this->lastTo('0700000001')
        );
        $this->assertSame(
            'Mama Rent: Reminder: Your rent for House A1 (TZS 100,000) is due on 2026-11-01. Please pay on time to avoid penalties.',
            $this->lastTo('0700000002')
        );
        $this->assertStringStartsWith('Mama Rent: URGENT', (string) $this->lastTo('0700000003'));
        $this->assertStringNotContainsString('Contact:', (string) $this->lastTo('0700000003'));
    }
}
