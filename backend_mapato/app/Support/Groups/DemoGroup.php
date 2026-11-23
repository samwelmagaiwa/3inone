<?php

namespace App\Support\Groups;

use App\Models\Business;
use App\Models\User;
use App\Services\ServiceAssignment;
use App\Services\Sms\LogSmsGateway;
use App\Services\Sms\SmsGateway;
use App\Support\Tenancy\TenantContext;
use App\Support\Tenancy\TenantTables;
use Illuminate\Contracts\Http\Kernel as HttpKernel;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;

/**
 * A whole savings group (Vikundi) for showing the app to stakeholders: a business of its own (never mixed with a real one), an administrator,
 * twenty members with every detail filled in (address, NIDA, dependants, photo and ID, a referrer), the eight offices held, a year of monthly
 * contributions and savings paid by cash and mobile money (some late, some not yet), shares, loans in every state with guarantors and
 * repayments, welfare requests, assets hired out (one late, one damaged), projects with the committee's reviews and the chair's decisions,
 * expense requests paid and verified, a dividend run, meetings with minutes, resolutions and actions, notices and texts.
 *
 * Everything is made THROUGH THE APP'S OWN ENDPOINTS, with the clock set back to each day, so every figure is the one the app really works out
 * (balances, receipts, statements, the officers' dashboard) and the approval rules hold: nobody verifies their own payment, nobody decides their
 * own request. No SMS can leave: the gateway is replaced by one that only logs. The business is found again by its administrator's address (see
 * ADMIN_EMAIL), and {@see self::remove()} takes away exactly that business and nothing else.
 */
final class DemoGroup
{
    public const ADMIN_EMAIL = 'demo.admin@vikundi-demo.example';

    public const BUSINESS = 'Umoja wa Wajasiriamali Mikocheni (UWM)';

    private const TZ = 'Africa/Dar_es_Salaam';

    /** key => [name, gender, born, office, joined, referrer, occupation, monthly savings, reliability 0..1] */
    private const MEMBERS = [
        'juma' => ['Juma Hamisi Mrema', 'male', '1976-03-14', 'mwenyekiti', '2025-09-14', null, 'Mfanyabiashara wa vifaa vya ujenzi', 90000, 0.99],
        'rehema' => ['Rehema Salim Kimaro', 'female', '1981-07-02', 'makamu_mwenyekiti', '2025-09-14', 'juma', 'Mwalimu wa shule ya msingi', 70000, 0.97],
        'zawadi' => ['Zawadi Joseph Mollel', 'female', '1984-11-23', 'mweka_hazina', '2025-09-14', 'juma', 'Mhasibu', 80000, 1.0],
        'baraka' => ['Baraka Elias Mushi', 'male', '1990-01-30', 'mweka_hazina_msaidizi', '2025-09-21', 'zawadi', 'Karani wa benki', 50000, 0.96],
        'neema' => ['Neema Peter Swai', 'female', '1988-05-19', 'katibu', '2025-09-14', 'rehema', 'Afisa maendeleo ya jamii', 60000, 0.98],
        'hassan' => ['Hassan Omari Said', 'male', '1985-09-08', 'katibu_msaidizi', '2025-09-28', 'neema', 'Fundi umeme', 40000, 0.92],
        'daudi' => ['Daudi Emmanuel Lema', 'male', '1979-12-11', 'mwenyekiti_miradi', '2025-09-14', 'juma', 'Mkulima na mfugaji', 100000, 0.95],
        'mwajuma' => ['Mwajuma Ally Temba', 'female', '1983-04-27', 'kamati_miradi', '2025-10-05', 'daudi', 'Mjasiriamali wa vyakula', 45000, 0.94],
        'elias' => ['Elias John Massawe', 'male', '1987-08-16', 'kamati_miradi', '2025-10-05', 'daudi', 'Mhandisi wa ujenzi', 75000, 0.93],
        'asha' => ['Asha Mussa Juma', 'female', '1992-02-09', null, '2025-10-12', 'rehema', 'Mshonaji', 65000, 0.97],
        'joyce' => ['Joyce Peter Kileo', 'female', '1986-06-21', null, '2025-10-12', 'neema', 'Muuguzi', 55000, 0.9],
        'fatma' => ['Fatma Bakari Hassan', 'female', '1979-10-03', null, '2025-10-19', 'asha', 'Mama lishe', 30000, 0.85],
        'peter' => ['Peter Samson Mtui', 'male', '1982-12-29', null, '2025-10-19', 'elias', 'Dereva wa bodaboda', 25000, 0.78],
        'grace' => ['Grace Anthony Mwakalinga', 'female', '1994-03-05', null, '2025-11-02', 'joyce', 'Mfanyakazi wa saluni', 35000, 0.88],
        'amina' => ['Amina Rashid Shirima', 'female', '1989-09-17', null, '2025-11-02', 'asha', 'Muuza mitumba', 30000, 0.82],
        'said' => ['Said Rashid Mkumbo', 'male', '1975-01-12', null, '2025-11-09', 'hassan', 'Mwenyekiti wa mtaa', 60000, 0.9],
        'happiness' => ['Happiness Deogratius Urio', 'female', '1996-08-24', null, '2025-11-09', 'grace', 'Mhudumu wa hoteli', 20000, 0.8],
        'rajabu' => ['Rajabu Mohamed Kisanga', 'male', '1980-05-06', null, '2025-11-16', 'peter', 'Mchuuzi wa samaki', 20000, 0.55],
    ];

    /** The three who joined later through an application: key => [name, gender, born, occupation, referrer, applied month index, saving] */
    private const NEWCOMERS = [
        'upendo' => ['Upendo Isaya Mchome', 'female', '1991-04-18', 'Mwandishi wa hesabu', 'neema', 4, 40000],
        'frank' => ['Frank Gabriel Nyoni', 'male', '1987-10-07', 'Mhandisi wa kompyuta', 'elias', 5, 50000],
        'mariam' => ['Mariam Hamza Chuma', 'female', '1993-01-26', 'Daktari msaidizi', 'joyce', 6, 35000],
    ];

    /** Who is still waiting for approval: key => [name, gender, born, occupation, referrer] */
    private const APPLICANTS = [
        'anna' => ['Anna Method Kavishe', 'female', '1990-07-13', 'Mwalimu wa chekechea', 'asha'],
        'yusuph' => ['Yusuph Khamis Abdallah', 'male', '1984-02-21', 'Fundi seremala', 'hassan'],
        'tatu' => ['Tatu Saidi Mnyone', 'female', '1995-11-04', 'Mfanyabiashara wa mbogamboga', 'fatma'],
    ];

    /** region, district, ward, street */
    private const PLACES = [
        ['Dar es Salaam', 'Kinondoni', 'Mikocheni', 'Mikocheni B'], ['Dar es Salaam', 'Ilala', 'Kariakoo', 'Mtaa wa Mchikichi'],
        ['Dar es Salaam', 'Temeke', 'Chang\'ombe', 'Chang\'ombe A'], ['Dar es Salaam', 'Ubungo', 'Manzese', 'Midizini'],
        ['Dar es Salaam', 'Kigamboni', 'Kibada', 'Kibada Mjini'], ['Dar es Salaam', 'Kinondoni', 'Msasani', 'Msasani Bonde la Mpunga'],
        ['Pwani', 'Kibaha', 'Kibaha', 'Mailimoja'], ['Dar es Salaam', 'Ubungo', 'Sinza', 'Sinza Mori'],
    ];

    private const SURNAMES_PHONE = ['0712', '0713', '0714', '0715', '0752', '0754', '0755', '0762', '0765', '0767', '0784', '0788', '0621', '0657'];

    private const MONEY = ['cash' => 34, 'mpesa' => 30, 'mixx' => 14, 'airtel_money' => 9, 'halopesa' => 4, 'bank_transfer' => 9];

    private Carbon $end;

    private Carbon $start;

    private int $months;

    /** @var array<string, string> who => token */
    private array $tokens = [];

    /** @var array<string, int> member key => member id */
    private array $ids = [];

    /** @var array<string, string> member key => phone */
    private array $phones = [];

    /** @var array<string, bool> keys of members who pay (active, not suspended) */
    private array $paying = [];

    /** @var array<int, array<string, mixed>> loans being repaid */
    private array $loans = [];

    /** @var array<string, int> */
    private array $usedPhones = [];

    /** @var array<string, int> what was made */
    public array $made = ['members' => 0, 'payments' => 0, 'loans' => 0, 'welfare' => 0, 'assets' => 0, 'hires' => 0, 'projects' => 0, 'expenses' => 0, 'meetings' => 0, 'notices' => 0, 'documents' => 0, 'texts' => 0];

    public ?string $password = null;

    /** @var callable|null */
    private $progress = null;

    private int $typeJamii = 0;

    public function __construct(int $months = 12, int $seed = 2026, ?Carbon $today = null)
    {
        $this->months = max(12, min(18, $months));
        $this->end = ($today ?? Carbon::now(self::TZ))->copy()->setTimezone(self::TZ)->startOfDay();
        $this->start = $this->end->copy()->startOfMonth()->subMonths($this->months - 1);
        mt_srand($seed);
    }

    public function onProgress(callable $callback): self
    {
        $this->progress = $callback;

        return $this;
    }

    private function say(string $line): void
    {
        if ($this->progress !== null) {
            ($this->progress)($line);
        }
    }

    // ------------------------------------------------------------------------------------------------ the one door to the app

