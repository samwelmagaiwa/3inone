<?php

namespace App\Services\Rental;

use App\Models\Rental\Property;
use App\Models\Rental\House;
use App\Models\User;
use Illuminate\Support\Facades\DB;

class PropertyService
{
    /** Who a new property is recorded against: the head of the caller's account. */
    protected ?string $ownerId = null;

    /** Every owner id the caller may see properties of: the head plus their staff. */
    protected ?array $ownerIds = null;

    // super_admin sees every landlord's data, not just their own -- every
    // query below skips the owner_id filter entirely when this is true,
    // rather than scoping to a super_admin's own (typically empty) portfolio.
    protected bool $unrestricted = false;

    /**
     * Scope the service to a signed-in user's account: properties are owned by
     * the account head (a landlord or admin), and everyone in that account --
     * including staff -- works on the same portfolio.
     */
    public function forUser(User $user): self
    {
        $this->ownerId = $user->accountHeadId();
        $this->ownerIds = $user->accountMemberIds();
        $this->unrestricted = $user->seesAllAccounts();

        return $this;
    }

    public function setOwner(string $ownerId): self
    {
        $this->ownerId = $ownerId;
        $this->ownerIds = [$ownerId];
        return $this;
    }

    public function setUnrestricted(bool $unrestricted = true): self
    {
        $this->unrestricted = $unrestricted;
        return $this;
    }

    protected function getOwnerId(): string
    {
        return $this->ownerId ?? (auth()->user() instanceof User ? auth()->user()->accountHeadId() : auth()->id());
    }

    /** @return array<int, string> */
    protected function getOwnerIds(): array
    {
        return $this->ownerIds ?? [$this->getOwnerId()];
    }

    /**
     * Get all properties for a landlord with pagination and filters.
     */
    public function getAll(array $filters, int $perPage = 15)
    {
        $query = Property::with(['blocks' => fn($q) => $q->withCount('houses'), 'houses.currentTenant', 'caretaker'])
            ->when(!$this->unrestricted, fn($q) => $q->whereIn('owner_id', $this->getOwnerIds()));

        // Search filter
        if (!empty($filters['search'])) {
            $search = $filters['search'];
            $query->where(function ($q) use ($search) {
                $q->where('name', 'like', "%{$search}%")
                    ->orWhere('address', 'like', "%{$search}%")
                    ->orWhere('region', 'like', "%{$search}%")
                    ->orWhere('district', 'like', "%{$search}%");
            });
        }

        // Status filter
        if (!empty($filters['status'])) {
            $query->where('status', $filters['status']);
        }

        // Property type filter
        if (!empty($filters['property_type'])) {
            $query->where('property_type', $filters['property_type']);
        }

        // Sorting
        $sortBy = $filters['sort_by'] ?? 'created_at';
        $sortOrder = $filters['sort_order'] ?? 'desc';
        $query->orderBy($sortBy, $sortOrder);

        return $query->paginate($perPage);
    }

    /**
     * Get single property with full details.
     */
    public function getById(string $id): Property
    {
        return Property::with(['blocks' => fn($q) => $q->withCount('houses'), 'houses.currentTenant', 'caretaker'])
            ->when(!$this->unrestricted, fn($q) => $q->whereIn('owner_id', $this->getOwnerIds()))
            ->findOrFail($id);
    }

    /**
     * Create a new property.
     */
    public function create(array $data): Property
    {
        return DB::transaction(function () use ($data) {
            // Handle cover image
            if (isset($data['cover_image']) && $data['cover_image'] instanceof \Illuminate\Http\UploadedFile) {
                $path = $data['cover_image']->store('properties', 'public');
                $data['cover_image'] = $path;
            }

            $property = Property::create(array_merge($data, [
                'owner_id' => $this->getOwnerId(),
                'status' => $data['status'] ?? 'active',
                'default_currency' => $data['currency'] ?? 'TZS',
                'default_billing_cycle' => $data['billing_cycle'] ?? 'monthly',
                'number_of_blocks' => $data['number_of_blocks'] ?? 1,
                'total_units' => $data['total_units'] ?? 0,
            ]));

            return $property;
        });
    }

    /**
     * Update an existing property.
     */
    public function update(string $id, array $data): Property
    {
        $property = $this->getById($id);

        // Handle cover image update
        if (isset($data['cover_image']) && $data['cover_image'] instanceof \Illuminate\Http\UploadedFile) {
            // Delete old image if exists
            if ($property->cover_image) {
                \Illuminate\Support\Facades\Storage::disk('public')->delete($property->cover_image);
            }
            $path = $data['cover_image']->store('properties', 'public');
            $data['cover_image'] = $path;
        }

        $property->update($data);

        return $property->fresh(['blocks', 'houses', 'caretaker']);
    }

    /**
     * Delete a property (soft delete).
     */
    public function delete(string $id): bool
    {
        return DB::transaction(function () use ($id) {
            $property = $this->getById($id);

            // Check if any house is occupied
            $occupiedCount = $property->houses()->where('status', 'occupied')->count();
            if ($occupiedCount > 0) {
                throw new \Exception('Huwezi kufuta jengo lenye wapangaji. Tafadhali sitisha mikataba kwanza.');
            }

            // Cascade soft-delete to houses
            $property->houses()->delete();

            // Cascade soft-delete to blocks
            $property->blocks()->delete();

            // Soft-delete the property itself
            $property->delete();

            return true;
        });
    }

    /**
     * Get property statistics.
     */
    public function getStatistics(): array
    {
        $properties = Property::when(!$this->unrestricted, fn($q) => $q->whereIn('owner_id', $this->getOwnerIds()))->get();

        $totalProperties = $properties->count();
        $totalUnits = $properties->sum('total_units');

        $occupiedUnits = House::whereHas('property', function ($query) {
            $query->when(!$this->unrestricted, fn($q) => $q->whereIn('owner_id', $this->getOwnerIds()));
        })->where('status', 'occupied')->count();

        $vacantUnits = $totalUnits - $occupiedUnits;

        $activeProperties = $properties->where('status', 'active')->count();
        $maintenanceProperties = $properties->where('status', 'under_maintenance')->count();

        return [
            'total_properties' => $totalProperties,
            'total_units' => $totalUnits,
            'occupied_units' => $occupiedUnits,
            'vacant_units' => $vacantUnits,
            'occupancy_rate' => $totalUnits > 0 ? round(($occupiedUnits / $totalUnits) * 100, 1) : 0,
            'active_properties' => $activeProperties,
            'maintenance_properties' => $maintenanceProperties,
        ];
    }

    /**
     * Restore a soft-deleted property.
     */
    public function restore(string $id): Property
    {
        $property = Property::withTrashed()
            ->when(!$this->unrestricted, fn($q) => $q->whereIn('owner_id', $this->getOwnerIds()))
            ->findOrFail($id);

        $property->restore();

        return $property;
    }

    /**
     * Get deleted properties.
     */
    public function getDeleted()
    {
        return Property::onlyTrashed()
            ->when(!$this->unrestricted, fn($q) => $q->whereIn('owner_id', $this->getOwnerIds()))
            ->get();
    }
}