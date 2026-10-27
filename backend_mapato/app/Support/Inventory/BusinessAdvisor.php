<?php

namespace App\Support\Inventory;

use App\Models\Business;
use App\Support\Ai\GeminiClient;
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;

/**
 * Where the owner can do better. The numbers are worked out by the app ({@see MonthlyReport}); the advice is then
 *
 *   1. always written by plain rules from those numbers (works with no internet and no AI key), and
 *   2. when an AI key is set on the server, read and improved by Claude, which is given the same facts in full -- totals,
 *      product names, customer and creditor names with what they owe -- and told to use only those numbers.
 *
 * Phone numbers never leave the server. The AI answer is checked: if it is missing or malformed the rule-based advice is
 * what the owner reads, so the page never fails. One answer is kept per business, month and language each day, and the owner
 * may ask for a fresh one a few times a day.
 */
final class BusinessAdvisor
{
    public const REFRESHES_PER_DAY = 5;

    private const CACHE_KEY = 'advice_cache';

    /**
     * @return array{items: array<int, array{level: string, title: string, detail: string}>, source: string, ai_error: ?string, facts: array<string, mixed>, refreshes_left: int, created: string}
     */
    public static function advise(string $month, string $lang, bool $refresh = false): array
    {
        $lang = $lang === 'sw' ? 'sw' : 'en';
        $today = now(MonthlyFigures::TIMEZONE)->toDateString();
        $cached = self::cached();
        $branch = \App\Support\Salon\SalonBranch::selected();
        $same = $cached !== null && ($cached['branch'] ?? null) === $branch && ($cached['date'] ?? null) === $today && ($cached['month'] ?? null) === $month && ($cached['lang'] ?? null) === $lang;
        $used = $cached !== null && ($cached['date'] ?? null) === $today ? (int) ($cached['count'] ?? 1) : 0;

        if ($same && !$refresh) {
            return self::present($cached, $used);
        }
        if ($same && $refresh && $used >= self::REFRESHES_PER_DAY) {
            return self::present($cached, $used);
        }

        $facts = self::facts($month);
        $rules = self::rules($facts, $lang === 'sw');
        $items = $rules;
        $source = 'rules';
        $error = null;

        if (self::aiKey() !== '') {
            try {
                $ai = self::askAi($facts, $rules, $lang);
                if ($ai !== []) {
                    $items = $ai;
                    $source = 'ai';
                } else {
                    $error = 'empty';
                }
            } catch (\Throwable $e) {
                $error = mb_substr($e->getMessage(), 0, 160);
            }
        }

        $entry = ['branch' => $branch, 'date' => $today, 'month' => $month, 'lang' => $lang, 'count' => $used + 1, 'items' => $items, 'source' => $source, 'ai_error' => $error, 'created' => now()->toIso8601String(), 'facts' => $facts];
        DB::table('inventory_settings')->updateOrInsert(['key' => self::CACHE_KEY], ['value' => json_encode($entry, JSON_UNESCAPED_UNICODE), 'updated_at' => now()]);

        return self::present($entry, $used + 1);
    }

    public static function aiKey(): string
    {
        $provider = self::provider();

        return $provider === null ? '' : trim((string) config("services.{$provider}.key", ''));
    }

    /** Which AI answers: Gemini when its key is set, else Anthropic, else none (rules only). */
    public static function provider(): ?string
    {
        foreach (['gemini', 'anthropic'] as $name) {
            if (trim((string) config("services.{$name}.key", '')) !== '') {
                return $name;
            }
        }

        return null;
    }

    private static function cached(): ?array
    {
        $raw = DB::table('inventory_settings')->where('key', self::CACHE_KEY)->value('value');
        $data = $raw === null ? null : json_decode((string) $raw, true);

        return is_array($data) ? $data : null;
    }

    private static function present(array $entry, int $used): array
    {
        return [
            'items' => $entry['items'] ?? [], 'source' => $entry['source'] ?? 'rules', 'ai_error' => $entry['ai_error'] ?? null,
            'facts' => $entry['facts'] ?? [], 'refreshes_left' => max(0, self::REFRESHES_PER_DAY - $used), 'created' => $entry['created'] ?? now()->toIso8601String(),
        ];
    }

    // ------------------------------------------------------------------ the facts

