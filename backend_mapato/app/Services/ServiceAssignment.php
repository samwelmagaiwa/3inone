<?php

namespace App\Services;

use App\Models\User;
use App\Models\UserService;
use App\Support\InventoryDefaults;

/**
 * Giving a user services (inventory / rental / transport). One place, so
 * approving a registration and editing an existing account follow the same rules.
 */
class ServiceAssignment
{
    /**
     * Replace the user's services with $services (and keep the legacy single
     * service_type column in step for older code paths).
     *
     * @param  array<int, string>  $services
     * @return array<int, string> the services now held
     */
    public function assign(User $target, array $services): array
    {
        $services = array_values(array_unique($services));

        $target->services()->delete();
        foreach ($services as $service) {
            UserService::create(['user_id' => $target->id, 'service_type' => $service]);
        }
        $target->unsetRelation('services');
        $target->service_type = $services[0] ?? null;
        $target->forgetAccountCache();

        $this->prepareServices($target);

        return $services;
    }

    /**
     * Whatever a business needs in place once it holds a service. For inventory
     * that is its own settings and default crate types, so its first sale works
     * and nothing is borrowed from another business. Harmless to repeat.
     */
    public function prepareServices(User $user): void
    {
        $isOwner = in_array(strtolower((string) $user->role), User::ACCOUNT_HEAD_ROLES, true);

        if ($isOwner && $user->services()->where('service_type', 'inventory')->exists()) {
            InventoryDefaults::seedFor($user);
        }
    }
}