    /**
     * @param  array<string, mixed>  $body
     * @return array<string, mixed>
     */
    private function call(string $who, string $method, string $uri, array $body = [], ?Carbon $at = null, array $files = []): array
    {
        if ($at !== null) {
            Carbon::setTestNow($at);
        }
        TenantContext::reset();
        app('auth')->forgetGuards();
        GroupAccess::forget();
        $server = ['HTTP_AUTHORIZATION' => 'Bearer ' . $this->tokens[$who], 'HTTP_ACCEPT' => 'application/json', 'HTTP_X_SERVICE' => 'groups'];
        if ($files === []) {
            $server['CONTENT_TYPE'] = 'application/json';
        }
        $url = str_starts_with($uri, '/api/') ? $uri : '/api/groups' . $uri;
        $request = Request::create($url, $method, $method === 'GET' ? $body : ($files === [] ? [] : $body), [], $files, $server, $method === 'GET' || $files !== [] ? null : json_encode($body));
        $kernel = app(HttpKernel::class);
        $response = $kernel->handle($request);
        $json = json_decode((string) $response->getContent(), true);
        $kernel->terminate($request, $response);
        if ($response->getStatusCode() >= 400) {
            throw new \RuntimeException("{$method} {$uri} answered {$response->getStatusCode()}: " . mb_substr((string) $response->getContent(), 0, 400));
        }

        return is_array($json) ? $json : [];
    }

    /** A call that may be refused (the app's own rules): true when it went through. */
    private function tryCall(string $who, string $method, string $uri, array $body = [], ?Carbon $at = null): bool
    {
        try {
            $this->call($who, $method, $uri, $body, $at);

            return true;
        } catch (\RuntimeException) {
            return false;
        }
    }

    // ------------------------------------------------------------------------------------------------ small dice

    private function chance(float $p): bool
    {
        return mt_rand(0, 9999) / 10000 < $p;
    }

    private function between(int $a, int $b): int
    {
        return mt_rand($a, $b);
    }

    private function pick(array $list): mixed
    {
        return $list[mt_rand(0, count($list) - 1)];
    }

    private function method(): string
    {
        $r = mt_rand(1, array_sum(self::MONEY));
        foreach (self::MONEY as $m => $w) {
            $r -= $w;
            if ($r <= 0) {
                return $m;
            }
        }

        return 'cash';
    }

    private function ref(string $method): ?string
    {
        if ($method === 'cash') {
            return null;
        }
        $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789';
        $out = '';
        for ($i = 0; $i < 10; $i++) {
            $out .= $chars[mt_rand(0, strlen($chars) - 1)];
        }

        return $out;
    }

    private function phone(): string
    {
        do {
            $phone = $this->pick(self::SURNAMES_PHONE) . str_pad((string) $this->between(100000, 999999), 6, '0', STR_PAD_LEFT);
        } while (isset($this->usedPhones[$phone]));
        $this->usedPhones[$phone] = 1;

        return $phone;
    }

    private function nida(string $born): string
    {
        return str_replace('-', '', $born) . '-' . str_pad((string) $this->between(10000, 99999), 5, '0', STR_PAD_LEFT) . '-' . str_pad((string) $this->between(0, 99999), 5, '0', STR_PAD_LEFT) . '-' . $this->between(10, 99);
    }

    private function day(int $monthIndex, int $dom, int $hour = 10): Carbon
    {
        $first = $this->start->copy()->addMonths($monthIndex);
        $d = $first->copy()->day(min($dom, $first->daysInMonth))->setTime($hour, $this->between(0, 55));

        return $d->greaterThan($this->end->copy()->setTime(18, 0)) ? $this->end->copy()->subDay()->setTime($hour, 5) : $d;
    }

    private function isCurrent(int $monthIndex): bool
    {
        return $monthIndex === $this->months - 1;
    }

    // ------------------------------------------------------------------------------------------------ build

    /** @return array<string, mixed> what to tell the person */
    public function build(): array
    {
        app()->instance(SmsGateway::class, new LogSmsGateway());
        $this->password ??= $this->randomPassword();

        try {
            $this->admin();
            $this->say('Group rules, members, offices and sign-ins ...');
            $this->settings();
            $this->founders();
            $this->contributionTypes();
            $this->say('Month by month: contributions, savings, loans, hires ...');
            for ($i = 0; $i < $this->months; $i++) {
                $this->month($i);
            }
            $this->say('Applications, notices, texts, the current month ...');
            $this->finish();
        } finally {
            Carbon::setTestNow();
            TenantContext::reset();
            foreach (User::query()->withoutGlobalScopes()->whereIn('id', $this->demoUserIds())->get() as $u) {
                $u->tokens()->delete();
            }
        }

        return $this->summary();
    }

    private function randomPassword(): string
    {
        $chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        $out = '';
        for ($i = 0; $i < 12; $i++) {
            $out .= $chars[random_int(0, strlen($chars) - 1)];
        }

        return $out;
    }

    /** @return array<int, string> */
    private function demoUserIds(): array
    {
        $admin = User::query()->withoutGlobalScopes()->where('email', self::ADMIN_EMAIL)->first();
        if ($admin === null) {
            return [];
        }
        $ids = [(string) $admin->id];
        TenantContext::withoutScope(function () use (&$ids) {
            $ids = array_merge($ids, DB::table('group_members')->whereNotNull('user_id')->pluck('user_id')->map(fn ($v) => (string) $v)->all());
        });

        return $ids;
    }

    private function admin(): void
    {
        if (User::query()->withoutGlobalScopes()->where('email', self::ADMIN_EMAIL)->exists()) {
            throw new \RuntimeException('The demo group is already here. Remove it first (or use --fresh).');
        }
        Carbon::setTestNow($this->start->copy()->setTime(9, 0));
        $owner = User::create([
            'name' => 'Hadija Kombo', 'email' => self::ADMIN_EMAIL, 'password' => $this->password, 'phone_number' => '0700000201',
            'role' => 'admin', 'is_active' => true, 'phone_verified' => true, 'email_verified' => true,
        ]);
        $owner->services()->firstOrCreate(['service_type' => 'groups']);
        app(ServiceAssignment::class)->prepareServices($owner);
        Business::forOwnerId($owner->id)->update([
            'name' => self::BUSINESS, 'address' => 'Mikocheni B, Barabara ya Mwai Kibaki, Dar es Salaam', 'phone' => '0700000201',
            'email' => self::ADMIN_EMAIL, 'plan' => 'premium', 'valid_until' => now()->addYears(2),
        ]);
        $this->tokens['admin'] = $owner->createToken('demo')->plainTextToken;
    }

    private function settings(): void
    {
        $this->call('admin', 'PUT', '/settings', ['reason' => 'Masharti ya kikundi yaliyopitishwa na mkutano mkuu', 'values' => [
            'joining_fee' => 80000, 'share_amount' => 200000, 'shares_required_for' => 'loans', 'loan_multiplier' => 3, 'member_prefix' => 'UWM',
            'payment_instructions' => 'Lipa kwa M-Pesa namba 0754 100 200 (Umoja wa Wajasiriamali Mikocheni) au NMB akaunti 2051234567. Weka namba ya muamala kwenye malipo.',
            'sms_reminders' => 'on', 'sms_show_amounts' => 'off',
            'loan_interest_rate' => 2, 'loan_interest_method' => 'flat', 'loan_max_months' => 12, 'loan_guarantors' => 1, 'hire_days_rule' => 'both',
        ]], $this->start->copy()->setTime(9, 5));
    }

    // ------------------------------------------------------------------------------------------------ people

    private function memberBody(string $name, string $gender, string $born, string $occupation, int $i, ?int $referrer): array
    {
        [$region, $district, $ward, $street] = self::PLACES[$i % count(self::PLACES)];
        $first = strtolower(explode(' ', $name)[0]);

        return [
            'full_name' => $name, 'phone' => $this->phone(), 'alt_phone' => $this->phone(), 'email' => $first . '.' . strtolower(explode(' ', $name)[2] ?? 'uwm') . '@gmail.com',
            'nida' => $this->nida($born), 'date_of_birth' => $born, 'gender' => $gender, 'region' => $region, 'district' => $district, 'ward' => $ward, 'street' => $street,
            'occupation' => $occupation, 'referrer_id' => $referrer,
            'notes' => $this->pick(['Anapendelea kulipa kwa M-Pesa.', 'Mjumbe wa kamati ya harusi.', 'Anapatikana jioni baada ya kazi.', 'Ana duka dogo karibu na soko.', 'Alijiunga kwa mwaliko wa rafiki.', 'Anaweza kusaidia kuratibu vikao.']),
        ];
    }

