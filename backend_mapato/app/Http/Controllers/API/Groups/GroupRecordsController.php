<?php

namespace App\Http\Controllers\API\Groups;

use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupAudit;
use App\Support\Groups\GroupContributions;
use App\Support\Groups\GroupLedger;
use App\Support\Groups\GroupLoans;
use App\Support\Groups\GroupMembers;
use App\Support\Groups\GroupOffices;
use App\Support\PrivateFile;
use App\Support\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * The group's records around its members: invitation codes, the referral tree (who brought whom), members' photos and documents, and the
 * reports and exports. Who sees what follows the rights: the whole tree and the exports for officers, one's own branch for a member, ID
 * documents only for whoever may see NIDA numbers.
 */
class GroupRecordsController extends Controller
{
    private function fail(string $code, string $message, int $status = 422): JsonResponse
    {
        return response()->json(['success' => false, 'code' => $code, 'message' => $message], $status);
    }

    // ---------------------------------------------------------------- invitations

    private static function newCode(): string
    {
        $letters = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
        do {
            $code = '';
            for ($i = 0; $i < 8; $i++) {
                $code .= $letters[random_int(0, strlen($letters) - 1)];
            }
        } while (TenantContext::withoutScope(fn () => DB::table('group_invitations')->where('code', $code)->exists()));

        return $code;
    }

    /** @return array<string, mixed> */
    private static function invitation(object $i): array
    {
        return ['id' => (int) $i->id, 'code' => $i->code, 'kind' => $i->kind, 'active' => (bool) $i->active, 'used' => (int) $i->used, 'created_at' => (string) $i->created_at];
    }

    /** The member's own code (made the first time it is asked for), and the group's codes for whoever registers members. */
    public function invitations(Request $request): JsonResponse
    {
        $user = $request->user();
        $me = GroupAccess::member($user);
        $mine = null;
        if ($me !== null && $me['status'] === GroupMembers::ACTIVE) {
            $row = DB::table('group_invitations')->where('kind', 'member')->where('member_id', (int) $me['id'])->where('active', true)->first();
            if ($row === null) {
                $id = (int) DB::table('group_invitations')->insertGetId([
                    'code' => self::newCode(), 'kind' => 'member', 'member_id' => (int) $me['id'], 'active' => true,
                    'created_by' => (string) $user->id, 'created_at' => now(), 'updated_at' => now(),
                ]);
                $row = DB::table('group_invitations')->where('id', $id)->first();
            }
            $mine = self::invitation($row);
        }
        $group = GroupAccess::can($user, 'manage_members')
            ? DB::table('group_invitations')->where('kind', 'group')->orderByDesc('id')->limit(20)->get()->map(fn ($i) => self::invitation($i))->values()
            : [];

        return response()->json(['success' => true, 'data' => ['mine' => $mine, 'group' => $group]]);
    }