    /** @return array<string, mixed> everything the advice is based on; no phone numbers */
    public static function facts(string $month): array
    {
        $branch = \App\Support\Salon\SalonBranch::selected();
        $r = MonthlyReport::build($month, $branch);
        $viewer = TenantContext::viewer();
        $business = $viewer === null ? null : Business::forUser($viewer);
        $prev = $r['previous']['figures'];
        $f = $r['figures'];

        // Which kinds of spending moved most against the month before.
        $before = collect($prev['expenses_by_category'])->pluck('total', 'category');
        $moves = collect($f['expenses_by_category'])->map(fn ($c) => ['category' => $c['category'], 'now' => $c['total'], 'before' => (float) ($before[$c['category']] ?? 0), 'change' => round($c['total'] - (float) ($before[$c['category']] ?? 0), 2)])
            ->sortByDesc('change')->values()->take(5)->all();

        return [
            'business' => $business?->name,
            'branch' => $branch === null ? null : DB::table('inventory_branches')->where('id', $branch)->value('name'),
            'kind' => $business?->inventory_type,
            'month' => $month,
            'month_in_progress' => $r['is_current'],
            'days_elapsed' => $r['days_elapsed'],
            'days_in_month' => $r['days_in_month'],
            'currency' => 'TSh',
            'this_month' => $f,
            'compared_with' => ['month' => $r['previous']['month'], 'same_days_only' => $r['previous']['like_for_like'], 'figures' => $prev],
            'change' => collect($r['compare'])->map(fn ($c) => ['now' => $c['now'], 'before' => $c['before'], 'percent' => $c['percent'], 'direction' => $c['direction']])->all(),
            'expense_changes' => $moves,
            'position' => $r['position'],
            'capital_change' => $r['capital_change'],
            'profit_target' => $r['target'],
            'best_products_by_profit' => $r['top_products'],
            'best_customers' => $r['top_customers'],
            'sleeping_stock_30_days' => $r['slow_stock'],
            'customers_who_owe' => $r['debtors'],
            'business_owes' => array_map(fn ($d) => ['name' => $d['name'], 'left' => $d['left'], 'days_late' => $d['days_late']], $r['creditors']),
        ];
    }

    // ------------------------------------------------------------------ the rules