    private function founders(): void
    {
        $i = 0;
        foreach (self::MEMBERS as $key => [$name, $gender, $born, $office, $joined, $ref, $occupation]) {
            $body = $this->memberBody($name, $gender, $born, $occupation, $i, $ref === null ? null : $this->ids[$ref]) + ['existing' => true, 'founding' => $i < 9, 'joined_on' => $joined];
            $id = (int) $this->call('admin', 'POST', '/members', $body, $this->start->copy()->setTime(9, 10 + $i))['data']['member']['id'];
            $this->ids[$key] = $id;
            $this->phones[$key] = $body['phone'];
            if ($office !== null) {
                $this->call('admin', 'PUT', "/members/{$id}/office", ['office' => $office, 'reason' => 'Alichaguliwa kwenye mkutano mkuu wa kwanza']);
            }
            $this->dependants($key, $id);
            $this->signIn($key, $id);
            $this->paying[$key] = true;
            $this->made['members']++;
            $i++;
        }
        $this->say(count(self::MEMBERS) . ' members with offices and sign-ins made.');

        // Their joining fee and shares were paid when they joined (the treasurer records it, the assistant verifies it).
        foreach (self::MEMBERS as $key => [, , , , $joined]) {
            $shares = in_array($key, ['peter', 'rajabu', 'happiness', 'amina', 'fatma'], true) ? 100000 : 200000;
            $this->pay($key, 'joining_fee', 80000, Carbon::parse($joined)->setTime(11, 0), 'officer', 'Ada ya kujiunga');
            $this->pay($key, 'shares', $shares, Carbon::parse($joined)->setTime(11, 15), 'officer', $shares < 200000 ? 'Hisa awamu ya kwanza' : 'Hisa zote');
        }
    }

    private function dependants(string $key, int $id): void
    {
        $n = $this->between(1, 3);
        $relations = [['spouse', 'Mwenza wa ndoa'], ['child', 'Mtoto'], ['child', 'Mtoto'], ['parent', 'Mzazi'], ['parent_in_law', 'Mzazi wa mwenza'], ['other', 'Ndugu']];
        $first = ['Amani', 'Baraka', 'Careen', 'Doreen', 'Emmanuel', 'Faraja', 'Glory', 'Hamisi', 'Imani', 'Joseph', 'Kelvin', 'Lucy', 'Mercy', 'Noel', 'Oliver', 'Prisca'];
        $surname = explode(' ', (self::MEMBERS[$key] ?? self::NEWCOMERS[$key] ?? ['Mwanachama Demo Mrema'])[0])[2] ?? 'Mrema';
        for ($d = 0; $d < $n; $d++) {
            [$rel] = $relations[($d + $this->between(0, 5)) % count($relations)];
            $born = match ($rel) {
                'child' => Carbon::now()->subYears($this->between(2, 17))->subDays($this->between(1, 300))->toDateString(),
                'parent', 'parent_in_law' => Carbon::now()->subYears($this->between(58, 78))->toDateString(),
                default => Carbon::now()->subYears($this->between(25, 50))->toDateString(),
            };
            $this->call('admin', 'POST', "/members/{$id}/dependants", [
                'name' => $this->pick($first) . ' ' . $surname, 'relationship' => $rel, 'phone' => $rel === 'child' ? null : $this->phone(),
                'date_of_birth' => $born, 'notes' => $rel === 'child' ? 'Anasoma shule ya msingi.' : 'Anaishi na familia.',
            ]);
        }
    }

    /** The member gets a sign-in; the demo password replaces the one-time one so the whole group signs in the same way. */
    private function signIn(string $key, int $id): void
    {
        $this->call('admin', 'POST', "/members/{$id}/sign-in");
        $userId = DB::table('group_members')->where('id', $id)->value('user_id');
        $user = User::query()->withoutGlobalScopes()->find($userId);
        $user->forceFill(['password' => Hash::make($this->password), 'must_change_password' => false, 'phone_verified' => true])->save();
        $this->tokens[$key] = $user->createToken('demo')->plainTextToken;
    }

    // ------------------------------------------------------------------------------------------------ money

    private function contributionTypes(): void
    {
        $at = $this->start->copy()->setTime(9, 40);
        $this->typeJamii = (int) $this->call('admin', 'POST', '/contribution-types', [
            'name' => 'JAMII (mchango wa kila mwezi)', 'description' => 'Mchango wa kila mwezi wa wanachama wote kwa ajili ya mfuko wa kikundi.', 'amount' => 20000,
            'frequency' => 'monthly', 'due_day' => 10, 'mandatory' => true, 'starts_on' => $this->start->toDateString(),
        ], $at)['data']['type']['id'];
        $this->call('admin', 'POST', '/contribution-types', [
            'name' => 'Msiba (rambirambi)', 'description' => 'Rambirambi ya papo kwa hapo wakati mwanachama au mwanafamilia anapofiwa.', 'amount' => 10000,
            'frequency' => 'event', 'mandatory' => true, 'starts_on' => $this->start->toDateString(),
        ], $at);
        $this->call('admin', 'POST', '/contribution-types', [
            'name' => 'Ada ya mwaka', 'description' => 'Ada ya mwaka ya uendeshaji wa kikundi.', 'amount' => 30000, 'frequency' => 'one_time', 'mandatory' => true,
            'starts_on' => $this->start->toDateString(),
        ], $at);
    }

    /**
     * One payment, recorded by the treasurer ('officer') or by the member from their phone ('self'), then verified by someone else.
     * Returns the transaction id (null when it was left waiting on purpose).
     */
    private function pay(string $key, string $category, float $amount, Carbon $at, string $via, ?string $note = null, array $extra = [], bool $verify = true): ?int
    {
        $method = $this->method();
        $body = ['category' => $category, 'amount' => $amount, 'method' => $method, 'external_ref' => $this->ref($method), 'paid_on' => $at->toDateString(), 'note' => $note] + $extra;
        if ($via === 'self') {
            $id = (int) $this->call($key, 'POST', '/me/payments', $body, $at)['data']['transaction']['id'];
        } else {
            $id = (int) $this->call('zawadi', 'POST', '/transactions', $body + ['member_id' => $this->ids[$key]], $at)['data']['transaction']['id'];
        }
        $this->made['payments']++;
        if ($verify) {
            $this->verify($id, $at->copy()->addMinutes($this->between(20, 240)));
        }

        return $id;
    }

    private function verify(int $id, Carbon $at): void
    {
        // The assistant treasurer verifies; when it is their own payment the treasurer does.
        // When it is the assistant's own payment and the treasurer recorded it, the administrator (who holds every right) does.
        if (!$this->tryCall('baraka', 'POST', "/transactions/{$id}/verify", [], $at) && !$this->tryCall('zawadi', 'POST', "/transactions/{$id}/verify", [], $at)) {
            $this->call('admin', 'POST', "/transactions/{$id}/verify", [], $at);
        }
    }

    private function obligation(string $key, int $typeId, string $period): ?int
    {
        $id = DB::table('group_obligations')->where('member_id', $this->ids[$key])->where('contribution_type_id', $typeId)->where('period', $period)->value('id');

        return $id === null ? null : (int) $id;
    }

    // ------------------------------------------------------------------------------------------------ one month

    private function month(int $i): void
    {
        $first = $this->start->copy()->addMonths($i);
        $period = $first->format('Y-m');
        $current = $this->isCurrent($i);

        // The treasurer raises the month's JAMII call on the 2nd.
        $this->call('zawadi', 'POST', "/contribution-types/{$this->typeJamii}/raise", ['month' => $period], $this->day($i, 2, 9));
        if ($i === 1) {
            $this->scenes1();
        }

        foreach ($this->paying as $key => $on) {
            if (!$on) {
                continue;
            }
            $profile = (self::MEMBERS[$key] ?? [])[8] ?? 0.9;
            $oid = $this->obligation($key, $this->typeJamii, $period);
            // JAMII: on time, late, or not yet (the current month is still open for many).
            $roll = mt_rand(0, 9999) / 10000;
            $onTime = $roll < $profile * ($current ? 0.55 : 1.0);
            $late = !$onTime && $roll < min(0.97, $profile + 0.08) * ($current ? 0.7 : 1.0);
            if ($oid !== null && ($onTime || $late)) {
                $dom = $onTime ? $this->between(3, 10) : $this->between(12, 27);
                $at = $this->day($i, $dom, $this->between(8, 18));
                if ($at->lessThanOrEqualTo($this->end->copy()->setTime(18, 0))) {
                    $amount = $this->chance(0.08) ? 10000 : 20000;
                    $left = $current && $this->chance(0.12);
                    $this->pay($key, 'contribution', $amount, $at, $this->chance(0.45) ? 'self' : 'officer', 'JAMII ' . $period, ['obligation_id' => $oid], !$left);
                    if ($amount === 10000 && $this->chance(0.7)) {
                        $this->pay($key, 'contribution', 10000, $at->copy()->addDays(5), 'officer', 'Salio la JAMII ' . $period, ['obligation_id' => $oid]);
                    }
                }
            }
            // Savings: most months, the member's own amount.
            if ($this->chance(0.9 * ($current ? 0.8 : 1.0))) {
                $at = $this->day($i, $this->between(11, 28), $this->between(8, 18));
                if ($at->lessThanOrEqualTo($this->end->copy()->setTime(18, 0))) {
                    $base = (self::MEMBERS[$key] ?? [])[7] ?? ((self::NEWCOMERS[$key] ?? [])[6] ?? 30000);
                    $this->pay($key, 'savings', round($base * $this->pick([0.5, 1, 1, 1, 1.5, 2]) / 1000) * 1000, $at, $this->chance(0.4) ? 'self' : 'officer', 'Akiba ya mwezi');
                }
            }
        }

        // Instalments of the loans that are running.
        $this->repayments($i);

        match (true) {
            $i === 2 => $this->scenes2(),
            $i === 3 => $this->scenes3(),
            $i === 4 => $this->scenes4(),
            $i === 5 => $this->scenes5(),
            $i === 6 => $this->scenes6(),
            $i === 7 => $this->scenes7(),
            $i === 8 => $this->scenes8(),
            $i === 9 => $this->scenes9(),
            $i === 10 => $this->scenes10(),
            default => null,
        };
        if ($i === $this->months - 1) {
            $this->scenesNow();
        }
    }

