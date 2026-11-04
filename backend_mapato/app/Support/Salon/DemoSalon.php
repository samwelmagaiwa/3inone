<?php

namespace App\Support\Salon;

use App\Models\Business;
use App\Models\User;
use App\Services\ServiceAssignment;
use App\Services\Sms\LogSmsGateway;
use App\Services\Sms\SmsGateway;
use App\Support\Tenancy\TenantContext;
use App\Support\Tenancy\TenantTables;
use Illuminate\Contracts\Http\Kernel as HttpKernel;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * A whole salon for showing the app to someone: a business of its own (never mixed with a real one), an owner, an accountant and six stylists
 * with their own strengths, a few months of visits (busy Fridays and Saturdays, a payday rush, a growing star, one that slips, a newcomer
 * finding their feet), clients who come back, discounts, mobile-money and cash, a little credit, spending, salaries and commissions paid,
 * targets, equipment, bookings and feedback.
 *
 * Everything is made THROUGH THE APP'S OWN ENDPOINTS, with the clock set back to each day, so every figure is the one the app really works out
 * (stock, receipts, commissions, reports) and nothing is typed in by hand. No SMS can leave: the gateway is replaced by one that only logs.
 * The business is found again by its owner's address (see OWNER_EMAIL), and {@see self::remove()} takes away exactly that business and nothing else.
 */
final class DemoSalon
{
    public const OWNER_EMAIL = 'demo.owner@glowbeauty.example';

    public const BUSINESS = 'Glow Beauty Lounge';

    private const TZ = 'Africa/Dar_es_Salaam';

    /** name, price, minutes */
    private const SERVICES = [
        'Knotless braids' => [80000, 240], 'Box braids' => [60000, 210], 'Cornrows' => [25000, 90], 'Kids braids' => [18000, 90],
        'Weave installation' => [50000, 150], 'Relaxer' => [35000, 120], 'Wash & blow-dry' => [15000, 60], 'Hair treatment' => [30000, 60],
        'Kids haircut' => [8000, 30], 'Manicure' => [12000, 45], 'Pedicure' => [18000, 60], 'Gel nails' => [35000, 75], 'Nail art' => [15000, 45],
        'Lash extensions' => [45000, 90], 'Day makeup' => [35000, 60], 'Bridal makeup' => [120000, 120], 'Eyebrow threading' => [5000, 15],
    ];

    /** name, price, cost */
    private const GOODS = [
        'Hair growth oil' => [8000, 4500], 'Moisturising shampoo' => [12000, 7000], 'Edge control gel' => [6000, 3000],
        'Nail polish' => [5000, 2200], 'Hair extensions pack' => [25000, 17000], 'Leave-in conditioner' => [15000, 9000],
    ];

    /** key => name, role, skills (service => weight), salary, commission %, day off (1 = Monday ... 7 = Sunday), joins N days before the end (0 = from the start) */
    private const STAFF = [
        'asha' => ['Asha Juma', 'hair_stylist', ['Knotless braids' => 30, 'Box braids' => 25, 'Cornrows' => 20, 'Kids braids' => 10, 'Hair treatment' => 8, 'Wash & blow-dry' => 7], 300000, 30, 7, 0],
        'mwajuma' => ['Mwajuma Said', 'hair_stylist', ['Weave installation' => 30, 'Relaxer' => 20, 'Wash & blow-dry' => 25, 'Hair treatment' => 15, 'Cornrows' => 10], 300000, 28, 1, 0],
        'zawadi' => ['Zawadi Mollel', 'nail_technician', ['Manicure' => 30, 'Pedicure' => 28, 'Gel nails' => 30, 'Nail art' => 12], 250000, 25, 2, 0],
        'furaha' => ['Furaha Mtui', 'lash_makeup_artist', ['Lash extensions' => 30, 'Day makeup' => 35, 'Bridal makeup' => 8, 'Eyebrow threading' => 27], 280000, 30, 3, 0],
        'grace' => ['Grace Lema', 'hair_stylist', ['Kids braids' => 35, 'Cornrows' => 30, 'Wash & blow-dry' => 20, 'Kids haircut' => 15], 220000, 28, 7, 0],
        'salma' => ['Salma Hassan', 'hair_stylist', ['Weave installation' => 25, 'Wash & blow-dry' => 30, 'Box braids' => 20, 'Relaxer' => 15, 'Hair treatment' => 10], 200000, 25, 1, 50],
    ];

