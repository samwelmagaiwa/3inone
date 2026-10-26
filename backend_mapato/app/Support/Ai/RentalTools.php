<?php

namespace App\Support\Ai;

use App\Models\Rental\House;
use App\Models\Rental\MaintenanceRequest;
use App\Models\Rental\Property;
use App\Models\Rental\RentBill;
use App\Models\Rental\RentalPayment;

/**
 * The Rental service for the AI assistant: properties, houses, rent owed and maintenance. Read through the Eloquent models, whose
 * scope (App\Support\Tenancy\RentalAccess) gives an owner the account's properties, a caretaker only theirs, and a tenant only their own lease.
 */
final class RentalTools
{
    /** @return array{data: array<string, mixed>, card: ?array<string, mixed>} */
    public static function overview(): array
    {
        $houses = House::get(['status'])->countBy('status');
        $arrears = RentBill::whereIn('status', ['unpaid', 'partial', 'overdue']);
        $owed = (float) (clone $arrears)->sum('balance');
        $collected = (float) RentalPayment::where('payment_date', '>=', now()->startOfMonth()->toDateString())->sum('amount_paid');
        $data = [
            'currency' => 'TSh', 'properties' => Property::count(), 'houses' => $houses->sum(),
            'occupied' => (int) ($houses['occupied'] ?? 0), 'vacant' => (int) ($houses['vacant'] ?? 0), 'under_maintenance' => (int) ($houses['maintenance'] ?? 0),
            'rent_collected_this_month' => round($collected, 2), 'rent_owed_total' => round($owed, 2), 'bills_overdue' => (clone $arrears)->where('status', 'overdue')->count(),
            'open_maintenance_requests' => MaintenanceRequest::whereIn('status', ['open', 'pending', 'in_progress'])->count(),
        ];

        return ['data' => $data, 'card' => ['type' => 'rows', 'title' => 'Rental', 'rows' => [
            ['title' => 'Properties', 'value' => (string) $data['properties']],
            ['title' => 'Houses', 'value' => (string) $data['houses'], 'note' => $data['occupied'] . ' occupied, ' . $data['vacant'] . ' vacant'],
            ['title' => 'Rent collected this month', 'value' => AssistantTools::tsh($collected)],
            ['title' => 'Rent owed', 'value' => AssistantTools::tsh($owed), 'note' => $data['bills_overdue'] . ' overdue bills'],
        ]]];
    }

    public static function arrears(array $args): array
    {
        $bills = RentBill::whereIn('status', ['unpaid', 'partial', 'overdue'])->where('balance', '>', 0)
            ->with(['agreement.tenant:id,name', 'agreement.house:id,house_number,property_id', 'agreement.house.property:id,name'])->get();
        $by = $bills->groupBy(fn ($b) => $b->agreement?->tenant_id)->map(function ($g) {
            $a = $g->first()->agreement;

            return [
                'tenant' => $a?->tenant?->name ?? 'Unknown', 'house' => trim(($a?->house?->property?->name ?? '') . ' ' . ($a?->house?->house_number ?? '')),
                'owed' => round((float) $g->sum('balance'), 2), 'months_unpaid' => $g->count(), 'overdue' => $g->contains(fn ($b) => $b->status === 'overdue'),
            ];
        })->sortByDesc('owed')->take(AssistantTools::limit($args))->values()->all();

        return ['data' => ['currency' => 'TSh', 'tenants_owing' => $by], 'card' => $by === [] ? null : ['type' => 'rows', 'title' => 'Rent owed', 'rows' => array_map(
            fn ($t) => ['title' => $t['tenant'], 'value' => AssistantTools::tsh($t['owed']), 'note' => $t['house'] . ' · ' . $t['months_unpaid'] . ' bills' . ($t['overdue'] ? ' · overdue' : '')], $by
        )]];
    }

    public static function houses(array $args): array
    {
        $q = House::with(['property:id,name'])->orderBy('house_number')->limit(15);
        if (in_array($args['status'] ?? '', ['vacant', 'occupied', 'maintenance'], true)) {
            $q->where('status', $args['status']);
        }
        $search = AssistantTools::text($args['search'] ?? '', 60);
        if ($search !== '') {
            $q->where('house_number', 'like', '%' . AssistantTools::like($search) . '%');
        }
        $rows = $q->get();
        $data = $rows->map(fn ($h) => ['house' => $h->house_number, 'property' => $h->property?->name, 'status' => $h->status, 'rent' => round((float) $h->rent_amount, 2)])->all();

        return ['data' => ['currency' => 'TSh', 'houses' => $data], 'card' => $data === [] ? null : ['type' => 'rows', 'title' => 'Houses', 'rows' => array_map(
            fn ($h) => ['title' => trim($h['property'] . ' ' . $h['house']), 'value' => AssistantTools::tsh($h['rent']), 'note' => $h['status']], $data
        )]];
    }

    public static function maintenance(array $args): array
    {
        $rows = MaintenanceRequest::with(['house:id,house_number', 'property:id,name', 'tenant:id,name'])
            ->whereIn('status', ['open', 'pending', 'in_progress'])->orderByDesc('id')->limit(10)->get();
        $data = $rows->map(fn ($m) => [
            'house' => trim(($m->property?->name ?? '') . ' ' . ($m->house?->house_number ?? '')), 'tenant' => $m->tenant?->name,
            'category' => $m->category, 'priority' => $m->priority, 'status' => $m->status, 'description' => mb_substr((string) $m->description, 0, 120),
        ])->all();

        return ['data' => ['requests' => $data], 'card' => $data === [] ? null : ['type' => 'rows', 'title' => 'Maintenance', 'rows' => array_map(
            fn ($m) => ['title' => $m['house'], 'value' => (string) $m['status'], 'note' => trim($m['category'] . ' · ' . $m['priority'], ' ·')], $data
        )]];
    }
}