    /**
     * @param  array<string, mixed>  $f
     * @return array<int, array{level: string, title: string, detail: string}>
     */
    public static function rules(array $f, bool $sw): array
    {
        $t = fn (string $s, string $e) => $sw ? $s : $e;
        $tsh = fn (float $n) => 'TSh ' . number_format(round($n), 0, '.', ',');
        $pct = fn (?float $p) => $p === null ? '' : ($p > 0 ? '+' : '') . rtrim(rtrim(number_format($p, 1), '0'), '.') . '%';
        $items = [];
        $m = $f['this_month'];
        $profit = $f['change']['net_profit'];
        $sales = $f['change']['sales'];
        $spend = $f['change']['expenses'];

        if ($m['sales_count'] === 0) {
            return [['level' => 'tip', 'title' => $t('Bado hakuna mauzo mwezi huu', 'No sales yet this month'), 'detail' => $t('Rekodi mauzo kila siku ili ripoti na ushauri viwe sahihi.', 'Record sales every day so the report and the advice are right.')]];
        }

        if ($profit['direction'] === 'down') {
            $why = $sales['direction'] === 'down'
                ? $t('Mauzo yameshuka (' . $pct($sales['percent']) . ').', 'Sales are down (' . $pct($sales['percent']) . ').')
                : ($spend['direction'] === 'up' ? $t('Matumizi yamepanda (' . $pct($spend['percent']) . ').', 'Spending is up (' . $pct($spend['percent']) . ').') : $t('Faida kwa kila bidhaa imepungua.', 'The profit on each sale is lower.'));
            $items[] = ['level' => 'warning', 'title' => $t('Faida imeshuka ' . ($profit['percent'] === null ? '' : abs($profit['percent']) . '%'), 'Profit fell ' . ($profit['percent'] === null ? '' : abs($profit['percent']) . '%')), 'detail' => $why . ' ' . $t('Faida: ', 'Profit: ') . $tsh($profit['now']) . $t(' dhidi ya ', ' against ') . $tsh($profit['before']) . '.'];
        } elseif ($profit['direction'] === 'up') {
            $items[] = ['level' => 'good', 'title' => $t('Faida imepanda ' . $pct($profit['percent']), 'Profit is up ' . $pct($profit['percent'])), 'detail' => $t('Faida: ', 'Profit: ') . $tsh($profit['now']) . $t(' dhidi ya ', ' against ') . $tsh($profit['before']) . $t('. Endelea na kilichofanya kazi.', '. Keep doing what worked.')];
        }

        if ($m['sales'] > 0 && $m['expenses'] / $m['sales'] > 0.30) {
            $top = $f['expense_changes'][0] ?? null;
            $items[] = ['level' => 'warning', 'title' => $t('Matumizi ni makubwa kwa mauzo', 'Spending is heavy for your sales'), 'detail' => $t('Matumizi ni ', 'Expenses are ') . round($m['expenses'] / $m['sales'] * 100) . $t('% ya mauzo.', '% of sales.') . ($top ? ' ' . $t('Kilichopanda zaidi: ', 'Biggest rise: ') . $top['category'] . ' (' . $tsh($top['change']) . ').' : '')];
        }

        if ($m['margin_percent'] !== null && $m['margin_percent'] < 10) {
            $items[] = ['level' => 'warning', 'title' => $t('Faida kwa kila mauzo ni ndogo', 'Thin margin on sales'), 'detail' => $t('Unabaki na ', 'You keep ') . $m['margin_percent'] . $t('% tu baada ya gharama ya bidhaa. Kagua bei za kuuza au bei ya kununua.', '% after the cost of the goods. Review your selling prices or what you pay suppliers.')];
        }

        $stockValue = (float) ($f['position']['stock_value'] ?? 0);
        $sleeping = collect($f['sleeping_stock_30_days']);
        if ($sleeping->isNotEmpty() && $stockValue > 0) {
            $sleepValue = (float) $sleeping->sum('value');
            if ($sleepValue / $stockValue > 0.10) {
                $items[] = ['level' => 'warning', 'title' => $t('Bidhaa zimelala dukani', 'Stock is sleeping on the shelf'), 'detail' => $t('Hazijauzwa kwa siku 30: ', 'Not sold in 30 days: ') . $sleeping->take(3)->pluck('name')->implode(', ') . ' (' . $tsh($sleepValue) . $t(' zimefungwa). Punguza bei au acha kuagiza tena.', ' tied up). Discount them or stop reordering.')];
            }
        }

        $owed = collect($f['customers_who_owe']);
        $totalOwed = (float) ($f['position']['receivable'] ?? 0);
        if ($totalOwed > 0 && ($m['sales'] > 0 && $totalOwed / $m['sales'] > 0.30 || $owed->contains(fn ($d) => $d['days'] > 60))) {
            $items[] = ['level' => 'warning', 'title' => $t('Madeni ya wateja yanasubiri kukusanywa', 'Customer debts need collecting'), 'detail' => $t('Unadai ', 'You are owed ') . $tsh($totalOwed) . ': ' . $owed->take(3)->map(fn ($d) => $d['name'] . ' ' . $tsh($d['owed']) . ' (' . $d['days'] . $t(' siku)', ' days)'))->implode(', ') . '.'];
        }

        $payable = (float) ($f['position']['payable'] ?? 0);
        if ($payable > 0 && $payable > $totalOwed + $stockValue * 0.5) {
            $items[] = ['level' => 'tip', 'title' => $t('Deni unalodaiwa ni kubwa', 'What you owe is large'), 'detail' => $t('Unadaiwa ', 'You owe ') . $tsh($payable) . $t('. Panga ratiba ya kulipa, anza na lililochelewa.', '. Plan repayments, starting with what is late.')];
        }

        $cap = $f['capital_change'];
        if ($cap !== null && $cap['direction'] === 'down') {
            $items[] = ['level' => 'warning', 'title' => $t('Mtaji umepungua', 'Capital has gone down'), 'detail' => $t('Mtaji umeshuka kwa ', 'Capital fell by ') . $tsh(abs($cap['change'])) . $t('. Angalia matumizi binafsi, madeni mapya na bidhaa zilizoharibika.', '. Check personal spending, new debts and damaged goods.')];
        }
        if ($m['personal_spending'] > 0 && $m['net_profit'] > 0 && $m['personal_spending'] / $m['net_profit'] > 0.5) {
            $items[] = ['level' => 'tip', 'title' => $t('Matumizi binafsi ni mengi', 'Personal spending is high'), 'detail' => $t('Umetoa ', 'You took out ') . $tsh($m['personal_spending']) . $t(' kwa matumizi binafsi, zaidi ya nusu ya faida. Mtaji hukua ukiacha faida ibaki.', ' for personal spending, over half the profit. Capital grows when profit is left in.')];
        }

        $target = $f['profit_target'];
        if ($target !== null) {
            if ($target['status'] === 'behind') {
                $need = $target['days_left'] > 0 ? $tsh($target['left'] / $target['days_left']) : $tsh($target['left']);
                $items[] = ['level' => 'warning', 'title' => $t('Uko nyuma ya lengo la faida', 'You are behind your profit target'), 'detail' => $t('Umepata ', 'You have ') . $tsh($target['profit']) . $t(' kati ya ', ' of ') . $tsh($target['profit_target']) . $t('. Unahitaji takriban ', '. You need about ') . $need . $t(' kwa siku iliyobaki.', ' a day for the rest of the month.')];
            } elseif ($target['status'] === 'reached') {
                $items[] = ['level' => 'good', 'title' => $t('Lengo la faida limefikiwa', 'Profit target reached'), 'detail' => $t('Umevuka lengo kwa ', 'You are over the target by ') . $tsh($target['over_by']) . '.'];
            } elseif ($target['status'] === 'missed') {
                $items[] = ['level' => 'warning', 'title' => $t('Lengo la faida halikufikiwa', 'Profit target missed'), 'detail' => $t('Ulikosa ', 'You were short by ') . $tsh($target['left']) . '.'];
            }
        } elseif ($f['month_in_progress']) {
            $items[] = ['level' => 'tip', 'title' => $t('Weka lengo la faida', 'Set a profit target'), 'detail' => $t('Weka lengo la mwezi uone kama uko mbele au nyuma.', 'Set a target for the month to see whether you are ahead or behind.')];
        }

        return array_slice($items, 0, 8);
    }

