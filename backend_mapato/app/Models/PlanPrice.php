<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * What one plan costs when paid for a number of months. The platform's own price list: shown to anybody who is
 * about to register and written only by a super admin, so it belongs to no business (see TenancyGuardTest).
 */
class PlanPrice extends Model
{
    protected $fillable = ['plan', 'months', 'amount', 'updated_by'];

    protected $casts = [
        'months' => 'integer',
        'amount' => 'float',
    ];
}
