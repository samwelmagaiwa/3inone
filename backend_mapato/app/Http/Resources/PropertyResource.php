<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class PropertyResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $housesCount = $this->whenLoaded('houses', fn() => $this->houses->count(), 0);

        return [
            'id' => $this->id,
            'name' => $this->name,
            'property_type' => $this->property_type,
            'property_type_display' => $this->formatPropertyType($this->property_type),
            'region' => $this->region,
            'district' => $this->district,
            'ward' => $this->ward,
            'street' => $this->street,
            'place' => $this->place,
            'city' => $this->city,
            'location' => $this->location,
            'address' => $this->address,
            'full_address' => $this->full_address,
            'description' => $this->description,
            'billing_cycle' => $this->default_billing_cycle,
            'billing_cycle_display' => $this->formatBillingCycle($this->default_billing_cycle),
            'currency' => $this->default_currency,
            'status' => $this->status,
            'status_display' => $this->formatStatus($this->status),
            'total_units' => $housesCount ?: ($this->total_units ?? 0),
            'number_of_blocks' => $this->number_of_blocks ?? 1,
            'occupied_units' => $this->occupied_units_count,
            'vacant_units' => $this->vacant_units_count,
            'occupancy_rate' => $this->occupancy_rate,
            'cover_image' => $this->cover_image ? asset('storage/' . $this->cover_image) : null,
            'default_rent_amount' => $this->default_rent_amount,
            'default_deposit_amount' => $this->default_deposit_amount,
            'utility_billing_enabled' => $this->utility_billing_enabled ?? false,
            'branch_id' => $this->branch_id,
            'revenue_summary' => [
                'total_collected' => $this->total_revenue,
            ],
            'caretaker' => $this->when($this->caretaker_id, function () {
                return [
                    'id' => $this->caretaker?->id,
                    'name' => $this->caretaker?->name,
                    'phone' => $this->caretaker?->phone_number,
                ];
            }),
            'blocks' => $this->when($this->relationLoaded('blocks'), function () {
                return BlockResource::collection($this->blocks);
            }),
            'houses' => $this->when($this->relationLoaded('houses'), function () {
                return HouseResource::collection($this->houses);
            }),
            'recent_payments' => $this->when($request->routeIs('rental.properties.show'), function () {
                $payments = $this->recentPayments(5);
                return $payments->map(fn($p) => [
                    'id' => $p->id,
                    'amount' => $p->amount_paid,
                    'date' => $p->payment_date?->toDateString(),
                    'tenant' => $p->tenant?->name ?? 'N/A',
                    'house' => $p->bill?->agreement?->house?->house_number ?? 'N/A',
                    'method' => $p->payment_method,
                ]);
            }),
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }

    private function formatPropertyType(?string $type): string
    {
        if (!$type)
            return '';
        return ucwords(str_replace('_', ' ', $type));
    }

    private function formatBillingCycle(?string $cycle): string
    {
        return match ($cycle) {
            'monthly' => 'Mwezi',
            'quarterly' => 'Robo Mwaka',
            'yearly' => 'Mwaka',
            default => $cycle ?? '',
        };
    }

    private function formatStatus(?string $status): string
    {
        return match ($status) {
            'active' => 'Hai',
            'inactive' => 'Si Hai',
            'under_maintenance' => 'Kwenye Matengenezo',
            'archived' => 'Imehifadhiwa',
            default => $status ?? '',
        };
    }
}

class BlockResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'description' => $this->description,
            // Use pre-computed withCount('houses') to avoid a query per block
            'houses_count' => $this->houses_count ?? 0,
        ];
    }
}

class HouseResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'house_number' => $this->house_number,
            'type' => $this->type,
            'rent_amount' => $this->rent_amount,
            'deposit_amount' => $this->deposit_amount,
            'status' => $this->status,
            'status_display' => $this->formatStatus($this->status),
            'bedrooms' => $this->bedrooms,
            'bathrooms' => $this->bathrooms,
            'floor' => $this->floor,
            'billing_cycle' => $this->billing_cycle,
            'currency' => $this->currency,
            'utility_billing_enabled' => $this->utility_billing_enabled,
            'ownership_notes' => $this->ownership_notes,
            'current_tenant' => $this->when($this->currentTenant, function () {
                return [
                    'id' => $this->currentTenant->id,
                    'name' => $this->currentTenant->name,
                    'phone' => $this->currentTenant->phone_number,
                ];
            }),
        ];
    }

    private function formatStatus(?string $status): string
    {
        return match ($status) {
            'vacant' => 'Wazi',
            'occupied' => 'Imekalia',
            'maintenance' => 'Matengenezo',
            'reserved' => 'Hifadhi',
            default => $status ?? '',
        };
    }
}