    // ------------------------------------------------------------------ the AI

    /**
     * @param  array<string, mixed>  $facts
     * @param  array<int, array{level: string, title: string, detail: string}>  $rules
     * @return array<int, array{level: string, title: string, detail: string}>
     */
    private static function askAi(array $facts, array $rules, string $lang): array
    {
        $language = $lang === 'sw' ? 'Swahili (simple, as spoken by a shop owner in Tanzania)' : 'English (simple and short)';
        $system = "You are a business adviser inside a shop-management app for a small business owner in Tanzania. "
            . "You are given the facts of one month as JSON (money is TSh). Reply with ONLY a JSON array of at most 6 objects "
            . '{"level":"warning|tip|good","title":"...","detail":"..."}, most important first. '
            . "Write in {$language}. Use ONLY numbers, product names and customer names found in the facts; never invent a figure. "
            . "Each detail must name the specific product, customer, expense or amount it is about and say one concrete action the owner can take this week. "
            . "Mention what is going well too. Do not repeat the same point. No markdown, no text outside the JSON.";

        $prompt = "Facts:\n" . json_encode(['facts' => $facts, 'rule_based_notes' => $rules], JSON_UNESCAPED_UNICODE);

        if (self::provider() === 'gemini') {
            try {
                // GeminiClient moves down its list of models by itself when one runs out of quota or is overloaded.
                $reply = GeminiClient::generate([
                    'systemInstruction' => ['parts' => [['text' => $system]]],
                    'contents' => [['role' => 'user', 'parts' => [['text' => $prompt]]]],
                    'generationConfig' => ['temperature' => 0.4, 'maxOutputTokens' => 4096, 'responseMimeType' => 'application/json'],
                ]);

                return self::parse((string) data_get($reply, 'candidates.0.content.parts.0.text', ''));
            } catch (\RuntimeException $e) {
                // Every Gemini model failed: use Claude when a key for it is set, else let the rules answer.
                if (trim((string) config('services.anthropic.key', '')) === '') {
                    throw $e;
                }
            }
        }

        $res = Http::withHeaders(['x-api-key' => trim((string) config('services.anthropic.key')), 'anthropic-version' => '2023-06-01'])
            ->timeout(45)->acceptJson()
            ->post('https://api.anthropic.com/v1/messages', [
                'model' => (string) config('services.anthropic.model', 'claude-sonnet-5-5'),
                'max_tokens' => 1500,
                'system' => $system,
                'messages' => [['role' => 'user', 'content' => $prompt]],
            ]);
        if (!$res->successful()) {
            throw new \RuntimeException('AI answered ' . $res->status());
        }

        return self::parse((string) data_get($res->json(), 'content.0.text', ''));
    }

    /**
     * Read the AI's answer into clean items; anything that is not a list of {title, detail} is dropped.
     *
     * @return array<int, array{level: string, title: string, detail: string}>
     */
    public static function parse(string $text): array
    {
        $start = strpos($text, '[');
        $end = strrpos($text, ']');
        if ($start === false || $end === false || $end <= $start) {
            return [];
        }
        $data = json_decode(substr($text, $start, $end - $start + 1), true);
        if (!is_array($data)) {
            return [];
        }
        $out = [];
        foreach ($data as $row) {
            if (!is_array($row) || trim((string) ($row['title'] ?? '')) === '' || trim((string) ($row['detail'] ?? '')) === '') {
                continue;
            }
            $level = in_array($row['level'] ?? '', ['warning', 'tip', 'good'], true) ? $row['level'] : 'tip';
            $out[] = ['level' => $level, 'title' => mb_substr(trim((string) $row['title']), 0, 120), 'detail' => mb_substr(trim((string) $row['detail']), 0, 500)];
        }

        return array_slice($out, 0, 6);
    }
}
