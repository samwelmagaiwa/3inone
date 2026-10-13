<?php

namespace App\Rules;

use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

/**
 * `exists:table,id` proves a row exists *anywhere*, so it happily accepts the
 * id of a record that belongs to a different account. This rule asks the model
 * instead, which means its account scope applies: an id the caller may not see
 * fails validation exactly like one that does not exist.
 *
 * Usage: 'driver_id' => ['required', new InAccount(Driver::class)]
 */
class InAccount implements ValidationRule
{
    /** @param class-string<\Illuminate\Database\Eloquent\Model> $model */
    public function __construct(
        private readonly string $model,
        private readonly string $column = 'id',
    ) {
    }

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if (!is_scalar($value) || !$this->model::query()->where($this->column, $value)->exists()) {
            $fail('The selected :attribute is invalid.');
        }
    }
}
