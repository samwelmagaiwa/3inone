<?php

namespace App\Http\Controllers\API\Inventory;

use App\Models\Business;
use App\Support\Salon\AppointmentPlanner;
use App\Support\Salon\SalonAccess;
use App\Support\Salon\SalonFinance;
use Dompdf\Dompdf;
use Dompdf\Options;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Routing\Controller;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use OpenApi\Attributes as OA;

/**
 * The salon's books on paper and in a spreadsheet: sales, expenses, payroll, each stylist's results, profit and loss and
 * the VAT collected, as a PDF to print or a CSV that Excel opens. For the owner, managers and accountants (it is the
 * business's money). Headers come in English or Swahili.
 */
#[OA\Tag(name: 'Inventory / Salon', description: 'Salon exports (PDF and CSV)')]
class SalonExportController extends Controller
{
    public const TYPES = ['sales', 'expenses', 'payroll', 'stylists', 'profit-loss', 'tax', 'cashbook'];

    /** A report longer than this is a mistake (or the whole history): ask for a shorter period. */
    private const MAX_ROWS = 20000;

    #[OA\Get(path: '/inventory/salon/export/{type}', summary: 'A report as a PDF or a CSV file', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'type', in: 'path', required: true, schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 200, description: 'The file')])]
    public function export(Request $request, string $type): Response
    {
        abort_unless(SalonAccess::isManager($request->user()), 403, 'Ni mmiliki, meneja au mhasibu tu. / Only the owner, a manager or an accountant.');
        abort_unless(in_array($type, self::TYPES, true), 404, 'Unknown report');
        $data = $request->validate([
            'format' => ['nullable', Rule::in(['csv', 'pdf'])],
            'lang' => ['nullable', Rule::in(['en', 'sw'])],
            'from' => 'nullable|date',
            'to' => 'nullable|date|after_or_equal:from',
            'month' => ['nullable', 'regex:/^\d{4}-(0[1-9]|1[0-2])$/'],
        ]);
        $format = $data['format'] ?? 'csv';
        $sw = ($data['lang'] ?? 'en') === 'sw';
        $today = Carbon::now(AppointmentPlanner::TIMEZONE)->startOfDay();
        $from = isset($data['from']) ? Carbon::parse($data['from'])->startOfDay() : $today->copy()->startOfMonth();
        $to = isset($data['to']) ? Carbon::parse($data['to'])->startOfDay() : $today;
        $month = $data['month'] ?? $today->format('Y-m');

        // Pass what the reports need on to the pages that already know how to work it out.
        $request->merge(['from' => $from->toDateString(), 'to' => $to->toDateString(), 'month' => $month]);
        [$title, $headers, $rows, $totals] = match ($type) {
            'sales' => $this->sales($from, $to, $sw),
            'expenses' => $this->expenses($from, $to, $sw),
            'payroll' => $this->payroll($request, $month, $sw),
            'stylists' => $this->stylists($request, $sw),
            'profit-loss' => $this->profitLoss($from, $to, $sw),
            'cashbook' => $this->cashbook($from, $to, $sw),
            default => $this->tax($from, $to, $sw),
        };

        $period = $type === 'payroll' ? $month : $from->format('d/m/Y') . ' - ' . $to->format('d/m/Y');
        $business = (string) (Business::forUser($request->user())?->name ?? '');
        $file = 'salon-' . $type . '-' . ($type === 'payroll' ? $month : $from->format('Ymd') . '-' . $to->format('Ymd')) . '.' . $format;

        return $format === 'pdf'
            ? $this->pdf($file, $business, $title, $period, $headers, $rows, $totals)
            : $this->csv($file, $title, $period, $headers, $rows, $totals);
    }

    // ------------------------------------------------------------------ the reports

