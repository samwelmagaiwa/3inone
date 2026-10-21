<?php

namespace App\Http\Controllers\API\Inventory;

use App\Support\Salon\AppointmentPlanner;
use App\Support\Salon\SalonAccess;
use App\Support\Salon\SalonPerks;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use OpenApi\Attributes as OA;

/**
 * What brings a client back: loyalty points (how they are earned and spent, and each client's balance), vouchers, and
 * the packages a client has bought. The rules live in {@see SalonPerks}; the owner and managers set them.
 */
#[OA\Tag(name: 'Inventory / Salon', description: 'Salon loyalty points, vouchers and packages')]
class SalonPerksController extends Controller
{
    private function requireManager(Request $request): void
    {
        abort_unless(SalonAccess::canConfigure($request->user()), 403, 'Ni mmiliki tu anayeweza kufanya hivi. / Only the owner can do this.');
    }

    private function today(): string
    {
        return Carbon::now(AppointmentPlanner::TIMEZONE)->toDateString();
    }

    // ------------------------------------------------------------------ loyalty

    #[OA\Get(path: '/inventory/salon/loyalty/settings', summary: 'How points are earned and spent', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function loyaltySettings(): JsonResponse
    {
        return response()->json(['data' => SalonPerks::settings()]);
    }

    #[OA\Put(path: '/inventory/salon/loyalty/settings', summary: 'Switch points on, and say how much one is worth', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function saveLoyaltySettings(Request $request): JsonResponse
    {
        $this->requireManager($request);
        $data = $request->validate([
            'on' => 'sometimes|boolean',
            'per' => 'sometimes|integer|min:1|max:10000000',
            'value' => 'sometimes|integer|min:0|max:10000000',
            'referral' => 'sometimes|integer|min:0|max:100000',
        ]);
        SalonPerks::saveSettings(
            array_key_exists('on', $data) ? (bool) $data['on'] : null,
            $data['per'] ?? null,
            $data['value'] ?? null,
            $data['referral'] ?? null,
        );

        return response()->json(['message' => 'Saved', 'data' => SalonPerks::settings()]);
    }

    #[OA\Get(path: '/inventory/salon/clients/{id}/loyalty', summary: 'A client\'s points and what moved them', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function loyalty(int $id): JsonResponse
    {
        abort_if(DB::table('inventory_customers')->where('id', $id)->doesntExist(), 404, 'Client not found');
        $s = SalonPerks::settings();
        $balance = SalonPerks::balance($id);

        $ledger = DB::table('inventory_loyalty_ledger')->where('customer_id', $id)->orderByDesc('id')->limit(50)->get()
            ->map(fn ($r) => ['points' => (int) $r->points, 'kind' => $r->kind, 'note' => $r->note, 'at' => Carbon::parse($r->created_at)->format('Y-m-d H:i')])->values();

        return response()->json(['data' => [
            'on' => $s['on'],
            'balance' => $balance,
            'worth' => $balance * $s['value'],
            'per' => $s['per'],
            'value' => $s['value'],
            'ledger' => $ledger,
        ]]);
    }

    #[OA\Post(path: '/inventory/salon/clients/{id}/loyalty/adjust', summary: 'Give or take points by hand, with a reason', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function adjustLoyalty(Request $request, int $id): JsonResponse
    {
        $this->requireManager($request);
        abort_if(DB::table('inventory_customers')->where('id', $id)->doesntExist(), 404, 'Client not found');
        $data = $request->validate(['points' => 'required|integer|not_in:0|between:-100000,100000', 'note' => 'required|string|min:3|max:160']);

        if ($data['points'] < 0 && SalonPerks::balance($id) + $data['points'] < 0) {
            throw ValidationException::withMessages(['points' => ['Pointi haziwezi kuwa chini ya sifuri. / Points cannot go below zero.']]);
        }
        DB::table('inventory_loyalty_ledger')->insert([
            'customer_id' => $id, 'points' => $data['points'], 'kind' => 'adjust', 'note' => trim($data['note']),
            'created_by' => (string) $request->user()->id, 'created_at' => now(), 'updated_at' => now(),
        ]);

        return response()->json(['message' => 'Saved', 'data' => ['balance' => SalonPerks::balance($id)]]);
    }

    // ------------------------------------------------------------------ vouchers

    #[OA\Get(path: '/inventory/salon/vouchers', summary: 'The salon\'s vouchers', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function vouchers(Request $request): JsonResponse
    {
        $this->requireManager($request);
        $today = $this->today();

        $rows = DB::table('inventory_vouchers')->orderByDesc('active')->orderByDesc('id')->get()->map(fn ($v) => [
            'id' => (int) $v->id,
            'code' => $v->code,
            'kind' => $v->kind,
            'value' => (float) $v->value == floor((float) $v->value) ? (int) $v->value : (float) $v->value,
            'expires_on' => $v->expires_on ? Carbon::parse($v->expires_on)->toDateString() : null,
            'max_uses' => $v->max_uses === null ? null : (int) $v->max_uses,
            'used_count' => (int) $v->used_count,
            'active' => (bool) $v->active,
            'note' => $v->note,
            // Usable now: switched on, not past its date, not used up.
            'usable' => (bool) $v->active && ($v->expires_on === null || Carbon::parse($v->expires_on)->toDateString() >= $today) && ($v->max_uses === null || (int) $v->used_count < (int) $v->max_uses),
        ])->values();

        return response()->json(['data' => $rows]);
    }

