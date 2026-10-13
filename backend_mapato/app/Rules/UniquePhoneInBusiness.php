<?php

namespace App\Rules;

use App\Models\User;
use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

/**
 * A phone number may belong to only one person INSIDE a business (staff, drivers, tenants it
 * created and its owner), but another business may have its own person on the same number: a
 * driver who changed employer, a family's shared phone.
 *
 * Numbers are compared by their last nine digits, the way sign-in compares them, so
 * "0743 519 100" and "+255743519100" are the same number.
 *
 * The users table has no business column (a person's business is worked out from who created
 * them), so this checks the business's own people in PHP rather than with a database index.
 */
class UniquePhoneInBusiness implements ValidationRule
{
    /**
     * @param  string|null  $ownerId     the business (account head's user id) the number would be used in;
     *                                   null means no business yet (a brand-new owner), so nothing can clash.
     * @param  string|null  $ignoreUserId  the user being edited
     */
    public function __construct(
        private readonly ?string $ownerId,
        private readonly ?string $ignoreUserId = null,
    ) {
    }

    public static function lastNine(?string $phone): string
    {
        return substr(preg_replace('/\D/', '', (string) $phone) ?? '', -9);
    }

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if ($this->taken((string) $value)) {
            $fail('This phone number is already used by someone in your business. / Namba hii ya simu tayari inatumiwa na mtu mwingine katika biashara yako.');
        }
    }

    /** Is $phone already used inside the business (apart from the ignored user)? */
    public function taken(string $phone): bool
    {
        return $this->findUser($phone) !== null;
    }

    /**
     * The person inside the business who already uses $phone (apart from the ignored user), or
     * null. Also how a service recognises "this is someone of mine" by phone without ever
     * matching a same-numbered person in another business.
     */
    public function findUser(string $phone): ?User
    {
        $wanted = self::lastNine($phone);
        if ($wanted === '' || $this->ownerId === null) {
            return null;
        }

        $head = User::query()->find($this->ownerId);
        if ($head === null) {
            return null;
        }

        $members = $head->accountMemberIds();

        $query = User::query()
            ->whereNotNull('phone_number')
            ->where(function ($q) use ($members) {
                // The head and staff, plus the drivers / tenants / vendors they created.
                $q->whereIn('id', $members)->orWhereIn('created_by', $members);
            });

        if ($this->ignoreUserId !== null) {
            $query->where('id', '!=', $this->ignoreUserId);
        }

        foreach ($query->get(['id', 'phone_number']) as $candidate) {
            if (self::lastNine($candidate->phone_number) === $wanted) {
                return User::query()->find($candidate->id);
            }
        }

        return null;
    }
}