    // ------------------------------------------------------------------------------------------------ scenes (what happened when)
    // The scenes are tied to month numbers counted from the start, so the story holds whatever today is (at least 12 months are best).

    private function idx(int $fromEnd): int
    {
        return max(0, $this->months - 1 - $fromEnd);
    }

    private function scenes1(): void
    {
        $this->assets();
        $this->welfareTypes();
        $this->meeting($this->day(1, 17, 14), 'Mkutano Mkuu wa kwanza wa mwaka', "1. Kufungua mkutano\n2. Taarifa ya fedha\n3. Kupitisha masharti ya mikopo\n4. Kupanga ratiba ya vikao\n5. Mengineyo", 'Ukumbi wa Kanisa la Mikocheni B', true, [
            ['resolution', 'Riba ya mikopo iwe asilimia 2 kwa mwezi, mkopo usizidi miezi 12.', null, null],
            ['resolution', 'Kila mwanachama achangie JAMII shilingi 20,000 kabla ya tarehe 10 ya kila mwezi.', null, null],
            ['action', 'Mweka hazina afungue akaunti ya benki ya kikundi.', 'zawadi', $this->day(2, 10)->toDateString()],
            ['action', 'Katibu aandae katiba ya kikundi iwasilishwe kwa wanachama.', 'neema', $this->day(2, 28)->toDateString()],
        ], 'Mkutano ulianza saa 8:00 mchana, wanachama wengi walihudhuria. Mweka hazina alisoma taarifa ya fedha ya miezi mitatu ya kwanza. Mkutano ulipitisha riba ya mikopo, kiasi cha JAMII na ratiba ya vikao vya kila mwezi. Mkutano ulifungwa saa 10:30 jioni.');
        $this->announce('general', 'Karibu kwenye UWM', 'Tunawakaribisha wanachama wote. Malipo yote yafanyike kupitia namba rasmi ya kikundi na muamala uandikwe kwenye programu.', $this->day(1, 5), null);
    }

    private function scenes2(): void
    {
        $this->welfare('asha', 'Msiba', 'Baba mzazi', 'parent', $this->day(2, 8)->toDateString(), 'Baba yangu amefariki dunia mkoani Mbeya, tunahitaji msaada wa mazishi.', 300000, 'approve', $this->day(2, 9), $this->day(2, 11));
        $this->announce('bereavement', 'Pole kwa Asha Mussa', 'Tumepokea taarifa ya msiba wa baba mzazi wa mwanachama wetu Asha Mussa. Rambirambi zitolewe kupitia mchango wa Msiba.', $this->day(2, 8, 16), $this->day(2, 28)->toDateString());
    }

    private function scenes3(): void
    {
        $this->project('Ununuzi wa kiwanja cha kikundi', 'Kununua kiwanja kimoja Kibaha kwa ajili ya ofisi ya kikundi na mradi wa baadaye wa ujenzi wa kumbi za kukodisha.', 15000000, 'asha', 'approve', 3, 'completed');
        $this->loan('asha', 600000, 'Mtaji wa kuongeza mashine za kushonea', 6, $this->day(3, 5), 'disburse', 3);
        $this->meeting($this->day(3, 14, 14), 'Kikao cha mwezi Machi', "1. Taarifa ya fedha\n2. Mikopo iliyoombwa\n3. Mradi wa kiwanja", 'Ofisi ya Mwenyekiti, Mikocheni B', false, [
            ['resolution', 'Kamati ya miradi ianze mazungumzo na muuzaji wa kiwanja Kibaha.', null, null],
            ['action', 'Mwenyekiti wa miradi apeleke ripoti ya bei ya kiwanja kwenye kikao kijacho.', 'daudi', $this->day(4, 12)->toDateString()],
        ], 'Wajumbe 15 walihudhuria. Mkopo wa kwanza wa mwanachama umepitishwa. Kamati ya miradi imeagizwa kufuatilia kiwanja.');
    }

    private function scenes4(): void
    {
        $this->newcomers(4);
        $this->hire('TNT-01', 'asha', 2, 4, 'Harusi ya dada yangu', 4, 'return_ok');
        $this->loan('joyce', 400000, 'Kununua vifaa vya zahanati ndogo ya nyumbani', 4, $this->day(4, 9), 'disburse', 4);
    }

    private function scenes5(): void
    {
        $this->newcomers(5);
        $this->project('Mradi wa kuku wa mayai', 'Kujenga banda la kuku 500 wa mayai, kununua vifaranga, chakula na dawa kwa miezi mitatu ya kwanza.', 6000000, 'daudi', 'approve', 5, 'active');
        $this->hire('VT-01', 'peter', 60, 5, 'Sherehe ya kuzaliwa', 6, 'return_ok');
        $this->welfare('joyce', 'Ugonjwa', 'Mwenyewe', 'self', $this->day(5, 6)->toDateString(), 'Nilifanyiwa upasuaji mdogo hospitalini na nilihitaji msaada wa gharama.', 150000, 'approve', $this->day(5, 8), $this->day(5, 10));
        $this->announce('event', 'Siku ya kikundi', 'Tutakuwa na siku ya kikundi Jumamosi ya mwisho wa mwezi: michezo, chakula cha pamoja na kuelezea mipango ya mwaka.', $this->day(5, 12), $this->day(5, 28)->toDateString());
    }

    private function scenes6(): void
    {
        $this->newcomers(6);
        $this->loan('peter', 300000, 'Kununua pikipiki ya pili ya biashara', 6, $this->day(6, 7), 'disburse', 6);
        $this->hire('PA-01', 'neema', 1, 6, 'Mkutano wa kijiji', 2, 'return_ok');
        $this->expense('daudi', 'Ujenzi wa banda: mchanga, saruji na mbao', 'project', 'Mwanga Hardware Ltd', 1200000, 'approve', $this->day(6, 3), 'mpesa', 'Mradi wa kuku wa mayai');
        $this->expense('daudi', 'Ununuzi wa vifaranga 500', 'project', 'Kuku Bora Hatchery', 900000, 'approve', $this->day(6, 14), 'bank_transfer', 'Mradi wa kuku wa mayai');
        $this->meeting($this->day(6, 13, 14), 'Kikao cha mwezi Juni', "1. Maendeleo ya mradi wa kuku\n2. Maombi mapya ya wanachama\n3. Mikopo", 'Ukumbi wa Kanisa la Mikocheni B', false, [
            ['resolution', 'Banda la kuku likamilike kabla ya mwisho wa mwezi.', null, null],
            ['action', 'Mhandisi Elias atoe ripoti ya ubora wa banda.', 'elias', $this->day(6, 30)->toDateString()],
        ], 'Maendeleo ya mradi wa kuku yamepitiwa; fedha za vifaranga zimeidhinishwa. Wanachama wapya watatu wamepokelewa.');
    }

    private function scenes7(): void
    {
        $this->progress('Mradi wa kuku wa mayai', 45, 'Banda limekamilika, tunasubiri kuku wa kwanza.', $this->day(7, 6));
        $this->hire('TNT-01', 'fatma', 3, 7, 'Msiba nyumbani Chang\'ombe', 2, 'damage');
        $this->welfare('hassan', 'Harusi', 'Mwenyewe', 'self', $this->day(7, 12)->toDateString(), 'Harusi yangu ilifanyika wikendi iliyopita.', 100000, 'approve', $this->day(7, 14), $this->day(7, 16));
        $this->expense('neema', 'Karatasi, wino na kuchapisha fomu za wanachama', 'office', 'Mikocheni Stationery', 45000, 'approve', $this->day(7, 9), 'cash', null);
        $this->announce('contribution', 'Kumbusho la JAMII', 'Tafadhali lipa JAMII ya mwezi huu kabla ya tarehe 10 ili kuepuka kuingia kwenye orodha ya waliochelewa.', $this->day(7, 5), null);
    }

    private function scenes8(): void
    {
        $this->progress('Mradi wa kuku wa mayai', 70, 'Kuku 480 wameanza kutaga, mayai 300 kwa siku.', $this->day(8, 10));
        $this->loan('frank', 500000, 'Kununua kompyuta na printa kwa ofisi ya huduma', 6, $this->day(8, 4), 'reject', 8);
        $this->hire('JN-01', 'said', 1, 8, 'Mkutano wa mtaa', 1, 'return_ok');
        $this->meeting($this->day(8, 8, 14), 'Kikao cha mwezi Agosti', "1. Maendeleo ya miradi\n2. Mikopo iliyochelewa\n3. Maombi ya msaada", 'Ukumbi wa Kanisa la Mikocheni B', false, [
            ['resolution', 'Wenye mikopo iliyochelewa wapigiwe simu na mweka hazina kila wiki.', null, null],
            ['action', 'Katibu aandae orodha ya wanaodaiwa na aiwasilishe kwa mwenyekiti.', 'neema', $this->day(8, 20)->toDateString()],
        ], 'Mwenyekiti alisisitiza nidhamu ya malipo. Mradi wa kuku unaendelea vizuri.');
        $this->expense('baraka', 'Chai na maji kwa kikao cha Agosti', 'meeting', 'Mama Lishe Mikocheni', 80000, 'approve', $this->day(8, 9), 'cash', null);
    }

