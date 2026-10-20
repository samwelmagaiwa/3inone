<?php

namespace App\Services;

use App\Models\Business;
use App\Models\User;
use App\Models\UserService;
use App\Support\InventoryDefaults;

/**
 * Giving a user services (inventory / rental / transport / salon). One place, so
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
     * (and salon) that is its own settings and default crate types, so its first sale works
     * and nothing is borrowed from another business. Harmless to repeat.
     */
    public function prepareServices(User $user): void
    {
        $isOwner = in_array(strtolower((string) $user->role), User::ACCOUNT_HEAD_ROLES, true);

        $held = $user->services()->pluck('service_type')->all();

        // Salon runs on the inventory engine, so it needs the same starting settings. A salon has no crates and
        // no wholesale: unless it also holds inventory (and chose a kind when registering), it starts as a
        // retail business, which is what those settings are made from.
        if ($isOwner && array_intersect(['inventory', 'salon'], $held) !== []) {
            if (in_array('salon', $held, true) && !in_array('inventory', $held, true)) {
                $business = Business::forUser($user);
                if ($business !== null && !$business->inventory_type) {
                    $business->inventory_type = 'retail';
                    $business->save();
                }
            }

            // Each service that holds the engine has its own settings: a shop's, a salon's.
            foreach (array_intersect(['inventory', 'salon'], $held) as $service) {
                InventoryDefaults::seedFor($user, $service);
            }
        }
    }
}