    /** @return array{0: string, 1: array<int, string>, 2: array<int, array<int, mixed>>, 3: ?array<int, mixed>} */
    private function sales(Carbon $from, Carbon $to, bool $sw): array
    {
        $sales = DB::table('inventory_sales as s')
            ->leftJoin('inventory_customers as c', 'c.id', '=', 's.customer_id')
            ->whereNull('s.cancelled_at')
            ->whereDate('s.created_at', '>=', $from->toDateString())
            ->whereDate('s.created_at', '<=', $to->toDateString())
            ->orderBy('s.created_at')->orderBy('s.id')
            ->limit(self::MAX_ROWS)
            ->get(['s.id', 's.number', 's.created_at', 's.subtotal', 's.discount', 's.total', 's.paid_total', 's.payment_status', 's.customer_name_override', 'c.name as customer_name']);
        $reasons = \Illuminate\Support\Facades\Schema::hasColumn('inventory_sales', 'discount_reason')
            ? DB::table('inventory_sales')->whereIn('id', $sales->pluck('id'))->pluck('discount_reason', 'id') : collect();

        $lines = $sales->isEmpty() ? collect() : DB::table('inventory_sale_items as si')
            ->leftJoin('inventory_products as p', 'p.id', '=', 'si.product_id')
            ->whereIn('si.sale_id', $sales->pluck('id'))
            ->get(['si.sale_id', 'p.name', 'si.staff_name', DB::raw('COALESCE(si.unit_qty, si.quantity) as qty')])
            ->groupBy('sale_id');
        $methods = $sales->isEmpty() ? collect() : DB::table('inventory_sale_payments')
            ->whereIn('sale_id', $sales->pluck('id'))
            ->get(['sale_id', 'method', 'method_extended'])->groupBy('sale_id')
            ->map(fn ($g) => $g->map(fn ($p) => $p->method_extended ?: $p->method)->unique()->implode(', '));

        $rows = $sales->map(fn ($s) => [
            Carbon::parse($s->created_at)->format('Y-m-d H:i'),
            $s->number,
            $s->customer_name ?: ($s->customer_name_override ?: ''),
            ($lines[$s->id] ?? collect())->map(fn ($l) => $l->name . ((int) $l->qty > 1 ? ' x' . (int) $l->qty : ''))->implode('; '),
            ($lines[$s->id] ?? collect())->pluck('staff_name')->filter()->unique()->implode(', '),
            SalonFinance::money($s->subtotal),
            SalonFinance::money($s->discount),
            (string) ($reasons[$s->id] ?? ''),
            SalonFinance::money($s->total),
            SalonFinance::money($s->paid_total),
            $s->payment_status,
            (string) ($methods[$s->id] ?? ''),
        ])->all();

        return [
            $sw ? 'Mauzo' : 'Sales',
            $sw ? ['Tarehe', 'Namba', 'Mteja', 'Huduma na bidhaa', 'Mhudumu', 'Jumla ndogo', 'Punguzo', 'Sababu ya punguzo', 'Jumla', 'Kilicholipwa', 'Hali', 'Njia ya malipo']
                : ['Date', 'Number', 'Client', 'Services and goods', 'Stylist', 'Subtotal', 'Discount', 'Discount reason', 'Total', 'Paid', 'Status', 'Paid by'],
            $rows,
            [$sw ? 'Jumla' : 'Total', '', '', '', '', SalonFinance::money(array_sum(array_column($rows, 5))), SalonFinance::money(array_sum(array_column($rows, 6))), '', SalonFinance::money(array_sum(array_column($rows, 8))), SalonFinance::money(array_sum(array_column($rows, 9))), '', ''],
        ];
    }

    private function expenses(Carbon $from, Carbon $to, bool $sw): array
    {
        $hasStatus = \Illuminate\Support\Facades\Schema::hasColumn('inventory_expenses', 'status');
        $rows = DB::table('inventory_expenses as e')
            ->leftJoin('users as u', 'u.id', '=', 'e.created_by')
            ->whereBetween('e.expense_date', [$from->toDateString(), $to->toDateString()])
            ->orderBy('e.expense_date')->orderBy('e.id')
            ->limit(self::MAX_ROWS)
            ->get(['e.*', 'u.name as by'])
            ->map(fn ($e) => [
                Carbon::parse($e->expense_date)->toDateString(),
                $e->category,
                $e->description,
                (string) ($e->supplier ?? ''),
                (string) ($e->payment_method ?? ''),
                SalonFinance::money($e->amount),
                $hasStatus ? (string) $e->status : 'approved',
                (string) ($e->by ?? ''),
            ])->all();
        $approved = array_sum(array_map(fn ($r) => $r[6] === 'approved' ? $r[5] : 0, $rows));

        return [
            $sw ? 'Matumizi' : 'Expenses',
            $sw ? ['Tarehe', 'Aina', 'Maelezo', 'Muuzaji', 'Njia ya malipo', 'Kiasi', 'Hali', 'Aliyeingiza']
                : ['Date', 'Category', 'Description', 'Supplier', 'Paid by', 'Amount', 'Status', 'Entered by'],
            $rows,
            [$sw ? 'Jumla iliyoidhinishwa' : 'Total approved', '', '', '', '', SalonFinance::money($approved), '', ''],
        ];
    }

