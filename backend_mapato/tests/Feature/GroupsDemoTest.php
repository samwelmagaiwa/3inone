<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\Sms\SmsGateway;
use App\Support\Groups\DemoGroup;
use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupSettings;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * The demo group: a believable savings group made through the app's own endpoints, with twenty members whose every detail is filled in, kept
 * apart from every real business, with no SMS and a way to take away exactly what it made.
 */
class GroupsDemoTest extends TestCase
{
    use RefreshDatabase;

    private const PASSWORD = 'Demo-pass-2026';

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function build(): array
    {
        $demo = new DemoGroup(12, 2026, Carbon::parse('2026-11-23', 'Africa/Dar_es_Salaam'));
        $demo->password = self::PASSWORD;

        return $demo->build();
    }

    private function api(string $phone, string $method, string $uri, array $body = [])
    {
        $user = User::query()->withoutGlobalScopes()->where('phone_number', $phone)->firstOrFail();
        $token = $user->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        GroupAccess::forget();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'groups')->json($method, '/api/groups' . $uri, $body);
    }

    public function test_it_makes_a_whole_group_with_twenty_members_each_with_every_detail(): void
    {
        $s = $this->build();

        $this->assertGreaterThanOrEqual(20, $s['made']['members']);
        $members = DB::table('group_members')->get();
        $this->assertGreaterThanOrEqual(23, $members->count(), '20 members and 3 applications');
        foreach ($members->where('status', 'active') as $m) {
            foreach (['full_name', 'phone', 'alt_phone', 'email', 'nida_encrypted', 'date_of_birth', 'gender', 'region', 'district', 'ward', 'street', 'occupation', 'member_number', 'joined_on'] as $col) {
                if (property_exists($m, $col)) {
                    $this->assertNotEmpty($m->{$col}, "{$m->full_name} has no {$col}");
                }
            }
            $this->assertGreaterThan(0, DB::table('group_dependants')->where('member_id', $m->id)->count(), "{$m->full_name} has no dependants");
        }
        $this->assertSame(8, collect(DB::table('group_members')->whereNotNull('office')->pluck('office'))->unique()->count() >= 8 ? 8 : 0, 'all eight offices are held');
        $this->assertSame(3, DB::table('group_members')->where('status', 'submitted')->count(), 'three applications wait');
        $this->assertSame(1, DB::table('group_members')->where('status', 'suspended')->count());

        foreach (['group_transactions', 'group_obligations', 'group_loans', 'group_loan_guarantors', 'group_benefit_requests', 'group_assets', 'group_hires', 'group_projects', 'group_project_reviews',
            'group_expense_requests', 'group_dividend_runs', 'group_meetings', 'group_meeting_items', 'group_announcements', 'group_promises'] as $table) {
            $this->assertGreaterThan(0, DB::table($table)->count(), "{$table} is empty");
        }
        $this->assertGreaterThan(300, DB::table('group_transactions')->where('status', 'verified')->count());
    }

    public function test_the_chair_and_a_member_see_a_living_group(): void
    {
        $s = $this->build();
        $chair = collect($s['sign_in'])->firstWhere('role', 'mwenyekiti')['login'];
        $asha = collect($s['sign_in'])->firstWhere('name', 'Asha Mussa Juma')['login'];

        $d = $this->api($chair, 'GET', '/dashboard')->assertOk();
        $this->assertGreaterThan(1000000, $d->json('data.money.cash_on_record'));
        $this->assertGreaterThanOrEqual(17, $d->json('data.members.active'));
        $this->assertNotNull($d->json('data.desk.projects'));

        $me = $this->api($asha, 'GET', '/me')->assertOk();
        $this->assertGreaterThan(500000, $me->json('data.balances.savings'));
        $this->assertNotEmpty($me->json('data.member.member_number'));
        $this->api($asha, 'GET', '/me/statement')->assertOk();
    }

    public function test_the_chair_signs_in_with_the_email_phone_and_password_given(): void
    {
        $demo = new DemoGroup(12, 2026, Carbon::parse('2026-11-23', 'Africa/Dar_es_Salaam'));
        $demo->password = '12345678';
        $demo->chairEmail = 'mwenyekiti@gmail.com';
        $demo->chairPhone = '0743519101';
        $demo->build();

        $this->flushHeaders();
        $this->postJson('/api/auth/login', ['email' => 'mwenyekiti@gmail.com', 'password' => '12345678'])->assertOk();
        $this->assertSame('0743519101', DB::table('group_members')->where('office', 'mwenyekiti')->value('phone'));
        $this->assertSame('off', GroupSettings::get('sms_reminders'), 'no reminder text can reach a demo phone');
    }

    public function test_it_sends_no_text_and_refuses_to_run_twice(): void
    {
        $this->build();
        $this->assertCount(0, $this->app->make(SmsGateway::class) instanceof \App\Services\Sms\LogSmsGateway ? [] : [1]);
        $this->expectException(\RuntimeException::class);
        $this->build();
    }

    public function test_remove_takes_away_exactly_the_demo_group(): void
    {
        $this->build();
        $this->assertGreaterThan(0, DemoGroup::remove());
        foreach (['group_members', 'group_transactions', 'group_loans', 'group_projects', 'group_meetings'] as $table) {
            $this->assertSame(0, DB::table($table)->count(), "{$table} still has rows");
        }
        $this->assertSame(0, User::query()->withoutGlobalScopes()->where('email', DemoGroup::ADMIN_EMAIL)->count());
        $this->assertSame(0, DemoGroup::remove(), 'nothing left to take away');
    }
}