    private const FIRST = ['Neema', 'Rehema', 'Zainab', 'Fatma', 'Mwanaidi', 'Amina', 'Husna', 'Halima', 'Salma', 'Tumaini', 'Upendo', 'Witness', 'Grace', 'Joyce', 'Mariam', 'Asha', 'Eliza', 'Naomi', 'Beatrice', 'Happiness', 'Agnes', 'Veronica', 'Rose', 'Stella', 'Glory', 'Pendo', 'Faraja', 'Subira', 'Latifa', 'Mwajuma', 'Rukia', 'Sophia', 'Digna', 'Imelda', 'Catherine', 'Lilian', 'Mercy', 'Esther', 'Anna', 'Devotha'];

    private const LAST = ['Mushi', 'Kimaro', 'Mrema', 'Massawe', 'Swai', 'Lema', 'Mollel', 'Msuya', 'Temba', 'Mtui', 'Juma', 'Said', 'Hassan', 'Ally', 'Mohamed', 'Mwakyusa', 'Mwakalinga', 'Kileo', 'Shirima', 'Urio', 'Nyerere', 'Mkapa', 'Magesa', 'Sanga', 'Kayombo', 'Mbwambo', 'Kisanga', 'Nnko', 'Chacha', 'Maganga'];

    private const PREFIXES = ['0712', '0713', '0714', '0715', '0716', '0752', '0754', '0755', '0756', '0762', '0765', '0767', '0782', '0784', '0788', '0621', '0622', '0657', '0658'];

    private const PAYMENTS = ['cash' => 50, 'mpesa' => 22, 'mixx' => 12, 'airtel_money' => 7, 'halopesa' => 3, 'bank_transfer' => 6];

    private int $days;

    private Carbon $end;

    /** @var array<string, string> role-keyed tokens */
    private array $tokens = [];

    /** @var array<string, string> staff key => user id */
    private array $staffIds = [];

    /** @var array<string, int> service name => product id */
    private array $serviceIds = [];

    /** @var array<string, int> goods name => product id */
    private array $goodsIds = [];

    /** @var array<int, array<string, mixed>> */
    private array $clients = [];

    private array $usedPhones = [];

    /** @var array<string, int> what was made */
    public array $made = ['clients' => 0, 'sales' => 0, 'expenses' => 0, 'payouts' => 0, 'bookings' => 0, 'reviews' => 0, 'shifts' => 0, 'equipment' => 0];

    public float $revenue = 0.0;

    public ?string $password = null;

    /** @var callable|null */
    private $progress = null;

