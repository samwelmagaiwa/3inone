<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class WorkOrderResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'title' => $this->title,
            'instructions' => $this->instructions,
            'estimated_cost' => $this->estimated_cost,
            'actual_cost' => $this->actual_cost,
            'status' => $this->status,
            'status_display' => $this->formatStatus($this->status),
            'scheduled_date' => $this->scheduled_date?->toDateString(),
            'completion_date' => $this->completion_date?->toDateString(),
            'vendor' => new VendorResource($this->whenLoaded('vendor')),
        ];
    }

    private function formatStatus(string $s): string
    {
        return match ($s) {
            'draft' => 'Rasimu',
            'scheduled' => 'Imepangwa',
            'in_progress' => 'Inafanyiwa Kazi',
            'completed' => 'Imeisha',
            'cancelled' => 'Imeahirishwa',
            default => $s,
        };
    }
}
