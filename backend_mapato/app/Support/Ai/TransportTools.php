<?php

namespace App\Support\Ai;

use App\Models\DebtRecord;
use App\Models\Driver;
use App\Models\Payment;

/**
 * The Transport service for the AI assistant: drivers, vehicles, payments and debts. Read through the Eloquent models, whose
 * account scope already limits a business to its own rows and a driver to their own; see {@see AssistantTools} for who gets which tool.
 */
final class TransportTools
{
    /** @return array{data: array<string, mixed>, card: ?array<string, mixed>} */
    public static function overview(): array
    {
        $month = now()->startOfMonth();
        $owed = DebtRecord::unpaid()->get(['expected_amount', 'paid_amount', 'days_overdue', 'driver_id']);
        $debt = (float) $owed->sum(fn ($d) => (float) $d->expected_amount - (float) $d->paid_amount);
        $collected = (float) Payment::completed()->where('payment_date', '>=', $month)->sum('amount');
        $data = [
            'currency' => 'TSh',
            'drivers' => Driver::count(), 'active_drivers' => Driver::where('is_active', true)->count(),
            'vehicles' => \App\Models\Device::count(),
            'collected_this_month' => round($collected, 2),
            'unpaid_debt_total' => round($debt, 2), 'drivers_in_debt' => $owed->pluck('driver_id')->unique()->count(),
        ];

        return ['data' => $data, 'card' => ['type' => 'rows', 'title' => 'Transport', 'rows' => [
            ['title' => 'Drivers', 'value' => (string) $data['drivers'], 'note' => $data['active_drivers'] . ' active'],
            ['title' => 'Vehicles', 'value' => (string) $data['vehicles']],
            ['title' => 'Collected this month', 'value' => AssistantTools::tsh($collected)],
            ['title' => 'Unpaid debt', 'value' => AssistantTools::tsh($debt), 'note' => $data['drivers_in_debt'] . ' drivers'],
        ]]];
    }

    public static function drivers(array $args): array
    {
        $q = Driver::with(['user:id,name,phone_number', 'devices:id,driver_id,name,plate_number'])->limit(10);
        $search = AssistantTools::text($args['search'] ?? '', 60);
        if ($search !== '') {
            $q->whereHas('user', fn ($u) => $u->where('name', 'like', '%' . AssistantTools::like($search) . '%'));
        }
        $rows = $q->get();

        $data = $rows->map(fn ($d) => [
            'name' => $d->user?->name, 'active' => (bool) $d->is_active,
            'vehicles' => $d->devices->map(fn ($v) => trim($v->name . ' ' . $v->plate_number))->all(),
            'license_expiry' => optional($d->license_expiry)->toDateString(),
        ])->all();

        return ['data' => ['drivers' => $data], 'card' => $rows->isEmpty() ? null : ['type' => 'rows', 'title' => 'Drivers', 'rows' => $rows->map(fn ($d) => [
            'title' => (string) $d->user?->name, 'value' => (string) $d->user?->phone_number,
            'note' => ($d->devices->pluck('plate_number')->filter()->implode(', ') ?: 'no vehicle') . ($d->is_active ? '' : ' · inactive'),
        ])->all()]];
    }

    public static function debts(array $args): array
    {
        $by = DebtRecord::unpaid()->with('driver.user:id,name')->get()->groupBy('driver_id')->map(fn ($g) => [
            'name' => $g->first()->driver?->user?->name ?? 'Unknown',
            'owed' => round((float) $g->sum(fn ($d) => (float) $d->expected_amount - (float) $d->paid_amount), 2),
            'days' => (int) $g->max('days_overdue'),
        ])->filter(fn ($r) => $r['owed'] > 0)->sortByDesc('owed')->take(AssistantTools::limit($args))->values()->all();

        return ['data' => ['currency' => 'TSh', 'drivers_in_debt' => $by], 'card' => $by === [] ? null : ['type' => 'rows', 'title' => 'Drivers in debt', 'rows' => array_map(
            fn ($d) => ['title' => $d['name'], 'value' => AssistantTools::tsh($d['owed']), 'note' => $d['days'] . ' days'], $by
        )]];
    }

    public static function payments(array $args): array
    {
        $days = max(1, min(31, (int) ($args['days'] ?? 7)));
        $rows = Payment::completed()->with('driver.user:id,name')->where('payment_date', '>=', now()->subDays($days))
            ->orderByDesc('payment_date')->limit(15)->get();
        $data = $rows->map(fn ($p) => [
            'driver' => $p->driver?->user?->name ?? 'Unknown', 'amount' => round((float) $p->amount, 2),
            'date' => optional($p->payment_date)->toDateString(), 'channel' => $p->payment_channel,
        ])->all();

        return ['data' => ['currency' => 'TSh', 'days' => $days, 'payments' => $data], 'card' => $data === [] ? null : ['type' => 'rows', 'title' => 'Payments', 'rows' => array_map(
            fn ($p) => ['title' => $p['driver'], 'value' => AssistantTools::tsh($p['amount']), 'note' => trim($p['date'] . ' · ' . $p['channel'], ' ·')], $data
        )]];
    }
}