    public function __construct(int $days = 150, int $seed = 2026, ?Carbon $today = null)
    {
        $this->days = max(7, min(400, $days));
        $this->end = ($today ?? Carbon::now(self::TZ))->copy()->setTimezone(self::TZ)->startOfDay();
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

    /** @return array<string, mixed> */
    private function call(string $who, string $method, string $uri, array $body = [], ?Carbon $at = null): array
    {
        if ($at !== null) {
            Carbon::setTestNow($at);
        }
        TenantContext::reset();
        app('auth')->forgetGuards();
        $server = ['HTTP_AUTHORIZATION' => 'Bearer ' . $this->tokens[$who], 'HTTP_ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json', 'HTTP_X_SERVICE' => 'salon'];
        $request = Request::create($uri, $method, $method === 'GET' ? $body : [], [], [], $server, $method === 'GET' ? null : json_encode($body));
        $kernel = app(HttpKernel::class);
        $response = $kernel->handle($request);
        $json = json_decode((string) $response->getContent(), true);
        $kernel->terminate($request, $response);
        if ($response->getStatusCode() >= 400) {
            throw new \RuntimeException("{$method} {$uri} answered {$response->getStatusCode()}: " . mb_substr((string) $response->getContent(), 0, 300));
        }

        return is_array($json) ? $json : [];
    }

    // ------------------------------------------------------------------------------------------------ small dice

    private function chance(float $p): bool
    {
        return mt_rand(0, 9999) < $p * 10000;
    }

    /** @param array<string|int, int|float> $weights */
    private function weighted(array $weights): string|int
    {
        $total = array_sum($weights);
        $roll = mt_rand(0, max(1, (int) round($total * 1000)) - 1) / 1000;
        foreach ($weights as $key => $w) {
            if (($roll -= $w) < 0) {
                return $key;
            }
        }

        return array_key_last($weights);
    }

    private function pick(array $list): mixed
    {
        return $list[mt_rand(0, count($list) - 1)];
    }

    private function between(int $a, int $b): int
    {
        return mt_rand($a, $b);
    }

    // ------------------------------------------------------------------------------------------------ build

    /** Makes the whole salon. @return array<string, mixed> what to tell the person */
    public function build(): array
    {
        // Nothing may be sent to a real phone: the gateway only writes to the log.
        app()->instance(SmsGateway::class, new LogSmsGateway());
        $this->password = $this->password ?? $this->randomPassword();

        $start = $this->end->copy()->subDays($this->days);
        try {
            $this->people($start);
            $this->catalogue($start);
            $this->say('Visits, day by day ...');
            $this->visits($start);
            $this->say('Spending, pay, targets, equipment, bookings, feedback ...');
            $this->books($start);
            $this->targets();
            $this->equipment();
            $this->feedback($start);
            $this->bookings();
            $this->attendance();
        } finally {
            Carbon::setTestNow();
            TenantContext::reset();
            // The keys used to make the data are not kept: the people sign in with the password given.
            foreach (User::query()->where('email', 'like', '%@glowbeauty.example')->get() as $u) {
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

    private function phone(): string
    {
        do {
            $phone = $this->pick(self::PREFIXES) . str_pad((string) $this->between(0, 999999), 6, '0', STR_PAD_LEFT);
        } while (isset($this->usedPhones[$phone]));
        $this->usedPhones[$phone] = true;

        return $phone;
    }

    private function people(Carbon $start): void
    {
        if (User::query()->where('email', self::OWNER_EMAIL)->exists()) {
            throw new \RuntimeException('The demo salon is already here. Remove it first (or use --fresh).');
        }
        $owner = User::create([
            'name' => 'Neema Mushi', 'email' => self::OWNER_EMAIL, 'password' => $this->password, 'phone_number' => '0700000101',
            'role' => 'admin', 'is_active' => true, 'phone_verified' => true, 'email_verified' => true,
        ]);
        $this->bind($owner);
        Business::forOwnerId($owner->id)->update(['name' => self::BUSINESS, 'address' => 'Mikocheni B, Dar es Salaam', 'phone' => '0700000101', 'email' => self::OWNER_EMAIL, 'plan' => 'premium', 'valid_until' => now()->addYear()]);
        $this->tokens['owner'] = $owner->createToken('demo')->plainTextToken;

        $accountant = User::create(['name' => 'Rehema Kimaro', 'email' => 'demo.accountant@glowbeauty.example', 'password' => $this->password, 'phone_number' => '0700000102', 'role' => 'accountant', 'is_active' => true, 'created_by' => $owner->id, 'phone_verified' => true, 'email_verified' => true]);
        $this->bind($accountant);
        $this->tokens['accountant'] = $accountant->createToken('demo')->plainTextToken;

        $n = 3;
        foreach (self::STAFF as $key => [$name, $role]) {
            $u = User::create(['name' => $name, 'email' => 'demo.' . $key . '@glowbeauty.example', 'password' => $this->password, 'phone_number' => '07000001' . str_pad((string) $n++, 2, '0', STR_PAD_LEFT), 'role' => $role, 'is_active' => true, 'created_by' => $owner->id, 'phone_verified' => true, 'email_verified' => true]);
            $this->bind($u);
            $this->staffIds[$key] = (string) $u->id;
        }
        $this->say('Owner, accountant and six stylists made.');
    }

    private function bind(User $user): void
    {
        $user->services()->firstOrCreate(['service_type' => 'salon']);
        app(ServiceAssignment::class)->prepareServices($user);
    }

    private function catalogue(Carbon $start): void
    {
        $at = $start->copy()->subDays(2)->setTime(8, 0);
        foreach (self::SERVICES as $name => [$price, $minutes]) {
            $this->serviceIds[$name] = (int) $this->call('owner', 'POST', '/api/inventory/products', [
                'name' => $name, 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => $price, 'duration_minutes' => $minutes,
            ], $at)['data']['id'];
        }
        foreach (self::GOODS as $name => [$price, $cost]) {
            $this->goodsIds[$name] = (int) $this->call('owner', 'POST', '/api/inventory/products', [
                'name' => $name, 'sku' => strtoupper(substr(preg_replace('/[^A-Za-z]/', '', $name), 0, 5)) . $this->between(100, 999), 'quantity' => 400, 'min_stock' => 20, 'status' => 'active', 'cost_price' => $cost, 'selling_price' => $price,
            ], $at)['data']['id'];
        }
        // How each person is paid, and the days they work.
        foreach (self::STAFF as $key => [$name, , , $salary, $commission, $off]) {
            $this->call('owner', 'PUT', '/api/inventory/salon/staff-profiles/' . $this->staffIds[$key], [
                'monthly_salary' => $salary, 'commission_percent' => $commission, 'work_days' => array_values(array_diff([1, 2, 3, 4, 5, 6, 7], [$off])),
                'shift_start' => '08:30', 'shift_end' => '18:30',
            ], $at);
        }
        $this->say(count(self::SERVICES) . ' services, ' . count(self::GOODS) . ' goods, pay set.');
    }

    // ------------------------------------------------------------------------------------------------ the visits

    /** How busy a day is: the weekday, the payday rush at month end, the first week, and the shop growing over time. */
    private function visitsOn(Carbon $day, float $t): int
    {
        $base = [1 => 7, 2 => 8, 3 => 8, 4 => 9, 5 => 13, 6 => 19, 7 => 6][$day->dayOfWeekIso];
        $month = $day->day >= 25 ? 1.25 : ($day->day <= 7 ? 1.1 : 1.0);

        return max(2, (int) round($base * $month * (0.85 + 0.35 * $t) * (mt_rand(75, 125) / 100)));
    }

    /** How much of its best a stylist is on a given day: a rising star, one that slips, a newcomer ramping up, the rest steady. */
    private function form(string $key, float $t, int $daysBeforeEnd): float
    {
        return match ($key) {
            'asha' => 0.75 + 0.6 * $t,
            'grace' => 1.15 - 0.5 * $t,
            'salma' => $daysBeforeEnd > 50 ? 0.0 : 0.3 + 0.6 * ((50 - $daysBeforeEnd) / 50),
            'zawadi' => 1.05,
            'furaha' => 0.95,
            default => 1.0,
        };
    }

    private function working(string $key, Carbon $day, int $daysBeforeEnd): bool
    {
        [, , , , , $off, $joins] = self::STAFF[$key];

        return $day->dayOfWeekIso !== $off && ($joins === 0 || $daysBeforeEnd <= $joins);
    }

    private function visits(Carbon $start): void
    {
        for ($d = 0; $d < $this->days; $d++) {
            $day = $start->copy()->addDays($d);
            $t = $d / max(1, $this->days - 1);
            $before = $this->days - $d;
            for ($i = 0, $n = $this->visitsOn($day, $t); $i < $n; $i++) {
                $at = $day->copy()->setTime($this->between(9, 18), $this->between(0, 59), $this->between(0, 59));
                try {
                    $this->oneVisit($day, $at, $t, $before);
                } catch (\RuntimeException $e) {
                    // A visit that cannot be recorded (a rule of the app) is skipped, never made up around it.
                    $this->say('skipped one visit: ' . mb_substr($e->getMessage(), 0, 120));
                }
            }
            if ($d % 15 === 14) {
                $this->say(sprintf('  %s  %d visits so far, TSh %s', $day->toDateString(), $this->made['sales'], number_format($this->revenue)));
            }
        }
    }

    private function oneVisit(Carbon $day, Carbon $at, float $t, int $daysBeforeEnd): void
    {
        $client = $this->clientFor($day, $at);
        $preferred = $client['pref'] ?? null;
        $key = $preferred !== null && $this->working($preferred, $day, $daysBeforeEnd) && $this->chance(0.75) ? $preferred : $this->stylistFor($day, $t, $daysBeforeEnd);
        $lines = [];
        $services = $this->weighted(self::STAFF[$key][2]);
        $lines[] = ['svc' => (string) $services, 'key' => $key];
        // Sometimes a second service, often by someone else (hair and nails).
        if ($this->chance(0.28)) {
            $key2 = $this->chance(0.5) ? $key : $this->stylistFor($day, $t, $daysBeforeEnd);
            $second = (string) $this->weighted(self::STAFF[$key2][2]);
            if ($second !== $lines[0]['svc'] || $key2 !== $key) {
                $lines[] = ['svc' => $second, 'key' => $key2];
            }
        }

        $items = [];
        $subtotal = 0;
        foreach ($lines as $l) {
            $price = self::SERVICES[$l['svc']][0];
            $items[] = ['product_id' => $this->serviceIds[$l['svc']], 'quantity' => 1, 'unit_price' => $price, 'staff_id' => $this->staffIds[$l['key']]];
            $subtotal += $price;
        }
        if ($this->chance(0.16)) {
            $g = (string) $this->pick(array_keys(self::GOODS));
            $items[] = ['product_id' => $this->goodsIds[$g], 'quantity' => 1, 'unit_price' => self::GOODS[$g][0]];
            $subtotal += self::GOODS[$g][0];
        }

        $discount = 0;
        $reason = null;
        if ($this->chance(0.08) && $subtotal >= 20000) {
            $discount = (int) (round($subtotal * $this->pick([0.05, 0.1, 0.1, 0.15]) / 500) * 500);
            $reason = $this->pick(['Regular client', 'Birthday offer', 'Referred a friend', 'Bridal package']);
        }
        $total = $subtotal - $discount;
        $body = ['payment_status' => 'paid', 'subtotal' => $subtotal, 'discount' => $discount, 'tax' => 0, 'total' => $total, 'paid_total' => $total, 'items' => $items];
        if ($reason !== null) {
            $body['discount_reason'] = $reason;
        }
        if ($client['id'] !== null) {
            $body['customer_id'] = $client['id'];
        }

        $method = (string) $this->weighted(self::PAYMENTS);
        if ($client['id'] !== null && $this->chance(0.06)) {
            // Some clients pay later: a part now, or nothing yet.
            $part = $this->chance(0.6) ? (int) (round($total * $this->pick([0.4, 0.5, 0.6]) / 1000) * 1000) : 0;
            $body['payment_status'] = $part > 0 ? 'partial' : 'debt';
            $body['paid_total'] = $part;
            $body['due_date'] = $day->copy()->addDays($this->between(7, 14))->toDateString();
            $body['payments'] = $part > 0 ? [['amount' => $part, 'method' => $method, 'paid_at' => $at->format('Y-m-d H:i:s')]] : [];
        } else {
            $body['payments'] = [['amount' => $total, 'method' => $method, 'paid_at' => $at->format('Y-m-d H:i:s')]];
        }

        $this->call('owner', 'POST', '/api/inventory/sales', $body, $at);
        $this->made['sales']++;
        $this->revenue += $total;
        if ($client['id'] !== null) {
            $idx = $client['idx'];
            $this->clients[$idx]['last'] = $day->copy();
        }
    }

    private function stylistFor(Carbon $day, float $t, int $daysBeforeEnd): string
    {
        $weights = [];
        foreach (array_keys(self::STAFF) as $key) {
            if ($this->working($key, $day, $daysBeforeEnd)) {
                $weights[$key] = max(0.05, $this->form($key, $t, $daysBeforeEnd)) * (1 + 0.1 * (count(self::STAFF[$key][2]) - 4));
            }
        }

        return (string) $this->weighted($weights ?: ['asha' => 1]);
    }

    /** Who comes: a client who is due again, a new one (saved when first seen), or a walk-in who gives no name. @return array{id: ?int, idx: ?int, pref: ?string} */
    private function clientFor(Carbon $day, Carbon $at): array
    {
        $due = [];
        foreach ($this->clients as $idx => $c) {
            if ($c['last'] !== null && $c['last']->copy()->addDays($c['every'])->lte($day->copy()->addDays($this->between(-4, 6)))) {
                $due[] = $idx;
            }
        }
        $roll = mt_rand(1, 100);
        if ($due !== [] && $roll <= 60) {
            $idx = $this->pick($due);

            return ['id' => $this->clients[$idx]['id'], 'idx' => $idx, 'pref' => $this->clients[$idx]['pref']];
        }
        if ($roll <= 92) {
            $name = ($this->chance(0.35) ? $this->pick(['Mama ', 'Bi ', 'Dada ']) : '') . $this->pick(self::FIRST) . ' ' . $this->pick(self::LAST);
            $phone = $this->phone();
            $id = (int) $this->call('owner', 'POST', '/api/inventory/customers', ['name' => $name, 'phone' => $phone], $at)['data']['id'];
            $pref = $this->chance(0.7) ? (string) $this->pick(array_keys(self::STAFF)) : null;
            // How often they come: some every week or two, most every month or so, some only now and then.
            $every = (int) $this->weighted([10 => 12, 18 => 26, 30 => 38, 55 => 24]);
            $this->clients[] = ['id' => $id, 'name' => $name, 'pref' => $pref, 'every' => $every, 'last' => null];
            $this->made['clients']++;
            $idx = array_key_last($this->clients);

            return ['id' => $id, 'idx' => $idx, 'pref' => $pref];
        }

        return ['id' => null, 'idx' => null, 'pref' => null];
    }

    // ------------------------------------------------------------------------------------------------ the books

    private function books(Carbon $start): void
    {
        $at = fn (Carbon $d) => $d->copy()->setTime(10, 0);
        $expense = function (Carbon $day, string $category, string $text, int $amount, string $method = 'cash') use ($at): void {
            if ($day->gt($this->end)) {
                return;
            }
            $this->call('owner', 'POST', '/api/inventory/expenses', ['category' => $category, 'description' => $text, 'amount' => $amount, 'expense_date' => $day->toDateString(), 'payment_method' => $method], $at($day));
            $this->made['expenses']++;
        };
        $monthStart = $start->copy()->startOfMonth();
        for ($m = $monthStart->copy(); $m->lte($this->end); $m->addMonth()) {
            $label = $m->format('F');
            $expense($m->copy()->day(1)->max($start), 'rent', "Shop rent - {$label}", 1200000, 'bank_transfer');
            $expense($m->copy()->day(5)->max($start), 'utilities', "LUKU electricity - {$label}", $this->between(180, 260) * 1000, 'mpesa');
            $expense($m->copy()->day(6)->max($start), 'utilities', "Water bill - {$label}", $this->between(45, 70) * 1000, 'mpesa');
            $expense($m->copy()->day(8)->max($start), 'utilities', "Internet - {$label}", 60000, 'airtel_money');
            $expense($m->copy()->day(10)->max($start), 'marketing', "Instagram and flyers - {$label}", $this->between(60, 110) * 1000, 'mpesa');
            $expense($m->copy()->day(15)->max($start), 'maintenance', 'Repairs and cleaning materials', $this->between(30, 90) * 1000, 'cash');
        }
        for ($d = $start->copy()->next(\Carbon\Carbon::MONDAY); $d->lte($this->end); $d->addWeek()) {
            $expense($d->copy()->addDays(1), 'supplies', 'Hair, shampoo and nail supplies', $this->between(220, 420) * 1000, $this->pick(['cash', 'mpesa']));
            $expense($d->copy()->addDays(2), 'transport', 'Transport and bodaboda for deliveries', $this->between(25, 45) * 1000, 'cash');
        }
        $expense($start->copy()->addDays(3), 'licences', 'Business licence', 120000, 'bank_transfer');

        // Pay: the salaries on the 28th for every month that has ended, and each month's commission in the first days of the next.
        for ($m = $monthStart->copy(); $m->lt($this->end->copy()->startOfMonth()); $m->addMonth()) {
            $this->payMonth($m->copy(), $start);
        }
        $this->call('owner', 'PUT', '/api/inventory/monthly-target', ['month' => $this->end->format('Y-m'), 'profit_target' => $this->profitTarget()], $this->end->copy()->setTime(9, 0));
        $this->say("{$this->made['expenses']} expenses and {$this->made['payouts']} payments to staff.");
    }

    private function payMonth(Carbon $month, Carbon $start): void
    {
        $period = $month->format('Y-m');
        $salaryDay = $month->copy()->day(min(28, $month->daysInMonth));
        $commissionDay = $month->copy()->addMonth()->day(5);
        if ($salaryDay->lt($start) || $commissionDay->gt($this->end)) {
            return;
        }
        foreach (self::STAFF as $key => [$name, , , $salary]) {
            // A newcomer is only paid for the months they were here.
            $joins = self::STAFF[$key][6];
            if ($joins > 0 && $this->end->copy()->subDays($joins)->gt($month->copy()->endOfMonth())) {
                continue;
            }
            $this->call('owner', 'POST', '/api/inventory/salon/payouts', ['staff_id' => $this->staffIds[$key], 'kind' => 'salary', 'amount' => $salary, 'paid_on' => $salaryDay->toDateString(), 'period_month' => $period, 'method' => 'bank_transfer', 'note' => 'Monthly salary'], $salaryDay->copy()->setTime(15, 0));
            $this->made['payouts']++;
        }
        // The commission each earned is what the app itself works out for the month.
        $payroll = $this->call('owner', 'GET', '/api/inventory/salon/payroll', ['month' => $period], $commissionDay->copy()->setTime(9, 30))['data'] ?? [];
        foreach ($payroll['staff'] ?? [] as $row) {
            $owed = (float) ($row['commission_earned'] ?? 0) - (float) ($row['commission_paid'] ?? 0);
            if ($owed >= 1000) {
                $this->call('owner', 'POST', '/api/inventory/salon/payouts', ['staff_id' => (string) $row['staff_id'], 'kind' => 'commission', 'amount' => round($owed), 'paid_on' => $commissionDay->toDateString(), 'period_month' => $period, 'method' => 'mpesa', 'note' => 'Commission for ' . $month->format('F')], $commissionDay->copy()->setTime(15, 30));
                $this->made['payouts']++;
            }
        }
    }

    private function profitTarget(): int
    {
        return (int) (round($this->revenue / max(1, $this->days / 30) * 0.35 / 100000) * 100000);
    }

    /** A target for this month and the last, a little above what each did the month before it. */
    private function targets(): void
    {
        foreach ([$this->end->copy()->subMonthNoOverflow()->startOfMonth(), $this->end->copy()->startOfMonth()] as $month) {
            $before = $month->copy()->subMonthNoOverflow();
            $asOf = $before->copy()->endOfMonth();
            $report = $this->call('owner', 'GET', '/api/inventory/salon/stylists', ['from' => $before->toDateString(), 'to' => $asOf->toDateString()], $this->end->copy()->setTime(9, 0));
            $targets = [];
            foreach ($report['data']['stylists'] ?? [] as $r) {
                if (!empty($r['staff_id']) && (float) $r['revenue'] > 0) {
                    $targets[] = ['staff_id' => (string) $r['staff_id'], 'revenue_target' => (int) (round((float) $r['revenue'] * 1.1 / 10000) * 10000)];
                }
            }
            if ($targets !== []) {
                $this->call('owner', 'PUT', '/api/inventory/salon/stylist-targets', ['month' => $month->format('Y-m'), 'targets' => $targets], $this->end->copy()->setTime(9, 5));
            }
        }
    }

    private function equipment(): void
    {
        $at = $this->end->copy()->setTime(9, 0);
        $rows = [
            ['Hood dryer (Gold)', 'dryer', 450000, 400, $this->end->copy()->addDays(9)], ['Hood dryer (Silver)', 'dryer', 380000, 300, $this->end->copy()->subDays(4)],
            ['Hair steamer', 'steamer', 260000, 250, $this->end->copy()->addDays(40)], ['Styling chairs (6)', 'furniture', 1800000, 500, null],
            ['Nail UV lamp', 'nails', 120000, 200, $this->end->copy()->addDays(20)], ['Sterilizer cabinet', 'hygiene', 210000, 350, $this->end->copy()->addDays(3)],
        ];
        foreach ($rows as [$name, $kind, $cost, $age, $next]) {
            $this->call('owner', 'POST', '/api/inventory/salon/equipment', array_filter([
                'name' => $name, 'kind' => $kind, 'cost' => $cost, 'bought_on' => $this->end->copy()->subDays($age)->toDateString(), 'next_service_on' => $next?->toDateString(), 'status' => 'working',
            ], fn ($v) => $v !== null), $at);
            $this->made['equipment']++;
        }
    }

    private function feedback(Carbon $start): void
    {
        $praise = ['Lovely braids, they lasted for weeks', 'Very clean and professional', 'Asante sana, nimependa sana', 'Quick service and friendly staff', 'My nails look great', 'Best makeup for my wedding', 'Will come again', 'Worth every shilling'];
        $complaints = ['Waited more than an hour past my booking', 'The price was higher than I was told'];
        $withClients = array_values(array_filter($this->clients, fn ($c) => $c['id'] !== null));
        for ($i = 0; $i < min(60, max(8, (int) ($this->days / 3))) && $withClients !== []; $i++) {
            $day = $start->copy()->addDays($this->between(3, $this->days - 1))->setTime($this->between(10, 18), $this->between(0, 59));
            $c = $this->pick($withClients);
            $complaint = $this->chance(0.07);
            $staff = $c['pref'] ?? (string) $this->pick(array_keys(self::STAFF));
            $this->call('owner', 'POST', '/api/inventory/salon/feedback', array_filter([
                'kind' => $complaint ? 'complaint' : 'review', 'rating' => $complaint ? $this->between(1, 2) : (int) $this->weighted([5 => 55, 4 => 30, 3 => 12, 2 => 3]),
                'message' => $complaint ? $this->pick($complaints) : $this->pick($praise), 'customer_id' => $c['id'], 'staff_id' => $this->staffIds[$staff],
            ], fn ($v) => $v !== null), $day);
            $this->made['reviews']++;
        }
    }

    /** Who came to work in the last four weeks and for how long (the Team page): in a little after half past eight, out a little after six. */
    private function attendance(): void
    {
        $from = max(0, $this->days - 28);
        for ($d = $from; $d < $this->days; $d++) {
            $day = $this->end->copy()->subDays($this->days - $d - 1);
            foreach (array_keys(self::STAFF) as $key) {
                if (!$this->working($key, $day, $this->days - $d)) {
                    continue;
                }
                try {
                    $in = $day->copy()->setTime(8, $this->between(20, 59))->addMinutes($this->chance(0.12) ? $this->between(15, 40) : 0);
                    $this->call('owner', 'POST', '/api/inventory/salon/attendance/clock-in', ['staff_id' => $this->staffIds[$key]], $in);
                    $this->call('owner', 'POST', '/api/inventory/salon/attendance/clock-out', ['staff_id' => $this->staffIds[$key]], $day->copy()->setTime(17, $this->between(30, 59))->addMinutes($this->between(0, 70)));
                    $this->made['shifts']++;
                } catch (\RuntimeException) {
                    // a day the app refuses is not recorded
                }
            }
        }
    }

    /** The coming week's diary. */
    private function bookings(): void
    {
        $now = $this->end->copy()->setTime(9, 0);
        $withClients = array_values(array_filter($this->clients, fn ($c) => $c['id'] !== null));
        $count = min(24, count($withClients));
        for ($i = 0; $i < $count; $i++) {
            $day = $this->end->copy()->addDays($this->between(1, 7));
            $key = (string) $this->pick(array_keys(self::STAFF));
            if (!$this->working($key, $day, 0)) {
                continue;
            }
            $svc = (string) $this->weighted(self::STAFF[$key][2]);
            $c = $this->pick($withClients);
            try {
                $this->call('owner', 'POST', '/api/inventory/salon/appointments', [
                    'customer_id' => $c['id'], 'staff_id' => $this->staffIds[$key], 'starts_at' => $day->copy()->setTime($this->between(9, 16), $this->pick([0, 30]))->format('Y-m-d H:i'),
                    'services' => [['product_id' => $this->serviceIds[$svc], 'price' => self::SERVICES[$svc][0]]], 'duration_minutes' => self::SERVICES[$svc][1], 'force' => true,
                ], $now);
                $this->made['bookings']++;
            } catch (\RuntimeException) {
                // a clash the diary refuses is simply not booked
            }
        }
    }

    // ------------------------------------------------------------------------------------------------ what to tell

    /** @return array<string, mixed> */
    private function summary(): array
    {
        return [
            'business' => self::BUSINESS,
            'from' => $this->end->copy()->subDays($this->days)->toDateString(),
            'to' => $this->end->toDateString(),
            'made' => $this->made,
            'revenue' => round($this->revenue),
            'sign_in' => [
                ['role' => 'Owner', 'name' => 'Neema Mushi', 'email' => self::OWNER_EMAIL, 'phone' => '0700000101'],
                ['role' => 'Accountant', 'name' => 'Rehema Kimaro', 'email' => 'demo.accountant@glowbeauty.example', 'phone' => '0700000102'],
            ],
            'password' => $this->password,
        ];
    }

    // ------------------------------------------------------------------------------------------------ remove

    /** Takes away the demo salon and nothing else. @return int how many rows went */
    public static function remove(): int
    {
        $owner = User::query()->where('email', self::OWNER_EMAIL)->first();
        if ($owner === null) {
            return 0;
        }
        $ownerId = (string) $owner->id;
        $gone = 0;
        // The rows of one business point at each other (a sale line at its product, a sale at its client): they all go, so the order does not matter.
        Schema::disableForeignKeyConstraints();
        TenantContext::withoutScope(function () use ($ownerId, &$gone) {
            $pending = array_values(array_filter(TenantTables::INVENTORY, fn (string $t) => Schema::hasTable($t) && Schema::hasColumn($t, TenantTables::OWNER_COLUMN)));
            // Where the database insists on the order (a sale line must go before its product), a table that refuses is tried again after the others.
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
            $people = User::query()->where('id', $ownerId)->orWhere('created_by', $ownerId)->pluck('id')->all();
            if ($people !== []) {
                DB::table('personal_access_tokens')->whereIn('tokenable_id', $people)->delete();
                if (Schema::hasTable('user_services')) {
                    DB::table('user_services')->whereIn('user_id', $people)->delete();
                }
                $gone += DB::table('users')->whereIn('id', $people)->delete();
            }
            if (Schema::hasTable('businesses')) {
                $gone += DB::table('businesses')->where('owner_id', $ownerId)->delete();
            }
        });
        Schema::enableForeignKeyConstraints();

        return $gone;
    }
}
