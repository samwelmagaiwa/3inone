<?php

namespace App\Rules;

use App\Models\User;
use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

/**
 * A user id that belongs to the caller's own account -- themself, or someone
 * they or their staff created. `exists:users,id` would accept anyone's id, so
 * a landlord could name a stranger as caretaker and hand them the portfolio.
 *
 * Usage: 'caretaker_id' => ['nullable', new UserInAccount($this->user())]
 *
 * $unchanged is the value already stored: re-submitting it is always allowed, so
 * a record that predates this rule can still be edited without touching that field.
 */
class UserInAccount implements ValidationRule
{
    public function __construct(
        private readonly ?User $viewer,
        private readonly ?string $unchanged = null,
    ) {
    }

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if ($this->unchanged !== null && (string) $value === $this->unchanged) {
            return;
        }

        if (!$this->viewer
            || !is_scalar($value)
            || !User::query()->inAccountOf($this->viewer)->whereKey($value)->exists()) {
            $fail('The selected :attribute is invalid.');
        }
    }
}