    /** A new code for the group (a poster, a meeting): applicants who use it have no referrer. */
    public function newGroupCode(Request $request): JsonResponse
    {
        DB::table('group_invitations')->insert([
            'code' => self::newCode(), 'kind' => 'group', 'active' => true, 'created_by' => (string) $request->user()->id, 'created_at' => now(), 'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, 'invitation_created', 'New group code');

        return $this->invitations($request)->setStatusCode(201);
    }

    /** Stop a code: one's own, or (whoever registers members) any. A new own code is made the next time it is asked for. */
    public function stopCode(Request $request, int $id): JsonResponse
    {
        $i = DB::table('group_invitations')->where('id', $id)->first();
        $me = GroupAccess::member($request->user());
        $own = $i !== null && $i->member_id !== null && $me !== null && (int) $i->member_id === (int) $me['id'];
        if ($i === null || (!$own && !GroupAccess::can($request->user(), 'manage_members'))) {
            return $this->fail('not_yours', 'Huna ruhusa. / Not allowed.', 403);
        }
        DB::table('group_invitations')->where('id', $id)->update(['active' => false, 'updated_at' => now()]);
        GroupAudit::record((string) $request->user()->id, 'invitation_stopped', 'Code ' . $i->code);

        return $this->invitations($request);
    }

    // ---------------------------------------------------------------- the referral tree

    /** @return array<int, array<string, mixed>> */
    private static function nodes(?array $only = null): array
    {
        return DB::table('group_members')->when($only !== null, fn ($q) => $q->whereIn('id', $only))
            ->whereNotIn('status', [GroupMembers::SUBMITTED, GroupMembers::REJECTED])
            ->orderBy('joined_on')->orderBy('id')
            ->get(['id', 'full_name', 'member_number', 'status', 'referrer_id', 'joined_on', 'founding', 'office'])
            ->map(fn ($m) => [
                'id' => (int) $m->id, 'name' => $m->full_name, 'member_number' => $m->member_number, 'status' => $m->status,
                'referrer_id' => $m->referrer_id === null ? null : (int) $m->referrer_id, 'joined_on' => $m->joined_on === null ? null : (string) $m->joined_on,
                'founding' => (bool) $m->founding, 'office' => $m->office,
            ])->all();
    }

    /** The whole tree (as a flat list the app nests), for officers; and the growth in numbers. */
    public function tree(): JsonResponse
    {
        $nodes = self::nodes();
        $pending = DB::table('group_members')->where('status', GroupMembers::SUBMITTED)->count();
        $byMonth = collect($nodes)->filter(fn ($n) => $n['joined_on'] !== null)->groupBy(fn ($n) => substr($n['joined_on'], 0, 7))->map->count()->sortKeys();

        return response()->json(['success' => true, 'data' => [
            'nodes' => $nodes,
            'stats' => [
                'members' => count($nodes),
                'active' => count(array_filter($nodes, fn ($n) => $n['status'] === GroupMembers::ACTIVE)),
                'pending' => $pending,
                'no_referrer' => count(array_filter($nodes, fn ($n) => $n['referrer_id'] === null)),
                'joined_by_month' => $byMonth,
            ],
        ]]);
    }

    /** The member's own branch: everyone they brought in, and whom those brought in. */
    public function myBranch(Request $request): JsonResponse
    {
        $me = GroupAccess::member($request->user());
        if ($me === null) {
            return response()->json(['success' => true, 'data' => ['nodes' => [], 'root' => null]]);
        }
        $all = DB::table('group_members')->whereNotIn('status', [GroupMembers::SUBMITTED, GroupMembers::REJECTED])->get(['id', 'referrer_id']);
        $children = [];
        foreach ($all as $m) {
            if ($m->referrer_id !== null) {
                $children[(int) $m->referrer_id][] = (int) $m->id;
            }
        }
        $branch = [(int) $me['id']];
        $frontier = [(int) $me['id']];
        for ($depth = 0; $depth < 30 && $frontier !== []; $depth++) {
            $next = [];
            foreach ($frontier as $id) {
                foreach ($children[$id] ?? [] as $c) {
                    if (!in_array($c, $branch, true)) {
                        $branch[] = $c;
                        $next[] = $c;
                    }
                }
            }
            $frontier = $next;
        }

        return response()->json(['success' => true, 'data' => ['nodes' => self::nodes($branch), 'root' => (int) $me['id']]]);
    }

    // ---------------------------------------------------------------- documents

    /** @return array<int, array<string, mixed>> what of [memberId]'s papers [request]'s user may see, with links that expire */
    public static function documentsFor(Request $request, int $memberId): array
    {
        $sensitive = GroupAccess::can($request->user(), 'view_sensitive');

        return DB::table('group_member_documents')->where('member_id', $memberId)->when(!$sensitive, fn ($q) => $q->where('kind', '!=', 'id'))
            ->orderByDesc('id')->get()
            ->map(fn ($d) => ['id' => (int) $d->id, 'kind' => $d->kind, 'caption' => $d->caption, 'url' => PrivateFile::url($d->path), 'created_at' => (string) $d->created_at])
            ->values()->all();
    }

    public function documents(Request $request, int $id): JsonResponse
    {
        if (!DB::table('group_members')->where('id', $id)->exists()) {
            return $this->fail('not_found', 'Mwanachama hayupo. / Member not found.', 404);
        }

        return response()->json(['success' => true, 'data' => ['documents' => self::documentsFor($request, $id)]]);
    }

    /** Keep a photo or a paper of a member, privately. An ID copy needs the right to see NIDA numbers. */
    public function upload(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'file' => 'required|file|mimes:jpg,jpeg,png,pdf|max:5120',
            'kind' => ['required', Rule::in(['photo', 'id', 'other'])],
            'caption' => 'nullable|string|max:150',
        ]);
        if (!DB::table('group_members')->where('id', $id)->exists()) {
            return $this->fail('not_found', 'Mwanachama hayupo. / Member not found.', 404);
        }
        if ($data['kind'] === 'id' && !GroupAccess::can($request->user(), 'view_sensitive')) {
            return $this->fail('sensitive_right_needed', 'Ni wenye ruhusa ya NIDA tu wanaoweka nakala ya kitambulisho. / Only those who may see NIDA numbers keep ID copies.', 403);
        }
        if ($data['kind'] === 'photo' && !str_starts_with((string) $request->file('file')->getMimeType(), 'image/')) {
            return $this->fail('not_an_image', 'Picha lazima iwe JPG au PNG. / A photo must be a JPG or PNG.');
        }
        $path = PrivateFile::store($request->file('file'), 'group_documents/' . Str::lower(Str::random(2)));
        DB::table('group_member_documents')->insert([
            'member_id' => $id, 'kind' => $data['kind'], 'path' => $path, 'caption' => $data['caption'] ?? null,
            'uploaded_by' => (string) $request->user()->id, 'created_at' => now(),
        ]);
        if ($data['kind'] === 'photo') {
            DB::table('group_members')->where('id', $id)->update(['photo_path' => $path, 'updated_at' => now()]);
        }
        GroupAudit::record((string) $request->user()->id, 'document_kept', ucfirst($data['kind']) . ' kept for member #' . $id, 'member', $id);

        return $this->documents($request, $id)->setStatusCode(201);
    }

