<?php

namespace Tests\Feature;

use App\Models\Rental\House;
use App\Models\Rental\MaintenanceRequest;
use App\Models\Rental\Property;
use App\Models\Rental\RentalAgreement;
use App\Models\Rental\TenantProfile;
use App\Models\User;
use App\Support\PrivateFile;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * Lease documents (signed contracts, ID cards), tenant photos, repair photos and reports used
 * to sit in public storage, readable by anyone who knew or guessed an address, with no sign-in.
 * They are now private: reachable only through a short-lived signed link that the API gives to
 * people who can already see the record.
 */
class PrivateUploadsTest extends TestCase
{
    use RefreshDatabase;

    /** A real 1x1 PNG, so Laravel's "image" rule accepts it without needing the GD extension. */
    private const PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake(PrivateFile::DISK);
        Storage::fake(PrivateFile::LEGACY_DISK);
    }

    // ------------------------------------------------------------- helpers

    private function call2(User $user, string $method, string $uri, array $body = [], array $files = [])
    {
        $token = $user->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->call($method, $uri, $body, [], $files, [
            'HTTP_AUTHORIZATION' => "Bearer {$token}",
            'HTTP_ACCEPT' => 'application/json',
        ]);
    }

    /** A landlord with one house, a tenant and a lease. @return array{0: User, 1: Property, 2: House, 3: User, 4: RentalAgreement} */
    private function landlordWithLease(string $label = 'A'): array
    {
        $landlord = $this->givenServices(User::factory()->create(['role' => 'landlord', 'is_active' => true]), 'rental');
        $property = Property::create(['owner_id' => $landlord->id, 'name' => "Plot {$label}"]);
        $house = House::create(['property_id' => $property->id, 'house_number' => "{$label}1", 'rent_amount' => 100000]);
        $tenant = $this->givenServices(User::factory()->create(['role' => 'tenant', 'is_active' => true, 'created_by' => $landlord->id]), 'rental');
        $lease = RentalAgreement::create([
            'tenant_id' => $tenant->id, 'house_id' => $house->id, 'property_id' => $property->id,
            'start_date' => now()->toDateString(), 'rent_cycle' => 'monthly', 'rent_amount' => 100000, 'status' => 'active',
        ]);

        return [$landlord, $property, $house, $tenant, $lease];
    }

    private function png(string $name = 'p.png'): UploadedFile
    {
        return UploadedFile::fake()->createWithContent($name, base64_decode(self::PNG));
    }

    /** Fetch a link exactly as an image widget would: no sign-in header, no cookies. */
    private function open(string $url)
    {
        $this->app['auth']->forgetGuards();

        return $this->get($url);
    }

    // ----------------------------------------------- new uploads are private

    public function test_a_lease_document_is_stored_privately_and_the_owner_gets_a_working_link(): void
    {
        [$landlord, , , , $lease] = $this->landlordWithLease();

        $response = $this->call2($landlord, 'POST', "/api/rental/agreements/{$lease->id}/documents", ['document_type' => 'id_card'], [
            'document' => UploadedFile::fake()->createWithContent('id.pdf', "%PDF-1.4 fake id card\n%%EOF"),
        ])->assertOk();

        $document = $response->json('data.documents.0');
        $path = $document['path'];

        $this->assertStringStartsWith("agreements/{$lease->id}/", $path);
        Storage::disk(PrivateFile::DISK)->assertExists($path);
        Storage::disk(PrivateFile::LEGACY_DISK)->assertMissing($path);

        // The API gives a signed, expiring link rather than a public address...
        $this->assertStringContainsString('/api/files/private/agreements/', $document['url']);
        $this->assertStringContainsString('signature=', $document['url']);
        $this->assertStringContainsString('expires=', $document['url']);
        // ...and it opens without any sign-in header.
        $this->open($document['url'])->assertOk();
    }

    public function test_another_business_can_neither_add_to_nor_get_a_link_for_someone_elses_lease(): void
    {
        [$landlord, , , , $lease] = $this->landlordWithLease('A');
        [$other] = $this->landlordWithLease('B');

        $this->call2($other, 'POST', "/api/rental/agreements/{$lease->id}/documents", ['document_type' => 'other'], [
            'document' => UploadedFile::fake()->createWithContent('x.pdf', '%PDF'),
        ])->assertNotFound();
        $this->assertSame([], Storage::disk(PrivateFile::DISK)->allFiles('agreements'));

        // A lease with a document: the other business cannot fetch the lease, so is given no link.
        $this->call2($landlord, 'POST', "/api/rental/agreements/{$lease->id}/documents", ['document_type' => 'other'], [
            'document' => UploadedFile::fake()->createWithContent('x.pdf', '%PDF'),
        ])->assertOk();
        $this->call2($other, 'GET', "/api/rental/agreements/{$lease->id}")->assertNotFound();
    }

    public function test_a_tenant_photo_is_stored_privately_and_shown_as_a_signed_link(): void
    {
        [$landlord, , $house] = $this->landlordWithLease();

        $this->call2($landlord, 'POST', '/api/rental/tenants/onboard', [
            'first_name' => 'Asha', 'last_name' => 'Juma', 'email' => 'asha.photo@example.test', 'phone' => '0712000999',
            'rental_house_id' => $house->id, 'rent_amount' => 90000,
        ], ['tenant_photo' => $this->png()])->assertCreated();

        $profile = TenantProfile::withoutAccountScope()->latest('created_at')->firstOrFail();
        $stored = $profile->getRawOriginal('photo_url');

        $this->assertStringStartsWith('tenant_photos/', $stored);
        Storage::disk(PrivateFile::DISK)->assertExists($stored);
        Storage::disk(PrivateFile::LEGACY_DISK)->assertMissing($stored);

        $link = $profile->toArray()['photo_url'];
        $this->assertStringContainsString('/api/files/private/tenant_photos/', $link, 'the API shows a link, never the stored path');
        $this->open($link)->assertOk();
    }

    public function test_a_repair_photo_link_goes_only_to_people_who_can_see_the_request(): void
    {
        [$landlord, $property, $house, $tenant] = $this->landlordWithLease('A');
        [$other] = $this->landlordWithLease('B');
        Storage::disk(PrivateFile::DISK)->put('maintenance/leak.png', base64_decode(self::PNG));
        $request = MaintenanceRequest::create([
            'property_id' => $property->id, 'house_id' => $house->id, 'tenant_id' => $tenant->id,
            'category' => 'plumbing', 'priority' => 'high', 'description' => 'Leak', 'status' => 'open', 'photo_url' => 'maintenance/leak.png',
        ]);

        $mine = $this->call2($landlord, 'GET', "/api/rental/maintenance/requests/{$request->id}")->assertOk()->json('data.photo_url');
        $this->assertStringContainsString('/api/files/private/maintenance/leak.png', $mine);
        $this->assertStringContainsString('signature=', $mine);
        $this->open($mine)->assertOk();

        $theirs = $this->call2($other, 'GET', "/api/rental/maintenance/requests/{$request->id}");
        $this->assertSame(404, $theirs->status(), 'another business is not even told the request exists, so gets no link');

        // The tenant who raised it sees their own photo.
        $this->assertStringContainsString('/api/files/private/', $this->call2($tenant, 'GET', "/api/rental/maintenance/requests/{$request->id}")->json('data.photo_url'));
    }

    public function test_reports_are_written_to_private_storage_with_an_unguessable_name(): void
    {
        $driverUser = $this->givenServices(User::factory()->create(['role' => 'driver', 'is_active' => true]), 'transport');
        $driver = \App\Models\Driver::create([
            'user_id' => $driverUser->id, 'license_number' => 'LIC-RPT-1', 'license_expiry' => now()->addYear(),
            'address' => 'Dar', 'emergency_contact' => '0755000000', 'is_active' => true,
        ]);

        $absolute = app(\App\Services\ReportService::class)->exportReportToPdf($driver, 'revenue', now()->subWeek()->toDateString(), now()->toDateString());

        $this->assertFileExists($absolute);
        $name = basename($absolute);
        $this->assertMatchesRegularExpression('/^report_revenue_\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}_[A-Za-z0-9]{24}\.html$/', $name);
        Storage::disk(PrivateFile::DISK)->assertExists("reports/{$name}");
        Storage::disk(PrivateFile::LEGACY_DISK)->assertMissing("reports/{$name}");
    }

    // ----------------------------------------- the old public address refuses

    public function test_the_public_address_no_longer_serves_the_private_folders_but_still_serves_listing_photos(): void
    {
        $public = Storage::disk(PrivateFile::LEGACY_DISK);
        foreach (['tenant_photos/t.png', 'agreements/7/contract.pdf', 'maintenance/m.png', 'reports/r.html'] as $private) {
            $public->put($private, 'secret');
        }
        foreach (['houses/h.png', 'properties/p.png', 'avatars/a.png'] as $listing) {
            $public->put($listing, 'photo');
        }

        foreach (['tenant_photos/t.png', 'agreements/7/contract.pdf', 'maintenance/m.png', 'reports/r.html'] as $private) {
            $this->open("/api/files/public/{$private}")->assertNotFound();
        }
        foreach (['houses/h.png', 'properties/p.png', 'avatars/a.png'] as $listing) {
            $this->open("/api/files/public/{$listing}")->assertOk();
        }
        $this->open('/api/files/public/houses/../../.env')->assertNotFound();
    }

    // --------------------------------------------------------- signed links

    private function linkTo(string $path): string
    {
        return PrivateFile::url($path);
    }

    public function test_a_signed_link_works_once_signed_and_not_unsigned_edited_or_expired(): void
    {
        Storage::disk(PrivateFile::DISK)->put('agreements/1/doc.pdf', 'contract');
        Storage::disk(PrivateFile::DISK)->put('agreements/2/other.pdf', 'someone elses');
        $link = $this->linkTo('agreements/1/doc.pdf');

        $this->open($link)->assertOk();

        // No signature at all.
        $this->open('/api/files/private/agreements/1/doc.pdf')->assertForbidden();
        // A signature for one file cannot be reused for another.
        $edited = str_replace('agreements/1/doc.pdf', 'agreements/2/other.pdf', $link);
        $this->open($edited)->assertForbidden();
        // A scrambled signature.
        $this->open(preg_replace('/signature=[a-f0-9]+/', 'signature=' . str_repeat('0', 64), $link))->assertForbidden();
        // And it stops working once it has expired.
        $this->travel(7)->hours();
        $this->open($link)->assertForbidden();
    }

    public function test_the_link_lifetime_is_configurable(): void
    {
        Storage::disk(PrivateFile::DISK)->put('reports/r.html', '<p>x</p>');
        config(['uploads.link_hours' => 1]);
        $link = $this->linkTo('reports/r.html');

        $this->travel(59)->minutes();
        $this->open($link)->assertOk();
        $this->travel(2)->minutes();
        $this->open($link)->assertForbidden();
    }

    public function test_files_uploaded_before_this_change_are_still_found_through_a_signed_link(): void
    {
        Storage::disk(PrivateFile::LEGACY_DISK)->put('tenant_photos/old.png', base64_decode(self::PNG));

        $this->open($this->linkTo('tenant_photos/old.png'))->assertOk();
    }

    public function test_a_signed_link_cannot_be_used_to_read_anything_but_the_private_folders(): void
    {
        Storage::disk(PrivateFile::LEGACY_DISK)->put('houses/h.png', 'photo');
        Storage::disk(PrivateFile::DISK)->put('backups/backup_x.json', '{"all":"the data"}');

        // Even with a perfectly valid signature, a path outside the private folders is refused.
        foreach (['houses/h.png', 'backups/backup_x.json', '../.env', 'agreements/../backups/backup_x.json'] as $path) {
            $signed = \Illuminate\Support\Facades\URL::temporarySignedRoute('files.private', now()->addHour(), ['path' => $path], absolute: false);
            $this->assertSame(404, $this->open($signed)->status(), "{$path} must not be readable");
        }
    }

    public function test_a_missing_file_is_a_clean_404_and_a_report_page_cannot_run_scripts(): void
    {
        $this->open($this->linkTo('agreements/1/nothing.pdf'))->assertNotFound();

        Storage::disk(PrivateFile::DISK)->put('reports/r.html', '<script>alert(1)</script>');
        $response = $this->open($this->linkTo('reports/r.html'))->assertOk();
        $this->assertStringContainsString('sandbox', (string) $response->headers->get('Content-Security-Policy'));
        $this->assertSame('nosniff', $response->headers->get('X-Content-Type-Options'));
    }

    // ------------------------------------------------------------ the command

    public function test_the_command_copies_old_files_to_private_storage_and_deletes_nothing_by_default(): void
    {
        $public = Storage::disk(PrivateFile::LEGACY_DISK);
        $private = Storage::disk(PrivateFile::DISK);
        $public->put('tenant_photos/a.png', 'aaa');
        $public->put('agreements/3/c.pdf', 'contract');
        $public->put('houses/h.png', 'listing photo'); // not private: must be left alone

        $this->artisan('files:secure-uploads', ['--dry-run' => true])->assertSuccessful();
        $this->assertSame([], $private->allFiles(), 'a dry run copies nothing');

        $this->artisan('files:secure-uploads')->assertSuccessful();
        $this->assertSame('aaa', $private->get('tenant_photos/a.png'));
        $this->assertSame('contract', $private->get('agreements/3/c.pdf'));
        $this->assertTrue($private->missing('houses/h.png'), 'listing photos are not private');
        $public->assertExists('tenant_photos/a.png');
        $public->assertExists('agreements/3/c.pdf');
        $public->assertExists('houses/h.png');

        // Running it again changes nothing.
        $this->artisan('files:secure-uploads')->assertSuccessful();
        $this->assertCount(2, $private->allFiles());
    }

    public function test_removing_the_originals_needs_the_flag_and_never_touches_listing_photos(): void
    {
        $public = Storage::disk(PrivateFile::LEGACY_DISK);
        $private = Storage::disk(PrivateFile::DISK);
        $public->put('maintenance/m.png', 'repair photo');
        $public->put('reports/r.html', '<p>report</p>');
        $public->put('properties/p.png', 'cover');

        $this->artisan('files:secure-uploads', ['--remove-originals' => true, '--dry-run' => true])->assertSuccessful();
        $public->assertExists('maintenance/m.png');

        $this->artisan('files:secure-uploads', ['--remove-originals' => true])->assertSuccessful();

        $public->assertMissing('maintenance/m.png');
        $public->assertMissing('reports/r.html');
        $public->assertExists('properties/p.png');
        $this->assertSame('repair photo', $private->get('maintenance/m.png'), 'the private copy is intact');

        // The signed link still opens the file after its public original is gone.
        $this->open($this->linkTo('maintenance/m.png'))->assertOk();
        // And the old public address is a dead end.
        $this->open('/api/files/public/maintenance/m.png')->assertNotFound();
    }
}
