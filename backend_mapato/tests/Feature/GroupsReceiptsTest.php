<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Groups\GroupAccess;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Groups (Vikundi): receipts. A verified payment has a receipt its member (or an officer who sees the finances) can read, carrying a link
 * that anyone can use to check it is genuine; a made-up or changed one does not verify, and nothing but the facts of the receipt is shown.
 */
class GroupsReceiptsTest extends TestCase
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
        $this->owner = $this->givenServices(User::factory()->create(['name' => 'MEG Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0711000999']), 'groups');
        Business::forOwnerId($this->owner->id)->update(['name' => 'MEG Group']);
        foreach ([['treasurer', '0712000002', 'mweka_hazina'], ['assistant', '0712000003', 'mweka_hazina_msaidizi'], ['secretary', '0712000004', 'katibu'],
            ['asha', '0713000001', null], ['juma', '0713000002', null]] as [$key, $phone, $office]) {
            $id = $this->api($this->owner, 'POST', '/members', ['full_name' => ucfirst($key) . ' Member', 'phone' => $phone, 'existing' => true])->assertCreated()->json('data.member.id');
            if ($office !== null) {
                $this->api($this->owner, 'PUT', "/members/{$id}/office", ['office' => $office])->assertOk();
            }
            $this->api($this->owner, 'POST', "/members/{$id}/sign-in")->assertCreated();
            $this->ids[$key] = $id;
            $this->people[$key] = User::query()->find(DB::table('group_members')->where('id', $id)->value('user_id'));
        }
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        GroupAccess::forget();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, '/api/groups' . $uri, $body);
    }

    /** A verified savings payment for Asha: recorded by the treasurer, verified by the assistant. Returns the transaction id. */
    private function verifiedPayment(): int
    {
        $id = (int) $this->api($this->people['treasurer'], 'POST', '/transactions', ['member_id' => $this->ids['asha'], 'category' => 'savings', 'amount' => 50000, 'method' => 'cash'])
            ->assertCreated()->json('data.transaction.id');
        $this->api($this->people['assistant'], 'POST', "/transactions/{$id}/verify")->assertOk();

        return $id;
    }

    public function test_a_member_reads_their_own_receipt_and_officers_who_see_the_finances_read_any(): void
    {
        $id = $this->verifiedPayment();

        $r = $this->api($this->people['asha'], 'GET', "/receipts/{$id}")->assertOk()->assertJsonPath('data.receipt.group', 'MEG Group')->assertJsonPath('data.receipt.transaction.amount', 50000);
        $this->assertStringContainsString('/api/public/groups/receipts/', $r->json('data.receipt.verify_url'));
        $this->assertNotNull($r->json('data.receipt.transaction.receipt_number'));
        $this->assertSame('Assistant Member', $r->json('data.receipt.transaction.verified_by_name'));
        // The receipt carries the member's number, so it can be sent to them (by text message or WhatsApp).
        $this->assertSame('0713000001', $r->json('data.receipt.member_phone'));
        $this->api($this->people['treasurer'], 'GET', "/receipts/{$id}")->assertOk()->assertJsonPath('data.receipt.member_phone', '0713000001');
        $this->api($this->people['juma'], 'GET', "/receipts/{$id}")->assertNotFound();
        $this->api($this->people['secretary'], 'GET', "/receipts/{$id}")->assertNotFound();
    }

    public function test_a_payment_that_is_not_verified_has_no_receipt(): void
    {
        $id = (int) $this->api($this->people['treasurer'], 'POST', '/transactions', ['member_id' => $this->ids['asha'], 'category' => 'savings', 'amount' => 1000, 'method' => 'cash'])->json('data.transaction.id');
        $this->api($this->people['asha'], 'GET', "/receipts/{$id}")->assertNotFound();
        $this->api($this->people['treasurer'], 'GET', "/receipts/{$id}")->assertNotFound();
    }

    public function test_anyone_can_check_a_receipt_and_a_changed_or_made_up_one_does_not_verify(): void
    {
        $id = $this->verifiedPayment();
        $url = $this->api($this->people['asha'], 'GET', "/receipts/{$id}")->json('data.receipt.verify_url');
        $path = substr($url, strpos($url, '/api/'));

        $this->flushHeaders();
        $ok = $this->getJson($path)->assertOk()->assertJsonPath('data.group', 'MEG Group')->assertJsonPath('data.amount', 50000)->assertJsonPath('data.category', 'savings');
        $this->assertArrayNotHasKey('member', $ok->json('data'));
        $this->assertStringNotContainsString('Asha', $ok->getContent());

        // A browser gets a page.
        $this->get($path, ['Accept' => 'text/html'])->assertOk()->assertSee('MEG Group')->assertSee('Genuine receipt', false);

        // Changing the signature or the number, or making one up, never verifies.
        $parts = explode('.', substr($path, strrpos($path, '/') + 1));
        $this->getJson('/api/public/groups/receipts/' . $parts[0] . '.' . $parts[1] . '.' . str_repeat('0', 16))->assertNotFound();
        $this->getJson('/api/public/groups/receipts/' . $parts[0] . '.RC-999999.' . $parts[2])->assertNotFound();
        $this->getJson('/api/public/groups/receipts/not-a-real-token-at-all-1234567')->assertNotFound();
        $this->get('/api/public/groups/receipts/' . $parts[0] . '.' . $parts[1] . '.' . str_repeat('0', 16), ['Accept' => 'text/html'])->assertNotFound()->assertSee('could not be verified', false);

        // A reversed payment still verifies as having existed, and says it was reversed.
        $this->api($this->people['treasurer'], 'POST', "/transactions/{$id}/reverse", ['reason' => 'Entered twice'])->assertOk();
        $this->flushHeaders();
        $this->getJson($path)->assertOk()->assertJsonPath('data.reversed', true);
    }
}