    public function removeDocument(Request $request, int $id, int $documentId): JsonResponse
    {
        $d = DB::table('group_member_documents')->where('id', $documentId)->where('member_id', $id)->first();
        if ($d === null) {
            return $this->fail('not_found', 'Halipo. / Not found.', 404);
        }
        if ($d->kind === 'id' && !GroupAccess::can($request->user(), 'view_sensitive')) {
            return $this->fail('sensitive_right_needed', 'Huna ruhusa. / Not allowed.', 403);
        }
        DB::table('group_member_documents')->where('id', $documentId)->delete();
        Storage::disk(PrivateFile::DISK)->delete($d->path);
        if (DB::table('group_members')->where('id', $id)->value('photo_path') === $d->path) {
            DB::table('group_members')->where('id', $id)->update(['photo_path' => null, 'updated_at' => now()]);
        }
        GroupAudit::record((string) $request->user()->id, 'document_removed', ucfirst($d->kind) . ' removed from member #' . $id, 'member', $id);

        return $this->documents($request, $id);
    }

    // ---------------------------------------------------------------- reports

    /** The group in numbers for a period: members, money by kind (in and out apart), contributions, loans, welfare, hire, dividends. */
    public function summary(Request $request): JsonResponse
    {
        $data = $request->validate(['from' => 'required|date', 'to' => 'required|date|after_or_equal:from']);
        $from = $data['from'];
        $to = $data['to'];
        $money = DB::table('group_transactions')->where('status', GroupLedger::VERIFIED)->whereBetween('paid_on', [$from, $to])
            ->selectRaw("category, SUM(CASE WHEN direction = 'in' THEN amount ELSE 0 END) as money_in, SUM(CASE WHEN direction = 'out' THEN amount ELSE 0 END) as money_out")
            ->groupBy('category')->get()
            ->mapWithKeys(fn ($r) => [$r->category => ['in' => round((float) $r->money_in, 2), 'out' => round((float) $r->money_out, 2)]]);
        $statusCounts = DB::table('group_members')->selectRaw('status, COUNT(*) as n')->groupBy('status')->pluck('n', 'status');
        $owing = GroupContributions::owing(GroupContributions::query())->where('o.due_date', '<', now()->toDateString())->get();
        $expected = GroupContributions::query()->where('o.status', GroupContributions::OPEN)->whereBetween('o.due_date', [$from, $to])->get();
        $portfolio = ['principal' => 0.0, 'interest' => 0.0, 'arrears' => 0.0];
        foreach (DB::table('group_loans')->where('status', 'active')->get() as $loan) {
            $p = GroupLoans::position($loan);
            $portfolio['principal'] += $p['outstanding_principal'];
            $portfolio['interest'] += $p['outstanding_interest'];
            $portfolio['arrears'] += $p['arrears'];
        }

        return response()->json(['success' => true, 'data' => [
            'from' => $from,
            'to' => $to,
            'members' => [
                'by_status' => collect(GroupMembers::STATUSES)->mapWithKeys(fn ($s) => [$s => (int) ($statusCounts[$s] ?? 0)]),
                'joined' => DB::table('group_members')->whereBetween('joined_on', [$from, $to])->count(),
                'officers' => DB::table('group_members')->whereIn('office', GroupOffices::OFFICES)->where('status', GroupMembers::ACTIVE)->count(),
            ],
            'money' => $money,
            'contributions' => [
                'expected' => round($expected->sum(fn ($o) => (float) $o->amount_due), 2),
                'collected' => round($expected->sum(fn ($o) => min((float) $o->paid, (float) $o->amount_due)), 2),
                'overdue_now' => round($owing->sum(fn ($o) => (float) $o->amount_due - (float) $o->paid), 2),
                'overdue_members' => $owing->pluck('member_id')->unique()->count(),
            ],
            'loans_now' => array_map(fn ($v) => round($v, 2), $portfolio),
            'meetings_held' => DB::table('group_meetings')->where('status', 'held')->whereBetween('starts_at', [$from . ' 00:00:00', $to . ' 23:59:59'])->count(),
        ]]);
    }

