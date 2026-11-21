<?php

namespace App\Http\Controllers\API\Groups;

use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupAudit;
use App\Support\Groups\GroupHires;
use App\Support\Groups\GroupMembers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * The asset register. Every member sees the things that are shown to members (name, what it is, how many are free, the hire rate); the
 * value, where it is kept and its history are for whoever manages assets and for its keeper. Every change of count is an event with its
 * reason, never a silent edit.
 */
class GroupAssetController extends Controller
{
    private function fail(string $code, string $message, int $status = 422): JsonResponse
    {
        return response()->json(['success' => false, 'code' => $code, 'message' => $message], $status);
    }

    /** @return array<string, mixed> */
    private static function payload(object $a, bool $inside): array
    {
        $today = now()->toDateString();
        $out = [
            'id' => (int) $a->id,
            'code' => $a->code,
            'name' => $a->name,
            'category' => $a->category,
            'description' => $a->description,
            'quantity' => (int) $a->quantity,
            'free_today' => GroupHires::available($a, $today, $today),
            'condition' => $a->condition,
            'hire_rate' => $a->hire_rate === null ? null : (float) $a->hire_rate,
            'late_rate' => $a->late_rate === null ? null : (float) $a->late_rate,
            'status' => $a->status,
            'visible' => (bool) $a->visible,
            'custodian_id' => $a->custodian_id === null ? null : (int) $a->custodian_id,
            'custodian_name' => $a->custodian_name ?? null,
        ];
        if ($inside) {
            $out += [
                'acquired_on' => $a->acquired_on === null ? null : (string) $a->acquired_on,
                'cost' => $a->cost === null ? null : (float) $a->cost,
                'location' => $a->location,
            ];
        }

        return $out;
    }

    private static function query(): \Illuminate\Database\Query\Builder
    {
        return DB::table('group_assets as a')->leftJoin('group_members as k', 'k.id', '=', 'a.custodian_id')->select('a.*', 'k.full_name as custodian_name');
    }

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $manager = GroupAccess::can($user, 'manage_assets');
        $rows = self::query()->when(!$manager, fn ($q) => $q->where('a.visible', true)->where('a.status', 'active'))->orderBy('a.status')->orderBy('a.name')->get();

