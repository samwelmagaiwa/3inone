<?php

namespace App\Support\Inventory;

use App\Models\User;
use App\Support\Salon\SalonAccess;
use App\Support\Tenancy\TenantContext;

/** Who sees every sale of the business and who sees only the sales they made themselves. One rule for the sales screens and the AI assistant. */
final class SalesVisibility
{
    public static function seesAll(?User $user): bool
    {
        // (A salon's accountant works across everyone's sales; its stylists see only their own.)
        if (TenantContext::service() === 'salon' && $user !== null) {
            return SalonAccess::isManager($user);
        }

        return in_array(optional($user)->role, ['admin', 'super_admin', 'manager', 'accountant']);
    }
}