    /** A CSV of the member register (officers who see members; NIDA only for those who may see it). */
    public function exportMembers(Request $request): StreamedResponse
    {
        $sensitive = GroupAccess::can($request->user(), 'view_sensitive');
        $rows = DB::table('group_members as m')->leftJoin('group_members as r', 'r.id', '=', 'm.referrer_id')->orderBy('m.member_number')->orderBy('m.full_name')
            ->get(['m.*', 'r.full_name as referrer_name']);
        GroupAudit::record((string) $request->user()->id, 'export_members', 'Member register exported (' . $rows->count() . ' rows)');

        return $this->csv('members.csv', ['Member number', 'Name', 'Phone', 'Email', 'NIDA', 'Status', 'Office', 'Joined on', 'Referred by', 'Region', 'District'],
            $rows->map(fn ($m) => [$m->member_number, $m->full_name, $m->phone, $m->email, $sensitive ? GroupMembers::nida($m->nida) : GroupMembers::maskNida(GroupMembers::nida($m->nida)),
                $m->status, $m->office, $m->joined_on, $m->referrer_name, $m->region, $m->district])->all());
    }

    /** A CSV of the verified money of a period. */
    public function exportTransactions(Request $request): StreamedResponse
    {
        $data = $request->validate(['from' => 'required|date', 'to' => 'required|date|after_or_equal:from']);
        $rows = GroupLedger::listQuery()->where('t.status', GroupLedger::VERIFIED)->whereBetween('t.paid_on', [$data['from'], $data['to']])->orderBy('t.paid_on')->orderBy('t.id')->get();
        GroupAudit::record((string) $request->user()->id, 'export_transactions', 'Payments exported ' . $data['from'] . '..' . $data['to'] . ' (' . $rows->count() . ' rows)');

        return $this->csv('payments.csv', ['Date', 'Receipt', 'Reference', 'Member number', 'Member', 'Kind', 'In/Out', 'Amount', 'Method', 'External reference', 'Payee', 'Verified by'],
            $rows->map(fn ($t) => [(string) $t->paid_on, $t->receipt_number, $t->reference, $t->member_number, $t->member_name, $t->category, $t->direction,
                (float) $t->amount, $t->method, $t->external_ref, $t->payee, $t->verified_by_name])->all());
    }

    /** @param array<int, array<int, mixed>> $rows */
    private function csv(string $name, array $header, array $rows): StreamedResponse
    {
        return response()->streamDownload(function () use ($header, $rows) {
            $out = fopen('php://output', 'w');
            fwrite($out, "\xEF\xBB\xBF"); // so Excel reads the Swahili and the TSH figures right
            fputcsv($out, $header);
            foreach ($rows as $row) {
                // A cell that starts like a formula is written as text: an export must never run anything in a spreadsheet.
                fputcsv($out, array_map(fn ($v) => is_string($v) && preg_match('/^[=+\-@]/', $v) === 1 ? "'" . $v : $v, $row));
            }
            fclose($out);
        }, $name, ['Content-Type' => 'text/csv; charset=UTF-8']);
    }
}
