<?php

namespace Tests\Feature;

use App\Models\User;
use App\Support\Groups\GroupAccess;
use App\Support\Tenancy\TenantTables;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * Groups (Vikundi), phase 1: the member register, offices and their rights, the joining payments and their verification, member
 * sign-in by phone, and the separation between groups.
 */
class GroupsMembershipTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        GroupAccess::forget();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, '/api/groups' . $uri, $body);
    }

    private function owner(string $name = 'MEG Owner'): User
    {
        return $this->givenServices(User::factory()->create(['name' => $name, 'role' => 'admin', 'is_active' => true, 'phone_number' => '0711000' . random_int(100, 999)]), 'groups');
    }

    /** An existing member entered by the owner, holding [office], with a sign-in. Returns [member id, their account]. */
    private function leader(User $owner, string $name, string $phone, ?string $office): array
    {
        $id = $this->api($owner, 'POST', '/members', ['full_name' => $name, 'phone' => $phone, 'existing' => true])->assertCreated()->json('data.member.id');
        if ($office !== null) {
            $this->api($owner, 'PUT', "/members/{$id}/office", ['office' => $office])->assertOk();
        }
        $this->api($owner, 'POST', "/members/{$id}/sign-in")->assertCreated();
        $account = User::query()->find(DB::table('group_members')->where('id', $id)->value('user_id'));

        return [$id, $account];
    }

    private function setFees(User $owner, float $joining = 80000, float $shares = 200000): void
    {
        $this->api($owner, 'PUT', '/settings', ['values' => ['joining_fee' => $joining, 'share_amount' => $shares, 'member_prefix' => 'MEG'], 'reason' => 'Group rules'])->assertOk();
    }

    public function test_every_group_table_is_scoped_by_business(): void
    {
        $tables = collect(Schema::getTableListing())
            ->map(fn ($t) => str_contains($t, '.') ? substr($t, strrpos($t, '.') + 1) : $t)
            ->filter(fn ($t) => str_starts_with($t, 'group_'))->values()->all();

        $this->assertEqualsCanonicalizing($tables, TenantTables::GROUPS, 'Every group_* table must be listed in TenantTables::GROUPS.');
        foreach (TenantTables::GROUPS as $table) {
            $this->assertTrue(Schema::hasColumn($table, 'owner_id'), "{$table} has no owner_id");
            $this->assertFalse(Schema::hasColumn($table, 'service'), "{$table} is not split by service");
        }
    }

    public function test_an_application_is_approved_only_after_the_joining_fee_is_verified_by_someone_else(): void
    {
        $owner = $this->owner();
        $this->setFees($owner);
        [, $treasurer] = $this->leader($owner, 'Mweka Hazina', '0712000001', 'mweka_hazina');

        $app = $this->api($owner, 'POST', '/members', ['full_name' => 'Asha Juma', 'phone' => '0713000001', 'nida' => '19900101-12345-00001-25'])
            ->assertCreated()->assertJsonPath('data.member.status', 'submitted')->assertJsonPath('data.member.member_number', null)
            ->assertJsonPath('data.approval_blockers', ['joining_fee_unpaid']);
        $id = $app->json('data.member.id');

        $this->api($owner, 'POST', "/members/{$id}/status", ['action' => 'approve'])->assertStatus(422)->assertJsonPath('code', 'approval_blocked');

        // A non-cash payment needs its reference; the same reference cannot be counted twice.
        $this->api($owner, 'POST', '/transactions', ['member_id' => $id, 'category' => 'joining_fee', 'amount' => 80000, 'method' => 'mpesa'])
            ->assertStatus(422)->assertJsonPath('code', 'reference_required');
        $tx = $this->api($owner, 'POST', '/transactions', ['member_id' => $id, 'category' => 'joining_fee', 'amount' => 80000, 'method' => 'mpesa', 'external_ref' => 'QWE123'])
            ->assertCreated()->assertJsonPath('data.transaction.status', 'pending')->json('data.transaction.id');
        $this->api($owner, 'POST', '/transactions', ['member_id' => $id, 'category' => 'joining_fee', 'amount' => 80000, 'method' => 'mpesa', 'external_ref' => 'QWE123'])
            ->assertStatus(422)->assertJsonPath('code', 'duplicate_reference');

        // Still pending: nothing counts yet.
        $this->api($owner, 'POST', "/members/{$id}/status", ['action' => 'approve'])->assertStatus(422);
        // Whoever recorded it cannot verify it.
        $this->api($owner, 'POST', "/transactions/{$tx}/verify")->assertStatus(403)->assertJsonPath('code', 'own_submission');

        $this->api($treasurer, 'POST', "/transactions/{$tx}/verify")->assertOk()
            ->assertJsonPath('data.transaction.status', 'verified')->assertJsonPath('data.transaction.receipt_number', 'RC-000001');

        $this->api($owner, 'POST', "/members/{$id}/status", ['action' => 'approve'])->assertOk()
            ->assertJsonPath('data.member.status', 'active')->assertJsonPath('data.member.member_number', 'MEG-0002');
        $this->assertTrue(DB::table('group_audit_log')->where('action', 'member_approve')->exists());
    }

    public function test_the_shares_must_be_paid_before_membership_only_when_the_group_says_so(): void
    {
        $owner = $this->owner();
        $this->setFees($owner, 0, 200000);
        $id = $this->api($owner, 'POST', '/members', ['full_name' => 'Juma Ali', 'phone' => '0713000002'])->json('data.member.id');
        $this->api($owner, 'GET', "/members/{$id}")->assertJsonPath('data.approval_blockers', []);

        $this->api($owner, 'PUT', '/settings', ['values' => ['shares_required_for' => 'membership'], 'reason' => 'Shares first'])->assertOk();
        $this->api($owner, 'GET', "/members/{$id}")->assertJsonPath('data.approval_blockers', ['shares_unpaid']);
    }

    public function test_a_verified_payment_is_corrected_by_a_reversal_never_by_an_edit(): void
    {
        $owner = $this->owner();
        $this->setFees($owner);
        [, $treasurer] = $this->leader($owner, 'Mweka Hazina', '0712000001', 'mweka_hazina');
        $id = $this->api($owner, 'POST', '/members', ['full_name' => 'Neema', 'phone' => '0713000003'])->json('data.member.id');
        $tx = $this->api($owner, 'POST', '/transactions', ['member_id' => $id, 'category' => 'shares', 'amount' => 50000, 'method' => 'cash'])->json('data.transaction.id');
        $this->api($treasurer, 'POST', "/transactions/{$tx}/verify")->assertOk();
        $this->api($owner, 'GET', "/members/{$id}")->assertJsonPath('data.balances.shares', 50000);

        $this->api($treasurer, 'POST', "/transactions/{$tx}/reverse", ['reason' => 'Wrong member'])->assertOk()
            ->assertJsonPath('data.transaction.direction', 'out')->assertJsonPath('data.transaction.reverses_id', $tx);
        $this->api($owner, 'GET', "/members/{$id}")->assertJsonPath('data.balances.shares', 0);

        $original = DB::table('group_transactions')->where('id', $tx)->first();
        $this->assertSame('verified', $original->status);
        $this->assertEquals(50000, (float) $original->amount);
        $this->api($treasurer, 'POST', "/transactions/{$tx}/reverse", ['reason' => 'Again'])->assertStatus(409);
        // The assistant treasurer verifies but does not reverse.
        [, $assistant] = $this->leader($owner, 'Msaidizi', '0712000009', 'mweka_hazina_msaidizi');
        $this->api($assistant, 'POST', "/transactions/{$tx}/reverse", ['reason' => 'x'])->assertForbidden();
    }

    public function test_a_treasurer_cannot_verify_their_own_payment(): void
    {
        $owner = $this->owner();
        [$treasurerId, $treasurer] = $this->leader($owner, 'Mweka Hazina', '0712000001', 'mweka_hazina');
        $tx = $this->api($owner, 'POST', '/transactions', ['member_id' => $treasurerId, 'category' => 'shares', 'amount' => 1000, 'method' => 'cash'])->json('data.transaction.id');

        $this->api($treasurer, 'POST', "/transactions/{$tx}/verify")->assertStatus(403)->assertJsonPath('code', 'own_payment');
        $this->api($treasurer, 'POST', "/transactions/{$tx}/reject", ['reason' => 'mine'])->assertStatus(403);
    }

    public function test_a_member_sees_only_their_own_file_and_pays_for_themself(): void
    {
        $owner = $this->owner();
        $this->setFees($owner);
        [$memberId, $member] = $this->leader($owner, 'Mwanachama', '0714000001', null);
        $this->leader($owner, 'Another', '0714000002', null);

        $this->api($member, 'GET', '/members')->assertForbidden();
        $this->api($member, 'GET', '/transactions')->assertForbidden();
        $this->api($member, 'POST', '/members', ['full_name' => 'X', 'phone' => '0715000000'])->assertForbidden();

        $me = $this->api($member, 'GET', '/me')->assertOk()->assertJsonPath('data.member.id', $memberId)->assertJsonPath('data.rights', [])
            ->assertJsonPath('data.is_owner', false)->assertJsonPath('data.settings.joining_fee', 80000);
        $this->assertSame([], $me->json('data.waiting'));

        $this->api($member, 'POST', '/me/payments', ['category' => 'shares', 'amount' => 20000, 'method' => 'mpesa', 'external_ref' => 'ABC999'])
            ->assertCreated()->assertJsonPath('data.transaction.member_id', $memberId)->assertJsonPath('data.transaction.status', 'pending');
        $this->api($member, 'GET', '/me/transactions')->assertOk()->assertJsonCount(1, 'data.transactions');
        $this->api($member, 'GET', '/me')->assertJsonPath('data.pending', 1);
    }

    public function test_offices_give_rights_one_holder_each_and_nobody_changes_their_own(): void
    {
        $owner = $this->owner();
        [$chairId, $chair] = $this->leader($owner, 'Mwenyekiti', '0712000010', 'mwenyekiti');
        [$otherId] = $this->leader($owner, 'Second', '0712000011', null);

        $this->api($owner, 'PUT', "/members/{$otherId}/office", ['office' => 'mwenyekiti'])->assertStatus(409)->assertJsonPath('code', 'office_taken');
        $this->api($chair, 'PUT', "/members/{$chairId}/office", ['office' => null])->assertForbidden()->assertJsonPath('code', 'own_office');

        // The chair approves and manages offices; replacing moves the office.
        $this->api($chair, 'PUT', "/members/{$otherId}/office", ['office' => 'katibu'])->assertOk()->assertJsonPath('data.member.office', 'katibu');
        $this->api($owner, 'PUT', "/members/{$otherId}/office", ['office' => 'mwenyekiti', 'replace' => true])->assertOk();
        $this->assertNull(DB::table('group_members')->where('id', $chairId)->value('office'));
        $this->api($chair, 'GET', '/members')->assertForbidden();
        $this->assertTrue(DB::table('group_member_events')->where('member_id', $chairId)->where('kind', 'office')->where('from_value', 'mwenyekiti')->whereNull('to_value')->where('reason', 'replaced')->exists());
    }

    public function test_nida_is_masked_without_the_right_and_a_duplicate_is_refused(): void
    {
        $owner = $this->owner();
        [, $assistant] = $this->leader($owner, 'Katibu Msaidizi', '0712000020', 'katibu_msaidizi');
        $id = $this->api($owner, 'POST', '/members', ['full_name' => 'Rehema', 'phone' => '0713000020', 'nida' => '19900101-12345-00001-25'])->json('data.member.id');

        $this->api($owner, 'GET', "/members/{$id}")->assertJsonPath('data.member.nida', '19900101-12345-00001-25');
        $masked = $this->api($assistant, 'GET', "/members/{$id}")->assertOk()->json('data.member');
        $this->assertTrue($masked['nida_masked']);
        $this->assertStringEndsWith('01-25', $masked['nida']);
        $this->assertStringNotContainsString('19900101', $masked['nida']);
        $this->assertStringNotContainsString('19900101', (string) DB::table('group_members')->where('id', $id)->value('nida'), 'stored encrypted');

        $this->api($assistant, 'POST', '/members', ['full_name' => 'Copy', 'phone' => '0713000021', 'nida' => '1990 0101 12345 00001 25'])
            ->assertStatus(422)->assertJsonPath('code', 'duplicate_nida');
        $this->api($assistant, 'POST', '/members', ['full_name' => 'Copy', 'phone' => '+255713000020'])->assertStatus(422)->assertJsonPath('code', 'duplicate_phone');
        // Whoever approves members may enter someone as an existing member: the management (chair, vice chair, secretary, assistant secretary) all do.
        $this->api($assistant, 'POST', '/members', ['full_name' => 'Old', 'phone' => '0713000022', 'existing' => true])->assertCreated();
    }

    public function test_a_member_signs_in_with_their_phone_and_loses_it_when_they_leave(): void
    {
        $owner = $this->owner();
        [$id, $account] = $this->leader($owner, 'Mwanachama', '0714000050', null);
        DB::table('users')->where('id', $account->id)->update(['password' => bcrypt('Secret#2026'), 'must_change_password' => false]);

        $this->postJson('/api/auth/login', ['email' => '+255714000050', 'password' => 'Secret#2026'])->assertOk()->assertJsonPath('data.user.id', (string) $account->id);
        $this->postJson('/api/auth/login', ['email' => '0714000050', 'password' => 'wrong'])->assertStatus(401);
        // A phone opens a group member's account only, never staff or an owner's.
        $staff = User::factory()->create(['role' => 'manager', 'phone_number' => '0716000060', 'password' => bcrypt('Secret#2026'), 'created_by' => $owner->id]);
        $this->postJson('/api/auth/login', ['email' => '0716000060', 'password' => 'Secret#2026'])->assertStatus(401);
        $this->assertNotNull($staff);

        $this->api($owner, 'POST', "/members/{$id}/status", ['action' => 'exit'])->assertStatus(422)->assertJsonPath('code', 'reason_required');
        $this->api($owner, 'POST', "/members/{$id}/status", ['action' => 'exit', 'reason' => 'Moved away'])->assertOk()->assertJsonPath('data.member.status', 'exited');
        $this->assertFalse((bool) User::query()->find($account->id)->is_active);
        $this->assertSame(0, $account->tokens()->count());
    }

    public function test_the_owner_who_is_also_a_member_is_tied_to_their_own_account(): void
    {
        $owner = $this->owner();
        $id = $this->api($owner, 'POST', '/members', ['full_name' => 'MEG Owner', 'phone' => (string) $owner->phone_number, 'existing' => true])->json('data.member.id');
        $this->api($owner, 'POST', "/members/{$id}/sign-in")->assertOk()->assertJsonPath('data.linked_owner', true);
        $this->api($owner, 'GET', '/me')->assertJsonPath('data.is_owner', true)->assertJsonPath('data.member.id', $id);
    }

    public function test_one_group_never_sees_another(): void
    {
        $a = $this->owner('Group A');
        $b = $this->owner('Group B');
        $id = $this->api($a, 'POST', '/members', ['full_name' => 'Only In A', 'phone' => '0713000099'])->json('data.member.id');

        $this->api($b, 'GET', '/members')->assertOk()->assertJsonCount(0, 'data.members');
        $this->api($b, 'GET', "/members/{$id}")->assertNotFound();
        $this->api($b, 'POST', "/members/{$id}/status", ['action' => 'reject', 'reason' => 'x'])->assertNotFound();
        // The same phone is free in another group.
        $this->api($b, 'POST', '/members', ['full_name' => 'Same Phone', 'phone' => '0713000099'])->assertCreated();
    }

    public function test_a_business_without_the_service_is_kept_out(): void
    {
        $shop = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'inventory');
        $this->api($shop, 'GET', '/me')->assertForbidden()->assertJsonPath('code', 'service_not_assigned');
    }

    public function test_settings_keep_their_history_and_refuse_bad_values(): void
    {
        $owner = $this->owner();
        $this->setFees($owner, 80000);
        $this->api($owner, 'PUT', '/settings', ['values' => ['joining_fee' => 100000], 'reason' => 'AGM decision', 'effective_from' => now()->addMonth()->toDateString()])->assertOk();

        $res = $this->api($owner, 'GET', '/settings')->assertOk();
        $this->assertSame('80000', $res->json('data.settings.joining_fee'), 'a future change does not apply yet');
        $this->assertGreaterThanOrEqual(2, count($res->json('data.history')));
        $this->api($owner, 'PUT', '/settings', ['values' => ['loan_multiplier' => 0], 'reason' => 'bad'])->assertStatus(422);
        $this->api($owner, 'PUT', '/settings', ['values' => ['joining_fee' => 1], 'reason' => ''])->assertStatus(422);
    }
}