    private function scenes9(): void
    {
        $this->suspendRajabu();
        $this->project('Ununuzi wa mashine ya kusaga nafaka', 'Kununua mashine ya kusaga na kukoboa nafaka na kuiweka kwenye banda la kikundi ili kuuzia wananchi wa mtaa.', 8500000, 'mwajuma', 'review', 9, 'proposed');
        $this->project('Duka la pembejeo za kilimo', 'Kufungua duka la mbolea na mbegu Kibaha.', 4000000, 'said', 'reject', 9, 'rejected');
        $this->hire('TNT-01', 'zawadi', 2, 9, 'Sherehe ya kuhitimu', 2, 'return_ok');
        $this->expense('daudi', 'Chakula cha kuku na dawa — mwezi Septemba', 'project', 'AgroVet Kibaha', 650000, 'approve', $this->day(9, 7), 'mpesa', 'Mradi wa kuku wa mayai');
        $this->expense('juma', 'Usafiri wa mjumbe kwenda Kibaha kuona kiwanja', 'transport', 'Hamisi Bakari (dereva)', 120000, 'reject', $this->day(9, 15), 'cash', null);
    }

    private function scenes10(): void
    {
        $this->dividend();
        $this->loan('grace', 250000, 'Mtaji wa kununua bidhaa za saluni', 5, $this->day(10, 6), 'awaiting', 10);
        $this->meeting($this->day(10, 10, 14), 'Kikao cha mwezi Oktoba', "1. Mgao wa faida\n2. Mradi wa kusaga nafaka\n3. Kiwanja", 'Ukumbi wa Kanisa la Mikocheni B', false, [
            ['resolution', 'Mgao wa faida ufanyike mwezi Novemba kulingana na akiba ya kila mwanachama.', null, null],
            ['action', 'Mweka hazina aandae mapendekezo ya mgao.', 'zawadi', $this->day(10, 25)->toDateString()],
            ['action', 'Mwenyekiti wa miradi akusanye bei za mashine ya kusaga kutoka wauzaji watatu.', 'daudi', $this->day(10, 20)->toDateString()],
        ], 'Mkutano ulijadili mgao wa faida na mradi mpya wa mashine ya kusaga. Muhtasari wa kikao uko tayari kuidhinishwa na mwenyekiti.', false);
    }

    private function scenesNow(): void
    {
        $m = $this->months - 1;
        $this->loan('amina', 350000, 'Kununua mitumba ya msimu', 6, $this->day($m, 3), 'review', $m);
        $this->loan('said', 450000, 'Kukarabati duka la mtaa', 6, $this->day($m, 5), 'recommended', $m);
        $this->loan('upendo', 300000, 'Vifaa vya ofisi ya uhasibu', 5, $this->day($m, 8), 'approved', $m);
        $this->welfare('mwajuma', 'Kuzaliwa mtoto', 'Mtoto wangu mchanga', 'child', $this->day($m, 9)->toDateString(), 'Nimejifungua salama, nashukuru kikundi.', 50000, 'pending', $this->day($m, 10), null);
        $this->welfare('fatma', 'Msiba', 'Mama mkwe', 'parent_in_law', $this->day($m, 4)->toDateString(), 'Mama mkwe amefariki Morogoro.', 300000, 'reject', $this->day($m, 6), null);
        $this->hire('VT-01', 'happiness', 40, $m, 'Harusi ya kanisani', 3, 'late');
        $this->hire('MZ-01', 'grace', 10, $m, 'Kikao cha familia', 2, 'request');
        $this->project('Mradi wa kuku wa mayai', '', 0, 'daudi', 'progress', $m, 'active');
        $this->expense('daudi', 'Chanjo na dawa za kuku — Novemba', 'project', 'AgroVet Kibaha', 280000, 'pending', $this->day($m, 10), 'mpesa', 'Mradi wa kuku wa mayai');
        $this->expense('neema', 'Mafuta ya jenereta na matengenezo', 'office', 'Kituo cha Mafuta Mikocheni', 95000, 'approve-unpaid', $this->day($m, 11), 'cash', null);
    }

    // ------------------------------------------------------------------------------------------------ the rest of the story

    private function loan(string $key, float $want, string $purpose, int $term, Carbon $at, string $end, int $idx): void
    {
        $e = $this->call($key, 'GET', '/me/loan-eligibility', [], $at)['data'];
        if (!($e['eligible'] ?? true)) {
            // The shares are not all paid yet: the member tops them up first (it is what the group asks before a loan).
            $this->pay($key, 'shares', 100000, $at->copy()->subDays(2), 'officer', 'Hisa zilizobaki');
            $e = $this->call($key, 'GET', '/me/loan-eligibility', [], $at)['data'];
        }
        $ceiling = (float) $e['ceiling'];
        $amount = (float) floor(min($want, $ceiling) / 10000) * 10000;
        if ($amount < 10000) {
            $amount = 10000;
        }
        $guarantor = $this->guarantorFor($key);
        $loan = $this->call($key, 'POST', '/me/loans', ['amount' => $amount, 'purpose' => $purpose, 'term_months' => $term, 'guarantor_ids' => [$this->ids[$guarantor]]], $at)['data']['loan'];
        $id = (int) $loan['id'];
        $this->made['loans']++;
        if ($end === 'awaiting') {
            return;
        }
        $g = $this->guaranteeOf($guarantor, $id, $at->copy()->addHours(5));
        $this->call($guarantor, 'POST', "/guarantees/{$g}/respond", ['accept' => true, 'note' => 'Namjua vizuri, nadhamini.'], $at->copy()->addHours(6));
        if ($end === 'review') {
            return;
        }
        if ($end === 'reject') {
            $this->call('daudi', 'POST', "/loans/{$id}/reject", ['reason' => 'Akiba yake bado ni ndogo ukilinganisha na kiasi alichoomba; aombe tena baada ya miezi mitatu.'], $at->copy()->addDays(2));

            return;
        }
        $this->call('daudi', 'POST', "/loans/{$id}/recommend", ['amount' => $amount, 'note' => 'Ana rekodi nzuri ya malipo na mdhamini mzuri; napendekeza mkopo upitishwe.'], $at->copy()->addDays(2));
        if ($end === 'recommended') {
            return;
        }
        $this->call('juma', 'POST', "/loans/{$id}/approve", [], $at->copy()->addDays(3));
        if ($end === 'approved') {
            return;
        }
        $method = $this->pick(['mpesa', 'bank_transfer', 'cash']);
        $this->call('zawadi', 'POST', "/loans/{$id}/disburse", ['method' => $method, 'external_ref' => $this->ref($method), 'note' => 'Mkopo umetolewa'], $at->copy()->addDays(4));
        $tx = (int) DB::table('group_transactions')->where('loan_id', $id)->where('category', 'loan_disbursement')->orderByDesc('id')->value('id');
        $this->verify($tx, $at->copy()->addDays(4)->addHours(2));
        $this->loans[] = ['id' => $id, 'key' => $key, 'from' => $idx + 1, 'term' => $term, 'amount' => $amount, 'skip' => $key === 'peter' ? 2 : ($key === 'asha' ? 5 : 99)];
    }

    private function guarantorFor(string $key): string
    {
        foreach (['juma', 'rehema', 'daudi', 'said', 'elias', 'zawadi'] as $g) {
            if ($g !== $key) {
                return $g;
            }
        }

        return 'juma';
    }

    private function guaranteeOf(string $guarantor, int $loanId, Carbon $at): int
    {
        $rows = $this->call($guarantor, 'GET', '/me/loans', [], $at)['data']['guarantees'] ?? [];
        foreach ($rows as $r) {
            if ((int) ($r['loan_id'] ?? $r['loan']['id'] ?? 0) === $loanId) {
                return (int) $r['id'];
            }
        }

        return (int) ($rows[0]['id'] ?? 0);
    }

    /** Instalments: each month the borrower pays one instalment, except a borrower who has fallen behind. */
    private function repayments(int $i): void
    {
        foreach ($this->loans as $n => $l) {
            if ($i < $l['from'] || $i >= $l['from'] + $l['term'] || $i >= $l['from'] + $l['skip']) {
                continue;
            }
            $detail = $this->call('juma', 'GET', "/loans/{$l['id']}", [], $this->day($i, 15))['data']['loan'];
            $outstanding = (float) ($detail['position']['outstanding'] ?? 0);
            if ($outstanding <= 0) {
                continue;
            }
            $instalment = (float) ($detail['position']['instalment'] ?? ($detail['preview']['instalment'] ?? round($l['amount'] / $l['term'] * 1.1, -2)));
            $at = $this->day($i, $this->between(6, 14), 11);
            if ($at->greaterThan($this->end->copy()->setTime(18, 0))) {
                continue;
            }
            $this->pay($l['key'], 'loan_repayment', min($outstanding, max(1000, $instalment)), $at, 'self', 'Rejesho la mkopo', ['loan_id' => $l['id']]);
        }
    }

    private function welfareTypes(): void
    {
        $at = $this->day(1, 18);
        foreach ([['Msiba', 'Msaada wa mazishi kwa mwanachama au mwanafamilia wa karibu.', 300000], ['Harusi', 'Zawadi ya kikundi kwa mwanachama anayeoa au kuolewa.', 100000], ['Ugonjwa', 'Msaada wa matibabu kwa mwanachama aliyelazwa.', 150000], ['Kuzaliwa mtoto', 'Zawadi ya kikundi kwa mwanachama aliyejifungua.', 50000]] as [$name, $desc, $amount]) {
            $this->call('admin', 'POST', '/benefit-types', ['name' => $name, 'description' => $desc, 'amount' => $amount, 'active' => true], $at);
        }
    }

