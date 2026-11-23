<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Groups\DemoGroup;
use App\Support\Groups\GroupAccess;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * Groups (Vikundi), phase 5b: invitation codes and what someone outside the group can do with one (apply, ask to hire), the referral tree,
 * members' photos and documents, and the reports and exports.
 */
class GroupsInvitationsRecordsTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;

    /** @var array<string, User> */
    private array $people = [];

    /** @var array<string, int> */
    private array $ids = [];

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
        Storage::fake('local');
        Carbon::setTestNow(Carbon::parse('2026-11-10 08:00:00'));
        $this->owner = $this->givenServices(User::factory()->create(['name' => 'MEG Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0711000999']), 'groups');
        Business::forOwnerId($this->owner->id)->update(['name' => 'MEG']);
        foreach ([['chair', '0712000001', 'mwenyekiti'], ['treasurer', '0712000002', 'mweka_hazina'], ['secretary', '0712000004', 'katibu'],
            ['assistant', '0712000005', 'katibu_msaidizi'], ['asha', '0713000001', null]] as [$key, $phone, $office]) {
            $id = $this->api($this->owner, 'POST', '/members', ['full_name' => ucfirst($key) . ' Member', 'phone' => $phone, 'existing' => true, 'nida' => '19900101' . substr($phone, 1)])->assertCreated()->json('data.member.id');
            if ($office !== null) {
                $this->api($this->owner, 'PUT', "/members/{$id}/office", ['office' => $office])->assertOk();
            }
            $this->api($this->owner, 'POST', "/members/{$id}/sign-in")->assertCreated();
            $this->ids[$key] = $id;
            $this->people[$key] = User::query()->find(DB::table('group_members')->where('id', $id)->value('user_id'));
        }
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        GroupAccess::forget();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, '/api/groups' . $uri, $body);
    }

    private function guest(string $method, string $uri, array $body = [])
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        GroupAccess::forget();

        return $this->json($method, '/api/public/groups' . $uri, $body);
    }

    /** A real 1x1 PNG (fake images need the GD extension, which the test image may not have). */
    private function png(string $name): UploadedFile
    {
        $path = tempnam(sys_get_temp_dir(), 'png');
        file_put_contents($path, \App\Support\Groups\DemoGroup::solidPng(240));

        return new UploadedFile($path, $name, 'image/png', null, true);
    }

    public function test_someone_with_a_members_code_applies_and_is_linked_to_the_member_who_invited_them(): void
    {
        $code = $this->api($this->people['asha'], 'GET', '/invitations')->assertOk()->json('data.mine.code');
        $this->assertSame($code, $this->api($this->people['asha'], 'GET', '/invitations')->json('data.mine.code'), 'the same code each time');

        $this->guest('GET', '/' . $code)->assertOk()->assertJsonPath('data.group', 'MEG')->assertJsonPath('data.invited_by', 'Asha');
        $this->guest('GET', '/NOSUCH99')->assertNotFound();
        $this->guest('POST', "/{$code}/apply", ['full_name' => 'Rehema Said', 'phone' => '0715000001'])->assertStatus(422); // no consent
        $ref = $this->guest('POST', "/{$code}/apply", ['full_name' => 'Rehema Said', 'phone' => '0715000001', 'consent' => true])
            ->assertCreated()->json('data.application_ref');

        $app = DB::table('group_members')->where('application_ref', $ref)->first();
        $this->assertSame('submitted', $app->status);
        $this->assertSame($this->ids['asha'], (int) $app->referrer_id);
        $this->assertSame('invitation', $app->source);
        $this->assertSame((string) $this->owner->id, (string) $app->owner_id, 'written as the group the code belongs to');
        $this->guest('POST', "/{$code}/apply", ['full_name' => 'Copy', 'phone' => '+255715000001', 'consent' => true])->assertStatus(422)->assertJsonPath('code', 'duplicate_phone');
        $this->api($this->owner, 'GET', '/me')->assertJsonPath('data.waiting.applications', 1);
    }

    public function test_the_groups_own_code_has_no_referrer_and_a_stopped_code_finds_nothing(): void
    {
        $this->api($this->people['asha'], 'POST', '/invitations')->assertForbidden();
        $group = $this->api($this->people['secretary'], 'POST', '/invitations')->assertCreated()->json('data.group.0');
        $this->guest('GET', '/' . $group['code'])->assertOk()->assertJsonPath('data.invited_by', null);
        $ref = $this->guest('POST', "/{$group['code']}/apply", ['full_name' => 'Poster Person', 'phone' => '0715000002', 'consent' => true])->assertCreated()->json('data.application_ref');
        $this->assertNull(DB::table('group_members')->where('application_ref', $ref)->value('referrer_id'));

        $this->api($this->people['secretary'], 'POST', "/invitations/{$group['id']}/stop")->assertOk();
        $this->guest('GET', '/' . $group['code'])->assertNotFound();
    }

    public function test_someone_outside_asks_to_hire_with_a_code_and_the_keeper_finds_it(): void
    {
        $chairs = $this->api($this->people['chair'], 'POST', '/assets', ['code' => 'VT-01', 'name' => 'Viti', 'quantity' => 50, 'hire_rate' => 300, 'custodian_id' => $this->ids['asha']])->json('data.asset.id');
        $code = $this->api($this->people['asha'], 'GET', '/invitations')->json('data.mine.code');

        $this->guest('GET', '/' . $code)->assertJsonPath('data.assets.0.name', 'Viti')->assertJsonPath('data.assets.0.free_today', 50);
        $this->guest('GET', "/{$code}/assets/{$chairs}/availability?from=2026-11-20&to=2026-11-21")->assertJsonPath('data.free', 50)->assertJsonPath('data.days', 2);
        $hire = ['asset_id' => $chairs, 'start_date' => '2026-11-20', 'end_date' => '2026-11-21', 'name' => 'Mzee Kassim', 'phone' => '0754000111'];
        $this->guest('POST', "/{$code}/hire", ['quantity' => 60] + $hire)->assertStatus(422)->assertJsonPath('code', 'not_enough');
        $this->guest('POST', "/{$code}/hire", ['quantity' => 40] + $hire)->assertCreated()->assertJsonPath('data.amount', 24000);

        $this->api($this->people['asha'], 'GET', '/hires?status=requested')->assertOk()->assertJsonPath('data.hires.0.who', 'Mzee Kassim');
    }

    public function test_the_tree_shows_who_brought_whom_and_a_member_sees_their_own_branch(): void
    {
        $code = $this->api($this->people['asha'], 'GET', '/invitations')->json('data.mine.code');
        $ref = $this->guest('POST', "/{$code}/apply", ['full_name' => 'Rehema Said', 'phone' => '0715000001', 'consent' => true])->json('data.application_ref');
        $rehema = (int) DB::table('group_members')->where('application_ref', $ref)->value('id');

        $this->api($this->people['asha'], 'GET', '/me/referrals')->assertJsonCount(1, 'data.nodes'); // an application is not yet in the tree
        $this->api($this->people['chair'], 'POST', "/members/{$rehema}/status", ['action' => 'approve'])->assertOk();

        $branch = $this->api($this->people['asha'], 'GET', '/me/referrals')->assertOk()->json('data');
        $this->assertSame($this->ids['asha'], $branch['root']);
        $this->assertSame($this->ids['asha'], collect($branch['nodes'])->firstWhere('id', $rehema)['referrer_id']);
        $this->api($this->people['asha'], 'GET', '/tree')->assertForbidden();
        $tree = $this->api($this->people['chair'], 'GET', '/tree')->assertOk()->json('data');
        $this->assertSame(6, $tree['stats']['members']);
        $this->assertSame(5, $tree['stats']['no_referrer']);
    }

    public function test_a_profile_photo_must_be_a_jpg_or_png_up_to_2_mb_and_at_least_200_pixels(): void
    {
        $asha = $this->ids['asha'];
        $as = $this->people['assistant'];

        // A PDF is a paper, not a photo.
        $this->api($as, 'POST', "/members/{$asha}/documents", ['file' => UploadedFile::fake()->create('x.pdf', 100, 'application/pdf'), 'kind' => 'photo'])
            ->assertStatus(422)->assertJsonPath('code', 'not_an_image');

        // Too small: 1 x 1 pixel.
        $tiny = tempnam(sys_get_temp_dir(), 'png');
        file_put_contents($tiny, DemoGroup::solidPng(1));
        $this->api($as, 'POST', "/members/{$asha}/documents", ['file' => new UploadedFile($tiny, 'tiny.png', 'image/png', null, true), 'kind' => 'photo'])
            ->assertStatus(422)->assertJsonPath('code', 'photo_too_small');

        // Too big: a real PNG padded past 2 MB.
        $big = tempnam(sys_get_temp_dir(), 'png');
        file_put_contents($big, DemoGroup::solidPng(240) . str_repeat('0', 2 * 1024 * 1024));
        $this->api($as, 'POST', "/members/{$asha}/documents", ['file' => new UploadedFile($big, 'big.png', 'image/png', null, true), 'kind' => 'photo'])
            ->assertStatus(422)->assertJsonPath('code', 'photo_too_big');

        // A good one is kept and becomes the profile photo.
        $this->api($as, 'POST', "/members/{$asha}/documents", ['file' => $this->png('ok.png'), 'kind' => 'photo'])->assertCreated();
        $this->assertNotNull(DB::table('group_members')->where('id', $asha)->value('photo_path'));
    }

    public function test_photos_and_papers_are_kept_privately_and_id_copies_only_for_those_who_may_see_nida(): void
    {
        $asha = $this->ids['asha'];
        $photo = $this->png('asha.png');
        $this->api($this->people['assistant'], 'POST', "/members/{$asha}/documents", ['file' => $photo, 'kind' => 'photo'])->assertCreated()->assertJsonCount(1, 'data.documents');
        $this->api($this->people['assistant'], 'POST', "/members/{$asha}/documents", ['file' => UploadedFile::fake()->create('id.pdf', 100, 'application/pdf'), 'kind' => 'id'])
            ->assertForbidden()->assertJsonPath('code', 'sensitive_right_needed');
        $this->api($this->people['secretary'], 'POST', "/members/{$asha}/documents", ['file' => UploadedFile::fake()->create('id.pdf', 100, 'application/pdf'), 'kind' => 'id'])->assertCreated();

        $this->api($this->people['secretary'], 'GET', "/members/{$asha}")->assertJsonCount(2, 'data.documents');
        $this->assertNotNull($this->api($this->people['secretary'], 'GET', "/members/{$asha}")->json('data.photo_url'));
        $this->api($this->people['assistant'], 'GET', "/members/{$asha}")->assertJsonCount(1, 'data.documents', 'the ID copy is hidden');
        $this->api($this->people['asha'], 'POST', "/members/{$asha}/documents", ['file' => $this->png('x.png'), 'kind' => 'photo'])->assertForbidden();
        $this->assertCount(2, Storage::disk('local')->allFiles('group_documents'));
    }

    public function test_reports_add_up_and_exports_never_carry_a_formula(): void
    {
        $this->api($this->owner, 'POST', '/members', ['full_name' => '=HYPERLINK("x")', 'phone' => '0716000001', 'existing' => true])->assertCreated();
        $tx = $this->api($this->people['treasurer'], 'POST', '/transactions', ['member_id' => $this->ids['asha'], 'category' => 'savings', 'amount' => 50000, 'method' => 'cash'])->json('data.transaction.id');
        $this->api($this->people['chair'], 'POST', "/transactions/{$tx}/verify")->assertForbidden(); // the chair does not verify money
        DB::table('group_transactions')->where('id', $tx)->update(['status' => 'verified', 'verified_at' => now(), 'verified_by' => (string) $this->owner->id]);

        $sum = $this->api($this->people['treasurer'], 'GET', '/reports/summary?from=2026-11-01&to=2026-11-30')->assertOk()->json('data');
        $this->assertEquals(50000, $sum['money']['savings']['in']);
        $this->assertSame(6, $sum['members']['by_status']['active']);
        $this->api($this->people['asha'], 'GET', '/reports/summary?from=2026-11-01&to=2026-11-30')->assertForbidden();

        $csv = $this->api($this->people['secretary'], 'GET', '/reports/members.csv')->assertOk()->streamedContent();
        $this->assertStringContainsString("'=HYPERLINK", $csv);
        $this->assertStringContainsString('"Member number",Name,Phone', $csv);
        $csv = $this->api($this->people['treasurer'], 'GET', '/reports/transactions.csv?from=2026-11-01&to=2026-11-30')->assertOk()->streamedContent();
        $this->assertStringContainsString('savings,in,50000', $csv);
        $this->assertTrue(DB::table('group_audit_log')->where('action', 'export_members')->exists());
    }
}