        return response()->json(['success' => true, 'data' => [
            'assets' => $rows->map(fn ($a) => self::payload($a, $manager || GroupHires::canHandle($user, $a)))->values(),
            'can_manage' => $manager,
        ]]);
    }

    public function show(Request $request, int $id): JsonResponse
    {
        $a = self::query()->where('a.id', $id)->first();
        $user = $request->user();
        $inside = $a !== null && GroupHires::canHandle($user, $a);
        if ($a === null || (!$inside && (!$a->visible || $a->status !== 'active'))) {
            return $this->fail('not_found', 'Mali haipo. / Asset not found.', 404);
        }
        $events = $inside ? DB::table('group_asset_events as e')->leftJoin('users as u', 'u.id', '=', 'e.by_user')->where('e.asset_id', $id)->orderByDesc('e.id')->limit(100)
            ->get(['e.kind', 'e.quantity', 'e.cost', 'e.note', 'e.created_at', 'u.name as by_name'])->map(fn ($e) => (array) $e)->values() : [];

        return response()->json(['success' => true, 'data' => ['asset' => self::payload($a, $inside), 'events' => $events, 'can_handle' => $inside]]);
    }

    /** How many are free over a range of days. */
    public function availability(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['from' => 'required|date', 'to' => 'required|date|after_or_equal:from']);
        $a = DB::table('group_assets')->where('id', $id)->where('status', 'active')->first();
        if ($a === null) {
            return $this->fail('not_found', 'Mali haipo. / Asset not found.', 404);
        }

        return response()->json(['success' => true, 'data' => [
            'free' => GroupHires::available($a, $data['from'], $data['to']),
            'days' => GroupHires::days($data['from'], $data['to']),
            'rate' => $a->hire_rate === null ? null : (float) $a->hire_rate,
        ]]);
    }

    /** Add an asset, or change one ([id]). The count changes only through events (damage, loss, repair, correction). */
    public function save(Request $request, ?int $id = null): JsonResponse
    {
        $data = $request->validate([
            'code' => 'required|string|max:30|regex:/^[A-Za-z0-9\-\/]+$/',
            'name' => 'required|string|min:2|max:120',
            'category' => 'nullable|string|max:60',
            'description' => 'nullable|string|max:255',
            'quantity' => ($id === null ? 'required' : 'prohibited') . '|integer|min:1|max:100000',
            'condition' => ['nullable', Rule::in(['good', 'fair', 'poor'])],
            'acquired_on' => 'nullable|date|before_or_equal:today',
            'cost' => 'nullable|numeric|min:0|max:10000000000',
            'location' => 'nullable|string|max:150',
            'custodian_id' => 'nullable|integer',
            'visible' => 'nullable|boolean',
            'hire_rate' => 'nullable|numeric|min:0|max:100000000',
            'late_rate' => 'nullable|numeric|min:0|max:100000000',
        ]);
        if (!empty($data['custodian_id']) && !DB::table('group_members')->where('id', (int) $data['custodian_id'])->where('status', GroupMembers::ACTIVE)->exists()) {
            return $this->fail('bad_custodian', 'Mtunzaji lazima awe mwanachama hai. / The keeper must be an active member.');
        }
        if (DB::table('group_assets')->where('code', $data['code'])->when($id !== null, fn ($q) => $q->where('id', '!=', $id))->exists()) {
            return $this->fail('code_taken', 'Namba hii ya mali tayari imetumika. / This asset code is already used.');
        }
        $row = [
            'code' => strtoupper(trim($data['code'])),
            'name' => trim($data['name']),
            'category' => $data['category'] ?? null,
            'description' => $data['description'] ?? null,
            'condition' => $data['condition'] ?? 'good',
            'acquired_on' => $data['acquired_on'] ?? null,
            'cost' => $data['cost'] ?? null,
            'location' => $data['location'] ?? null,
            'custodian_id' => empty($data['custodian_id']) ? null : (int) $data['custodian_id'],
            'visible' => (bool) ($data['visible'] ?? true),
            'hire_rate' => $data['hire_rate'] ?? null,
            'late_rate' => $data['late_rate'] ?? null,
            'updated_at' => now(),
        ];
        $by = (string) $request->user()->id;
        if ($id === null) {
            $id = (int) DB::table('group_assets')->insertGetId($row + ['quantity' => (int) $data['quantity'], 'status' => 'active', 'created_at' => now()]);
            GroupHires::event($id, 'adjust', (int) $data['quantity'], 'registered', $by);
        } else {
            $before = DB::table('group_assets')->where('id', $id)->first();
            if ($before === null) {
                return $this->fail('not_found', 'Mali haipo. / Asset not found.', 404);
            }
            DB::table('group_assets')->where('id', $id)->update($row);
            if ((int) ($before->custodian_id ?? 0) !== (int) ($row['custodian_id'] ?? 0)) {
                GroupHires::event($id, 'custody', null, 'keeper changed', $by);
            }
        }
        GroupAudit::record($by, 'asset_saved', $row['code'] . ' ' . $row['name'], 'asset', $id);

        return $this->show($request, $id);
    }

    /** A change to an asset: maintenance (cost), damage or loss (fewer usable), repair or a correction (count up or down), retiring it. */
    public function event(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'kind' => ['required', Rule::in(['maintenance', 'damage', 'loss', 'repair', 'adjust', 'retire'])],
            'quantity' => 'nullable|integer|min:1|max:100000',
            'cost' => 'nullable|numeric|min:0|max:10000000000',
            'note' => 'required|string|min:3|max:255',
            'direction' => ['nullable', Rule::in(['up', 'down'])],
        ]);
        $a = DB::table('group_assets')->where('id', $id)->first();
        if ($a === null) {
            return $this->fail('not_found', 'Mali haipo. / Asset not found.', 404);
        }
        $qty = (int) ($data['quantity'] ?? 0);
        $change = match ($data['kind']) {
            'damage', 'loss' => -$qty,
            'repair' => $qty,
            'adjust' => ($data['direction'] ?? 'up') === 'down' ? -$qty : $qty,
            default => 0,
        };
        if (in_array($data['kind'], ['damage', 'loss', 'repair', 'adjust'], true) && $qty < 1) {
            return $this->fail('quantity_required', 'Weka idadi. / Give the number.');
        }
        if ((int) $a->quantity + $change < 0) {
            return $this->fail('too_many', 'Idadi ni zaidi ya zilizopo. / More than there are.');
        }
        DB::transaction(function () use ($a, $data, $change, $request, $id) {
            DB::table('group_assets')->where('id', $id)->update([
                'quantity' => (int) $a->quantity + $change,
                'status' => $data['kind'] === 'retire' ? 'retired' : $a->status,
                'updated_at' => now(),
            ]);
            GroupHires::event($id, $data['kind'], $change === 0 ? null : $change, trim($data['note']), (string) $request->user()->id, isset($data['cost']) ? (float) $data['cost'] : null);
        });
        GroupAudit::record((string) $request->user()->id, 'asset_' . $data['kind'], $a->code . ': ' . trim($data['note']), 'asset', $id);

        return $this->show($request, $id);
    }
}