    private function benefitType(string $name): int
    {
        return (int) DB::table('group_benefit_types')->where('name', $name)->value('id');
    }

    private function welfare(string $key, string $type, string $beneficiary, string $relation, string $eventDate, string $description, float $amount, string $outcome, Carbon $decideAt, ?Carbon $payAt): void
    {
        $at = Carbon::parse($eventDate)->setTime(15, 0)->addDay();
        $id = (int) $this->call($key, 'POST', '/me/benefits', [
            'type_id' => $this->benefitType($type), 'beneficiary' => $beneficiary, 'relationship' => $relation, 'event_date' => $eventDate, 'description' => $description, 'amount' => $amount,
        ], $at)['data']['request']['id'];
        $this->made['welfare']++;
        if ($outcome === 'pending') {
            return;
        }
        if ($outcome === 'reject') {
            $this->call('juma', 'POST', "/benefits/{$id}/decide", ['approve' => false, 'note' => 'Hati ya kifo haijawasilishwa; tafadhali iwasilishe kisha uombe tena.'], $decideAt);

            return;
        }
        $this->call('juma', 'POST', "/benefits/{$id}/decide", ['approve' => true, 'amount' => $amount], $decideAt);
        if ($payAt !== null) {
            $method = $this->pick(['mpesa', 'cash']);
            $this->call('zawadi', 'POST', "/benefits/{$id}/pay", ['method' => $method, 'external_ref' => $this->ref($method)], $payAt);
            $tx = (int) DB::table('group_transactions')->where('category', 'welfare')->orderByDesc('id')->value('id');
            $this->verify($tx, $payAt->copy()->addHours(2));
        }
    }

    private function assets(): void
    {
        $at = $this->day(1, 8);
        $items = [
            ['TNT-01', 'Mahema ya sherehe (6)', 'Mahema', 6, 3600000, 'Stoo ya Katibu msaidizi, Mikocheni B', 'hassan', 25000, 10000, 'Mahema makubwa ya mita 6 kwa 12, yenye nguzo za chuma.'],
            ['VT-01', 'Viti vya plastiki', 'Viti', 200, 3000000, 'Stoo ya Kamati, Mikocheni B', 'elias', 300, 100, 'Viti vya plastiki vyeupe, vinakodishwa kwa siku.'],
            ['MZ-01', 'Meza za mikutano', 'Meza', 40, 2000000, 'Stoo ya Kamati, Mikocheni B', 'elias', 1500, 500, 'Meza za mraba za mbao ngumu.'],
            ['PA-01', 'Mfumo wa sauti (PA system)', 'Vifaa vya sauti', 1, 2500000, 'Nyumbani kwa Mweka hazina msaidizi', 'baraka', 60000, 20000, 'Spika 2, maikrofoni 3 na mixer ndogo.'],
            ['JN-01', 'Jenereta ya kW 5', 'Mitambo', 1, 1800000, 'Stoo ya Mwenyekiti', 'juma', 40000, 15000, 'Jenereta ya dizeli, inakodishwa pamoja na mafuta ya awali.'],
        ];
        foreach ($items as [$code, $name, $cat, $qty, $cost, $loc, $keeper, $rate, $late, $desc]) {
            $this->call('juma', 'POST', '/assets', [
                'code' => $code, 'name' => $name, 'category' => $cat, 'description' => $desc, 'quantity' => $qty, 'condition' => 'good', 'acquired_on' => $this->day(1, 3)->toDateString(),
                'cost' => $cost, 'location' => $loc, 'custodian_id' => $this->ids[$keeper], 'visible' => true, 'hire_rate' => $rate, 'late_rate' => $late,
            ], $at);
            $this->made['assets']++;
        }
        $jn = (int) DB::table('group_assets')->where('code', 'JN-01')->value('id');
        $this->call('juma', 'POST', "/assets/{$jn}/events", ['kind' => 'maintenance', 'cost' => 85000, 'note' => 'Service ya kawaida: mafuta ya injini na chujio.'], $this->day(1, 20));
    }

    /**
     * A hire from asking to closing. $how: return_ok | damage | late (issued, not yet back) | request (only asked).
     */
    private function hire(string $code, string $key, int $qty, int $idx, string $purpose, int $days, string $how): void
    {
        $asset = DB::table('group_assets')->where('code', $code)->first();
        $keeper = array_search((int) $asset->custodian_id, $this->ids, true);
        $startDay = $how === 'late' ? max(1, (int) $this->end->day - 12) : $this->between(18, 24);
        $startAt = $this->day($idx, $startDay, 9);
        $askAt = $startAt->copy()->subDays($this->between(3, 6));
        $hire = $this->call($key, 'POST', '/me/hires', [
            'asset_id' => (int) $asset->id, 'quantity' => $qty, 'start_date' => $startAt->toDateString(), 'end_date' => $startAt->copy()->addDays($days - 1)->toDateString(), 'purpose' => $purpose,
        ], $askAt)['data']['hire'];
        $id = (int) $hire['id'];
        $this->made['hires']++;
        if ($how === 'request') {
            return;
        }
        $this->call($keeper, 'POST', "/hires/{$id}/decide", ['approve' => true], $askAt->copy()->addHours(5));
        $total = (float) ($this->call($key, 'GET', '/me/hires', [], $askAt->copy()->addHours(6))['data']['hires'][0]['total'] ?? $asset->hire_rate * $qty * $days);
        $this->pay($key, 'hire', $total, $askAt->copy()->addDays(1), 'self', 'Malipo ya kukodi', ['hire_id' => $id]);
        $this->call($keeper, 'POST', "/hires/{$id}/issue", ['quantity' => $qty, 'condition' => 'Vizuri'], $startAt);
        if ($how === 'late') {
            return;
        }
        $endAt = $startAt->copy()->addDays($days - 1)->setTime(17, 0);
        if ($how === 'damage') {
            $this->call($keeper, 'POST', "/hires/{$id}/return", ['returned' => $qty - 1, 'damaged' => 1, 'missing' => 1, 'note' => 'Nguzo moja imepinda, bomba moja halijarudi.', 'returned_on' => $endAt->toDateString()], $endAt);
            $this->call('juma', 'POST', "/hires/{$id}/charge", ['amount' => 90000, 'note' => 'Nguzo iliyopinda (40,000) na bomba lililopotea (50,000).'], $endAt->copy()->addDay());
            $this->pay($key, 'hire', 90000, $endAt->copy()->addDays(2), 'self', 'Gharama za uharibifu', ['hire_id' => $id]);
        } else {
            $this->call($keeper, 'POST', "/hires/{$id}/return", ['returned' => $qty, 'damaged' => 0, 'missing' => 0, 'note' => 'Vimerudi vyote vikiwa salama.', 'returned_on' => $endAt->toDateString()], $endAt);
        }
        $this->call($keeper, 'POST', "/hires/{$id}/close", [], $endAt->copy()->addDays(3));
    }

    private function project(string $title, string $description, float $budget, string $by, string $outcome, int $idx, string $end): void
    {
        $at = $this->day($idx, 3, 9);
        if ($outcome === 'progress') {
            $pid = (int) DB::table('group_projects')->where('title', $title)->value('id');
            $this->call('daudi', 'POST', "/projects/{$pid}/progress", ['progress' => 85, 'note' => 'Kuku wanatoa mayai 420 kwa siku; tumeanza kuuza kwa wateja wa kudumu.'], $this->day($idx, 8));

            return;
        }
        $pid = (int) $this->call($by, 'POST', '/projects', [
            'title' => $title, 'description' => $description, 'budget' => $budget, 'start_date' => $at->copy()->addDays(10)->toDateString(), 'end_date' => $at->copy()->addMonths(6)->toDateString(),
        ], $at)['data']['project']['id'];
        $this->made['projects']++;
        $reviewers = array_values(array_filter(['daudi', 'mwajuma', 'elias'], fn ($k) => $k !== $by));
        if ($outcome === 'review') {
            $this->call($reviewers[0], 'POST', "/projects/{$pid}/review", ['supports' => true, 'note' => 'Mradi una soko la uhakika mtaani na unarudisha gharama ndani ya mwaka mmoja.'], $at->copy()->addDays(2));

            return;
        }
        if ($outcome === 'reject') {
            $this->call($reviewers[0], 'POST', "/projects/{$pid}/review", ['supports' => false, 'note' => 'Soko la pembejeo Kibaha lina washindani wengi; mtaji ni mkubwa kuliko faida.'], $at->copy()->addDays(2));
            $this->call('juma', 'POST', "/projects/{$pid}/decide", ['approve' => false, 'note' => 'Kamati haikuunga mkono; tuangalie tena mwaka ujao.'], $at->copy()->addDays(4));

            return;
        }
        foreach (array_slice($reviewers, 0, 2) as $r) {
            $this->call($r, 'POST', "/projects/{$pid}/review", ['supports' => true, 'note' => 'Napendekeza mradi uidhinishwe; bajeti inaonekana halisi.'], $at->copy()->addDays(2));
        }
        $this->call('juma', 'POST', "/projects/{$pid}/decide", ['approve' => true, 'note' => 'Umeidhinishwa kwa kauli ya kamati ya miradi.'], $at->copy()->addDays(4));
        $this->call('daudi', 'PUT', "/projects/{$pid}", ['manager_id' => $this->ids[$title === 'Mradi wa kuku wa mayai' ? 'elias' : 'daudi']], $at->copy()->addDays(5));
        $this->call('daudi', 'POST', "/projects/{$pid}/progress", ['progress' => 20, 'note' => 'Eneo limesafishwa na mafundi wamepatikana.'], $at->copy()->addDays(20));
        if ($end === 'completed') {
            $this->call('daudi', 'POST', "/projects/{$pid}/progress", ['progress' => 100, 'note' => 'Hati ya kiwanja imepatikana na imesajiliwa kwa jina la kikundi.'], $this->day($this->idx(1), 12));
            $this->call('daudi', 'POST', "/projects/{$pid}/close", ['outcome' => 'completed', 'note' => 'Mradi umekamilika; kiwanja kiko Kibaha, kina ukubwa wa ekari moja.'], $this->day($this->idx(1), 14));
        }
    }