    private function payroll(Request $request, string $month, bool $sw): array
    {
        $d = app(SalonMoneyController::class)->payroll($request)->getData(true)['data'];
        $rows = array_map(fn ($r) => [$r['name'], $r['salary'], $r['commission_earned'], $r['salary_paid'], $r['commission_paid'], $r['advances'], $r['owed']], $d['staff']);
        $t = $d['totals'];

        return [
            ($sw ? 'Mishahara ' : 'Payroll ') . $month,
            $sw ? ['Jina', 'Mshahara', 'Kamisheni iliyopatikana', 'Mshahara uliolipwa', 'Kamisheni iliyolipwa', 'Advance', 'Anadaiwa']
                : ['Name', 'Salary', 'Commission earned', 'Salary paid', 'Commission paid', 'Advances', 'Still owed'],
            $rows,
            [$sw ? 'Jumla' : 'Total', $t['salary'], $t['commission_earned'], $t['salary_paid'], $t['commission_paid'], $t['advances'], $t['owed']],
        ];
    }

    private function stylists(Request $request, bool $sw): array
    {
        $d = app(SalonController::class)->stylists($request)->getData(true)['data'];
        $rows = array_map(fn ($s) => [$s['name'] ?: ($sw ? 'Hakutajwa' : 'No stylist named'), $s['services'], $s['revenue'], $s['discount'], $s['commission'], $s['visits'], $s['clients']], $d['stylists']);
        $t = $d['totals'];

        return [
            $sw ? 'Matokeo ya wahudumu' : 'Stylists\' results',
            $sw ? ['Mhudumu', 'Huduma', 'Mapato halisi', 'Punguzo', 'Kamisheni', 'Ziara', 'Wateja']
                : ['Stylist', 'Services', 'Net revenue', 'Discount', 'Commission', 'Visits', 'Clients'],
            $rows,
            [$sw ? 'Jumla' : 'Total', $t['services'], $t['revenue'], $t['discount'], $t['commission'], $t['visits'], ''],
        ];
    }

    private function profitLoss(Carbon $from, Carbon $to, bool $sw): array
    {
        $s = SalonFinance::summary($from, $to);
        $line = fn (string $en, string $swa, $v) => [$sw ? $swa : $en, $v];
        $rows = [
            $line('Service revenue', 'Mapato ya huduma', $s['service_revenue']),
            $line('Goods sold', 'Mauzo ya bidhaa', $s['goods_revenue']),
            $line('(discounts already taken off)', '(punguzo tayari limeondolewa)', $s['discounts']),
            $line('Cost of goods sold', 'Gharama ya bidhaa zilizouzwa', -$s['cost_of_goods']),
            $line('Gross profit', 'Faida ghafi', $s['gross_profit']),
            ...array_map(fn ($g) => [$g['category'], -$g['total']], $s['expenses_by_category']),
            $line('Stylists commission', 'Kamisheni za wahudumu', -$s['commissions']),
            $line('Salaries paid', 'Mishahara iliyolipwa', -$s['salaries']),
            $line('Other income (kept deposits)', 'Mapato mengine (amana zilizobaki)', $s['other_income']),
            $line('Money received', 'Pesa zilizopokelewa', $s['collected']),
            $line('Owed by clients', 'Madeni ya wateja', $s['outstanding']),
        ];

        return [$sw ? 'Faida na hasara' : 'Profit and loss', $sw ? ['Maelezo', 'Kiasi (TSh)'] : ['Item', 'Amount (TSh)'], $rows, [$sw ? 'Faida halisi' : 'Net profit', $s['net_profit']]];
    }

    /** One line per place per day with money moving or counted: in, out, what should be held, and the count if one was made. */
    private function cashbook(Carbon $from, Carbon $to, bool $sw): array
    {
        $book = \App\Support\Salon\SalonBooks::book($from->toDateString(), $to->toDateString());
        $name = fn (string $p) => $p === 'cash' ? ($sw ? 'Taslimu' : 'Cash') : ($p === 'mobile' ? ($sw ? 'Simu' : 'Mobile money') : ($sw ? 'Benki' : 'Bank'));
        $rows = [];
        foreach ($book['places'] as $place => $data) {
            $rows[] = [$from->toDateString(), $name($place), $sw ? 'Salio la kuanzia' : 'Opening balance', '', '', $data['opening'], '', ''];
            foreach ($data['days'] as $d) {
                $rows[] = [$d['date'], $name($place), '', $d['in'], $d['out'], $d['closing'], $d['count']['counted'] ?? '', $d['count']['difference'] ?? ''];
            }
        }

        return [
            $sw ? 'Kitabu cha pesa' : 'Cashbook',
            $sw ? ['Tarehe', 'Mahali', 'Maelezo', 'Ndani', 'Nje', 'Inapaswa kuwepo', 'Iliyohesabiwa', 'Tofauti'] : ['Date', 'Place', 'Note', 'In', 'Out', 'Should be held', 'Counted', 'Difference'],
            $rows,
            [$sw ? 'Jumla inapaswa kuwepo' : 'Total that should be held', $book['total']['closing']],
        ];
    }

