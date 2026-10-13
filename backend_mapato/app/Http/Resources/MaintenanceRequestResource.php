<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class MaintenanceRequestResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'category' => $this->category,
            'priority' => $this->priority,
            'priority_display' => $this->formatPriority($this->priority),
            'description' => $this->description,
            'status' => $this->status,
            'status_display' => $this->formatStatus($this->status),
            'photo_url' => \App\Support\PrivateFile::url($this->photo_url),
            'resolved_at' => $this->resolved_at?->toIso8601String(),
            'created_at' => $this->created_at?->toIso8601String(),
            'property' => [
                'id' => $this->property?->id,
                'name' => $this->property?->name,
            ],
            'house' => [
                'id' => $this->house?->id,
                'house_number' => $this->house?->house_number,
            ],
            'tenant' => [
                'id' => $this->tenant?->id,
                'name' => $this->tenant?->name,
                'phone' => $this->tenant?->phone_number,
            ],
            'work_order' => new WorkOrderResource($this->whenLoaded('workOrder')),
        ];
    }

    private function formatPriority(string $p): string
    {
        return match ($p) {
            'low' => 'Chini',
            'medium' => 'Kati',
            'high' => 'Juu',
            'emergency' => 'Dharura',
            default => $p,
        };
    }

    private function formatStatus(string $s): string
    {
        return match ($s) {
            'open' => 'Wazi',
            'pending' => 'Inasubiri',
            'in_progress' => 'Inafanyiwa Kazi',
            'resolved' => 'Imeisha',
            'cancelled' => 'Imeahirishwa',
            default => $s,
        };
    }
}