    /** An expense request: $outcome approve (and pay) | reject | pending | approve-unpaid. */
    private function expense(string $by, string $purpose, string $category, string $payee, float $amount, string $outcome, Carbon $at, string $method, ?string $project): void
    {
        $projectId = $project === null ? null : (int) DB::table('group_projects')->where('title', $project)->value('id');
        $id = (int) $this->call($by, 'POST', '/expenses', ['purpose' => $purpose, 'category' => $category, 'payee' => $payee, 'amount' => $amount, 'project_id' => $projectId], $at)['data']['request']['id'];
        $this->made['expenses']++;
        if ($outcome === 'pending') {
            return;
        }
        $approver = $by === 'juma' ? 'rehema' : 'juma';
        if ($outcome === 'reject') {
            $this->call($approver, 'POST', "/expenses/{$id}/decide", ['approve' => false, 'note' => 'Gharama ni kubwa; tumia usafiri wa umma na uombe tena.'], $at->copy()->addDay());

            return;
        }
        $this->call($approver, 'POST', "/expenses/{$id}/decide", ['approve' => true, 'amount' => $amount, 'note' => 'Imeidhinishwa.'], $at->copy()->addDay());
        if ($outcome === 'approve-unpaid') {
            return;
        }
        $payer = $by === 'zawadi' ? 'baraka' : 'zawadi';
        $this->call($payer, 'POST', "/expenses/{$id}/pay", ['method' => $method, 'external_ref' => $this->ref($method)], $at->copy()->addDays(2));
        $tx = (int) DB::table('group_transactions')->where('expense_id', $id)->orderByDesc('id')->value('id');
        $this->verify($tx, $at->copy()->addDays(2)->addHours(3));
    }

    private function progress(string $title, int $percent, string $note, Carbon $at): void
    {
        $pid = (int) DB::table('group_projects')->where('title', $title)->value('id');
        $this->call('daudi', 'POST', "/projects/{$pid}/progress", ['progress' => $percent, 'note' => $note], $at);
    }

    private function dividend(): void
    {
        $at = $this->day($this->idx(1), 18);
        $run = $this->call('zawadi', 'POST', '/dividends', [
            'period_from' => $this->start->copy()->addMonths(1)->toDateString(), 'period_to' => $this->day($this->idx(2), 1)->endOfMonth()->toDateString(), 'profit_pool' => 2400000,
            'base' => 'average', 'method' => 'share', 'note' => 'Faida ya mradi wa kuku na mapato ya kukodisha mali, kama ilivyopitishwa kikaoni.',
        ], $at)['data']['run'];
        $this->call('juma', 'POST', '/dividends/' . (int) $run['id'] . '/post', [], $at->copy()->addDays(2));
    }

    /** Held (and optionally approved) meeting with minutes, resolutions and actions. */
    private function meeting(Carbon $startsAt, string $title, string $agenda, string $venue, bool $big, array $items, string $minutes, bool $approve = true): void
    {
        $called = $startsAt->copy()->subDays(7)->setTime(10, 0);
        $id = (int) $this->call('juma', 'POST', '/meetings', ['title' => $title, 'agenda' => $agenda, 'starts_at' => $startsAt->format('Y-m-d H:i:s'), 'venue' => $venue, 'notify' => true], $called)['data']['meeting']['id'];
        $present = [];
        foreach ($this->ids as $key => $mid) {
            if (isset($this->paying[$key]) && $this->paying[$key] && $this->chance($big ? 0.92 : 0.8)) {
                $present[] = $mid;
            }
        }
        $held = $startsAt->copy()->addHours(3);
        $this->call('neema', 'POST', "/meetings/{$id}/record", ['present_ids' => $present, 'minutes' => $minutes], $held);
        foreach ($items as [$kind, $text, $assignee, $due]) {
            $this->call('neema', 'POST', "/meetings/{$id}/items", ['kind' => $kind, 'text' => $text, 'assignee_id' => $assignee === null ? null : $this->ids[$assignee], 'due_date' => $due], $held->copy()->addMinutes(10));
        }
        $this->made['meetings']++;
        if (!$approve) {
            return;
        }
        $this->call('juma', 'POST', "/meetings/{$id}/approve-minutes", [], $held->copy()->addDays(3));
        // Some actions are done by their owner.
        foreach (DB::table('group_meeting_items')->where('meeting_id', $id)->where('kind', 'action')->get() as $n => $item) {
            if ($n % 2 === 0 && $item->assignee_member_id !== null) {
                $owner = array_search((int) $item->assignee_member_id, $this->ids, true);
                if ($owner !== false) {
                    $this->tryCall($owner, 'POST', "/meetings/{$id}/items/{$item->id}/done", [], $held->copy()->addDays(9));
                }
            }
        }
    }

    private function announce(string $category, string $title, string $body, Carbon $at, ?string $expires): void
    {
        $this->call('neema', 'POST', '/announcements', ['title' => $title, 'body' => $body, 'category' => $category, 'audience' => 'all', 'expires_on' => $expires], $at);
        $this->made['notices']++;
    }

    /** Three people applied through a member's code and were approved by the chair once their fees were verified. */
    private function newcomers(int $idx): void
    {
        foreach (self::NEWCOMERS as $key => [$name, $gender, $born, $occupation, $ref, $when, $saving]) {
            if ($when !== $idx) {
                continue;
            }
            $at = $this->day($idx, 4, 10);
            $code = $this->call($ref, 'GET', '/invitations', [], $at)['data']['mine']['code'];
            $this->publicApply($code, $key, $name, $gender, $born, $occupation, $ref, $at);
            $id = (int) DB::table('group_members')->where('phone', $this->phones[$key])->value('id');
            $this->ids[$key] = $id;
            $this->pay($key, 'joining_fee', 80000, $at->copy()->addDays(2), 'officer', 'Ada ya kujiunga');
            $this->pay($key, 'shares', 200000, $at->copy()->addDays(2)->addHours(1), 'officer', 'Hisa zote');
            $this->call('juma', 'POST', "/members/{$id}/status", ['action' => 'approve'], $at->copy()->addDays(4));
            $this->call('admin', 'PUT', "/members/{$id}", ['notes' => 'Amepokelewa kupitia mwaliko wa ' . self::MEMBERS[$ref][0] . '.', 'alt_phone' => $this->phone()], $at->copy()->addDays(4));
            $this->dependants($key, $id);
            $this->signIn($key, $id);
            $this->paying[$key] = true;
            $this->made['members']++;
        }
    }

    private function publicApply(string $code, string $key, string $name, string $gender, string $born, string $occupation, ?string $ref, Carbon $at): void
    {
        $body = $this->memberBody($name, $gender, $born, $occupation, count($this->phones), null);
        unset($body['referrer_id'], $body['notes']);
        Carbon::setTestNow($at);
        TenantContext::reset();
        app('auth')->forgetGuards();
        GroupAccess::forget();
        $request = Request::create("/api/public/groups/{$code}/apply", 'POST', [], [], [], ['HTTP_ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json'], json_encode($body + ['consent' => true]));
        $kernel = app(HttpKernel::class);
        $response = $kernel->handle($request);
        $kernel->terminate($request, $response);
        if ($response->getStatusCode() >= 400) {
            throw new \RuntimeException('Public apply answered ' . $response->getStatusCode() . ': ' . mb_substr((string) $response->getContent(), 0, 300));
        }
        $this->phones[$key] = $body['phone'];
    }

    private function suspendRajabu(): void
    {
        $this->paying['rajabu'] = false;
        $this->call('juma', 'POST', "/members/{$this->ids['rajabu']}/status", ['action' => 'suspend', 'reason' => 'Hajalipa JAMII kwa miezi mitatu mfululizo na hajapokea simu za viongozi.'], $this->day(9, 6));
    }

    // ------------------------------------------------------------------------------------------------ the present