    private function tax(Carbon $from, Carbon $to, bool $sw): array
    {
        $s = SalonFinance::summary($from, $to);
        $rows = array_map(fn ($r) => [$r['rate'] . '%', $r['taxable'], $r['vat']], $s['vat']['by_rate']);

        return [
            $sw ? 'Muhtasari wa kodi (VAT)' : 'VAT summary',
            $sw ? ['Kiwango', 'Mauzo yanayotozwa kodi', 'VAT'] : ['Rate', 'Taxable sales', 'VAT'],
            $rows,
            [$sw ? 'Jumla' : 'Total', SalonFinance::money(array_sum(array_column($rows, 1))), $s['vat']['total']],
        ];
    }

    // ------------------------------------------------------------------ the files

    private function csv(string $file, string $title, string $period, array $headers, array $rows, ?array $totals): Response
    {
        $out = fopen('php://temp', 'r+');
        fwrite($out, "\xEF\xBB\xBF"); // so Excel reads the letters right
        fputcsv($out, [$title, $period]);
        fputcsv($out, $headers);
        foreach ($rows as $row) {
            fputcsv($out, array_map(fn ($v) => $this->safe($v), $row));
        }
        if ($totals !== null) {
            fputcsv($out, array_map(fn ($v) => $this->safe($v), $totals));
        }
        rewind($out);
        $body = (string) stream_get_contents($out);
        fclose($out);

        return response($body, 200, ['Content-Type' => 'text/csv; charset=UTF-8', 'Content-Disposition' => 'attachment; filename="' . $file . '"', 'Cache-Control' => 'no-store']);
    }

    /** A cell that starts like a formula is made plain text, so a name like "=cmd()" cannot run inside Excel. */
    private function safe(mixed $v): mixed
    {
        return is_string($v) && $v !== '' && in_array($v[0], ['=', '+', '-', '@', "\t", "\r"], true) && !is_numeric($v) ? "'" . $v : $v;
    }

    private function pdf(string $file, string $business, string $title, string $period, array $headers, array $rows, ?array $totals): Response
    {
        $e = fn ($v) => htmlspecialchars((string) (is_float($v) || is_int($v) ? number_format((float) $v, $v == floor((float) $v) ? 0 : 2) : $v), ENT_QUOTES, 'UTF-8');
        $cell = fn ($v, string $tag = 'td') => '<' . $tag . (is_numeric($v) ? ' class="n"' : '') . '>' . $e($v) . '</' . $tag . '>';
        $html = '<html><head><meta charset="utf-8"><style>'
            . 'body{font-family:DejaVu Sans,sans-serif;font-size:10px;color:#111}h1{font-size:16px;margin:0}h2{font-size:12px;margin:2px 0 10px;color:#555}'
            . 'table{width:100%;border-collapse:collapse}th{background:#0b3a4a;color:#fff;text-align:left;padding:4px}td{padding:3px 4px;border-bottom:1px solid #ddd}'
            . '.n{text-align:right}tr.t td{font-weight:bold;border-top:2px solid #0b3a4a}</style></head><body>'
            . '<h1>' . $e($business) . '</h1><h2>' . $e($title) . ' &middot; ' . $e($period) . '</h2><table><tr>'
            . implode('', array_map(fn ($h) => '<th>' . $e($h) . '</th>', $headers)) . '</tr>';
        foreach ($rows as $row) {
            $html .= '<tr>' . implode('', array_map(fn ($v) => $cell($v), $row)) . '</tr>';
        }
        if ($totals !== null) {
            $html .= '<tr class="t">' . implode('', array_map(fn ($v) => $cell($v), $totals)) . '</tr>';
        }
        $html .= '</table></body></html>';

        $options = new Options();
        $options->set('isRemoteEnabled', false);   // nothing in a report may reach out to the network
        $options->set('isPhpEnabled', false);
        $dompdf = new Dompdf($options);
        $dompdf->loadHtml($html);
        $dompdf->setPaper('A4', count($headers) > 7 ? 'landscape' : 'portrait');
        $dompdf->render();

        return response($dompdf->output(), 200, ['Content-Type' => 'application/pdf', 'Content-Disposition' => 'attachment; filename="' . $file . '"', 'Cache-Control' => 'no-store']);
    }
}