    #[OA\Post(path: '/inventory/salon/vouchers', summary: 'Make a voucher', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 201, description: 'Created')])]
    public function storeVoucher(Request $request): JsonResponse
    {
        $this->requireManager($request);
        $data = $request->validate([
            'code' => ['required', 'string', 'min:3', 'max:40', 'regex:/^[A-Za-z0-9_-]+$/'],
            'kind' => ['required', Rule::in(['percent', 'amount'])],
            'value' => 'required|numeric|gt:0|max:100000000',
            'expires_on' => 'nullable|date_format:Y-m-d',
            'max_uses' => 'nullable|integer|min:1|max:1000000',
            'note' => 'nullable|string|max:160',
        ]);
        if ($data['kind'] === 'percent' && (float) $data['value'] > 100) {
            throw ValidationException::withMessages(['value' => ['Asilimia isizidi 100. / A percent cannot be more than 100.']]);
        }
        $code = strtoupper($data['code']);
        if (DB::table('inventory_vouchers')->where('code', $code)->exists()) {
            throw ValidationException::withMessages(['code' => ['Msimbo huu upo tayari. / That code already exists.']]);
        }

        $id = DB::table('inventory_vouchers')->insertGetId([
            'code' => $code, 'kind' => $data['kind'], 'value' => $data['value'], 'expires_on' => $data['expires_on'] ?? null,
            'max_uses' => $data['max_uses'] ?? null, 'note' => !empty($data['note']) ? trim($data['note']) : null, 'active' => true,
            'created_by' => (string) $request->user()->id, 'created_at' => now(), 'updated_at' => now(),
        ]);

        return response()->json(['message' => 'Created', 'data' => ['id' => (int) $id, 'code' => $code]], 201);
    }

    #[OA\Put(path: '/inventory/salon/vouchers/{id}', summary: 'Change, switch off or extend a voucher', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function updateVoucher(Request $request, int $id): JsonResponse
    {
        $this->requireManager($request);
        abort_if(DB::table('inventory_vouchers')->where('id', $id)->doesntExist(), 404, 'Voucher not found');
        $data = $request->validate([
            'active' => 'sometimes|boolean',
            'expires_on' => 'sometimes|nullable|date_format:Y-m-d',
            'max_uses' => 'sometimes|nullable|integer|min:1|max:1000000',
            'note' => 'sometimes|nullable|string|max:160',
        ]);
        DB::table('inventory_vouchers')->where('id', $id)->update($data + ['updated_at' => now()]);

        return response()->json(['message' => 'Saved']);
    }

    #[OA\Delete(path: '/inventory/salon/vouchers/{id}', summary: 'Delete a voucher that was never used', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function destroyVoucher(Request $request, int $id): JsonResponse
    {
        $this->requireManager($request);
        $v = DB::table('inventory_vouchers')->find($id);
        abort_if($v === null, 404, 'Voucher not found');
        if ((int) $v->used_count > 0) {
            throw ValidationException::withMessages(['voucher' => ['Kuponi iliyotumika haifutwi: izime badala yake. / A voucher that was used cannot be deleted: switch it off instead.']]);
        }
        DB::table('inventory_vouchers')->where('id', $id)->delete();

        return response()->json(['message' => 'Deleted']);
    }

    #[OA\Get(path: '/inventory/salon/vouchers/check', summary: 'What a voucher takes off a sale of this size', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function checkVoucher(Request $request): JsonResponse
    {
        $data = $request->validate(['code' => 'required|string|max:40', 'subtotal' => 'required|numeric|min:0']);

        return response()->json(['data' => SalonPerks::preview($data['code'], (float) $data['subtotal'])]);
    }

    // ------------------------------------------------------------------ packages

    #[OA\Get(path: '/inventory/salon/clients/{id}/packages', summary: 'The packages a client has bought, with the visits left', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function packages(int $id): JsonResponse
    {
        abort_if(DB::table('inventory_customers')->where('id', $id)->doesntExist(), 404, 'Client not found');
        $today = $this->today();

        $rows = DB::table('inventory_client_packages as cp')
            ->leftJoin('inventory_products as sp', 'sp.id', '=', 'cp.service_product_id')
            ->where('cp.customer_id', $id)
            ->orderBy('cp.status')
            ->orderByDesc('cp.id')
            ->get(['cp.*', 'sp.name as service_name'])
            ->map(function ($p) use ($today) {
                $expired = $p->expires_on !== null && Carbon::parse($p->expires_on)->toDateString() < $today;

                return [
                    'id' => (int) $p->id,
                    'name' => $p->name,
                    'service_product_id' => (int) $p->service_product_id,
                    'service_name' => $p->service_name,
                    'sessions_total' => (int) $p->sessions_total,
                    'sessions_left' => (int) $p->sessions_left,
                    'expires_on' => $p->expires_on ? Carbon::parse($p->expires_on)->toDateString() : null,
                    'status' => $p->status,
                    'expired' => $expired,
                    // Can be used at the till today.
                    'usable' => $p->status === 'active' && !$expired && (int) $p->sessions_left > 0,
                ];
            })->values();

        return response()->json(['data' => $rows]);
    }
}