    private function finish(): void
    {
        $now = $this->end->copy()->subDay()->setTime(15, 0);
        // Three people have applied and wait for the chair; one has paid the joining fee already.
        $applyDay = 0;
        foreach (self::APPLICANTS as $key => [$name, $gender, $born, $occupation, $ref]) {
            $at = $this->end->copy()->subDays(8 - $applyDay * 2)->setTime(11, 0);
            $applyDay++;
            $code = $this->call($ref, 'GET', '/invitations', [], $at)['data']['mine']['code'];
            $this->publicApply($code, $key, $name, $gender, $born, $occupation, $ref, $at);
            if ($key === 'anna') {
                $id = (int) DB::table('group_members')->where('phone', $this->phones[$key])->value('id');
                $this->ids[$key] = $id;
                $this->pay($key, 'joining_fee', 80000, $at->copy()->addDay(), 'officer', 'Ada ya kujiunga');
            }
        }

        // A few promises: one kept, one still due, one withdrawn; one excuse (udhuru) granted by the chair.
        $period = $this->end->format('Y-m');
        foreach ([['peter', 20000, 12, true], ['fatma', 20000, 6, false], ['amina', 20000, 2, null]] as [$key, $amount, $inDays, $keep]) {
            if (!$this->paying[$key]) {
                continue;
            }
            $oid = $this->obligation($key, $this->typeJamii, $period);
            if ($oid === null) {
                continue;
            }
            $pid = (int) $this->call($key, 'POST', '/me/promises', ['obligation_id' => $oid, 'amount' => $amount, 'promised_on' => $this->end->copy()->addDays($inDays)->toDateString(), 'note' => 'Nitalipa mshahara ukitoka.'], $now)['data']['promise']['id'];
            if ($keep === null) {
                $this->call($key, 'POST', "/promises/{$pid}/cancel", [], $now->copy()->addMinutes(10));
            }
        }
        foreach (['joyce', 'fatma', 'peter', 'amina', 'grace', 'happiness'] as $key) {
            $oid = $this->obligation($key, $this->typeJamii, $this->end->copy()->subMonths(2)->format('Y-m'));
            if ($oid !== null && $this->tryCall('juma', 'POST', "/obligations/{$oid}/exempt", ['reason' => 'Alilazwa hospitalini mwezi huo; kikundi kimemsamehe.'], $now)) {
                break;
            }
        }

        // A savings withdrawal by the treasurer, and a payment put right with a reversal.
        $w = $this->call('zawadi', 'POST', '/transactions', ['category' => 'savings', 'direction' => 'out', 'member_id' => $this->ids['said'], 'amount' => 100000, 'method' => 'mpesa', 'external_ref' => $this->ref('mpesa'), 'note' => 'Alitoa akiba ya ada ya shule', 'paid_on' => $now->toDateString()], $now)['data']['transaction']['id'];
        $this->verify((int) $w, $now->copy()->addHours(1));
        $wrong = (int) $this->call('zawadi', 'POST', '/transactions', ['category' => 'savings', 'member_id' => $this->ids['fatma'], 'amount' => 50000, 'method' => 'cash', 'note' => 'Akiba (imerekodiwa kimakosa)', 'paid_on' => $now->copy()->subDay()->toDateString()], $now->copy()->subDay())['data']['transaction']['id'];
        $this->verify($wrong, $now->copy()->subDay()->addHours(1));
        $this->call('zawadi', 'POST', "/transactions/{$wrong}/reverse", ['reason' => 'Ilirekodiwa kwa mwanachama asiye sahihi; imerudishwa kwa Fatma Bakari sahihi.'], $now);

        // Notices and texts, and a few members' own latest payments left waiting for the treasurer.
        $this->announce('meeting', 'Kikao cha kufunga mwaka', 'Kikao cha kufunga mwaka kitafanyika mwanzoni mwa Desemba. Wanachama wote mnaombwa kuhudhuria.', $now->copy()->subDays(3), $this->end->copy()->addDays(20)->toDateString());
        $this->announce('loan', 'Mikopo ya sikukuu', 'Maombi ya mikopo ya sikukuu yanapokelewa hadi tarehe 10 Desemba. Hakikisha mdhamini wako yuko tayari.', $now->copy()->subDays(2), $this->end->copy()->addDays(17)->toDateString());
        $this->announce('asset', 'Kukodisha mali kwa sikukuu', 'Mahema, viti na meza vinakodishwa kwa wanachama kwa bei ya kikundi. Weka oda mapema.', $now->copy()->subDays(1), null);
        $this->announce('emergency', 'Namba mpya ya malipo', 'Tahadhari: lipa kwa namba rasmi ya kikundi tu. Usimtumie mtu mwingine pesa za kikundi.', $now, null);
        $this->call('juma', 'POST', '/meetings', [
            'title' => 'Kikao cha kufunga mwaka', 'agenda' => "1. Taarifa ya mwaka\n2. Mgao wa faida\n3. Mipango ya mwaka ujao", 'starts_at' => $this->end->copy()->addDays(12)->setTime(14, 0)->format('Y-m-d H:i:s'),
            'venue' => 'Ukumbi wa Kanisa la Mikocheni B', 'notify' => true,
        ], $now->copy()->subDays(2));
        $this->made['meetings']++;
        try {
            $this->call('neema', 'POST', '/messages', ['audience' => 'overdue', 'body' => 'Ndugu mwanachama, JAMII ya mwezi huu bado haijalipwa. Tafadhali lipa kabla ya mwisho wa mwezi. Asante. UWM'], $now);
            $this->call('neema', 'POST', '/messages', ['audience' => 'all', 'body' => 'Habari wanachama wa UWM: kikao cha kufunga mwaka kitafanyika mwanzoni mwa Desemba. Karibuni sote.'], $now->copy()->subDays(1));
            $this->made['texts'] += 2;
        } catch (\RuntimeException $e) {
            $this->say('Texts were not made: ' . mb_substr($e->getMessage(), 0, 160));
        }
        $this->documents();
    }

    private function documents(): void
    {
        $png = base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
        $at = $this->end->copy()->subDays(10)->setTime(12, 0);
        // The officers who register members share the work (an upload is limited to 30 a minute for each person).
        $uploaders = ['neema', 'hassan', 'juma'];
        $n = 0;
        foreach ($this->ids as $key => $id) {
            foreach ([['photo', 'Picha ya pasipoti'], ['id', 'Kitambulisho cha NIDA']] as [$kind, $caption]) {
                $by = $uploaders[$n++ % count($uploaders)];
                $tmp = tempnam(sys_get_temp_dir(), 'demo');
                file_put_contents($tmp, $png);
                $file = new UploadedFile($tmp, $kind . '-' . $key . '.png', 'image/png', null, true);
                try {
                    $this->call($by, 'POST', "/members/{$id}/documents", ['kind' => $kind, 'caption' => $caption], $at, ['file' => $file]);
                    $this->made['documents']++;
                } catch (\RuntimeException $e) {
                    $this->say('A document was not stored: ' . mb_substr($e->getMessage(), 0, 120));

                    return;
                } finally {
                    @unlink($tmp);
                }
            }
        }
    }

    // ------------------------------------------------------------------------------------------------ what to tell

    /** @return array<string, mixed> */
    private function summary(): array
    {
        $people = [['role' => 'Administrator', 'name' => 'Hadija Kombo', 'login' => self::ADMIN_EMAIL]];
        foreach (self::MEMBERS as $key => $m) {
            $people[] = ['role' => $m[3] ?? 'Member', 'name' => $m[0], 'login' => $this->phones[$key] ?? ''];
        }
        foreach (self::NEWCOMERS as $key => $m) {
            $people[] = ['role' => 'Member', 'name' => $m[0], 'login' => $this->phones[$key] ?? ''];
        }

        return [
            'business' => self::BUSINESS,
            'from' => $this->start->toDateString(),
            'to' => $this->end->toDateString(),
            'made' => $this->made,
            'sign_in' => $people,
            'password' => $this->password,
        ];
    }

    // ------------------------------------------------------------------------------------------------ remove

    /** Takes away the demo group and nothing else. @return int how many rows went */
    public static function remove(): int
    {
        $owner = User::query()->withoutGlobalScopes()->where('email', self::ADMIN_EMAIL)->first();
        if ($owner === null) {
            return 0;
        }
        $ownerId = (string) $owner->id;
        $gone = 0;
        Schema::disableForeignKeyConstraints();
        TenantContext::withoutScope(function () use ($ownerId, &$gone) {
            $people = [$ownerId];
            if (Schema::hasTable('group_members')) {
                $people = array_merge($people, DB::table('group_members')->where(TenantTables::OWNER_COLUMN, $ownerId)->whereNotNull('user_id')->pluck('user_id')->map(fn ($v) => (string) $v)->all());
            }
            $pending = array_values(array_filter(TenantTables::GROUPS, fn (string $t) => Schema::hasTable($t) && Schema::hasColumn($t, TenantTables::OWNER_COLUMN)));
            for ($round = 0; $round < 12 && $pending !== []; $round++) {
                foreach ($pending as $i => $table) {
                    try {
                        $gone += DB::table($table)->where(TenantTables::OWNER_COLUMN, $ownerId)->delete();
                        unset($pending[$i]);
                    } catch (\Illuminate\Database\QueryException $e) {
                        if (!str_starts_with((string) $e->getCode(), '23')) {
                            throw $e;
                        }
                    }
                }
            }
            if ($pending !== []) {
                throw new \RuntimeException('Could not take away: ' . implode(', ', $pending));
            }
            DB::table('personal_access_tokens')->whereIn('tokenable_id', $people)->delete();
            if (Schema::hasTable('user_services')) {
                DB::table('user_services')->whereIn('user_id', $people)->delete();
            }
            $gone += DB::table('users')->whereIn('id', $people)->delete();
            if (Schema::hasTable('businesses')) {
                $gone += DB::table('businesses')->where('owner_id', $ownerId)->delete();
            }
        });
        Schema::enableForeignKeyConstraints();

        return $gone;
    }
}
