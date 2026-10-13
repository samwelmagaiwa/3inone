<?php

namespace App\Rules;

use App\Models\Rental\Block;
use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

/**
 * A block id that really is a block of the given property. `exists:rental_blocks,id`
 * accepts any block in the system, so a house could be filed under a block that
 * belongs to a different landlord's property.
 */
class BlockOnProperty implements ValidationRule
{
    /** @param mixed $propertyId straight from the request, so it may not be a string */
    public function __construct(private readonly mixed $propertyId)
    {
    }

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if (!is_scalar($this->propertyId)
            || !is_scalar($value)
            || !Block::where('id', $value)->where('property_id', $this->propertyId)->exists()) {
            $fail('The selected block does not belong to this property.');
        }
    }
}
