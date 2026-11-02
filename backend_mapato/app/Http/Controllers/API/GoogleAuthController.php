<?php

namespace App\Http\Controllers\API;

use App\Helpers\ResponseHelper;
use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\Auth\GoogleIdentity;
use Illuminate\Http\Request;

/**
 * Sign in with Google. A person Google vouches for who already has an owner account is signed in (through the SAME checks as a password
 * login: approval, suspension, billing). Someone new gets a sealed sign-up token and is sent to the registration form, which no longer
 * asks for a password or user name: Google is both.
 */
class GoogleAuthController extends Controller
{
    public function __construct(private readonly GoogleIdentity $google, private readonly AuthController $auth)
    {
    }

    public function signIn(Request $request)
    {
        $data = $request->validate(['id_token' => 'required|string|max:4096']);

        $identity = $this->google->verify($data['id_token']);
        if ($identity === null) {
            return ResponseHelper::error(
                'Google haikuweza kuthibitisha akaunti yako. Jaribu tena. / Google could not confirm your account. Try again.',
                401,
                ['code' => 'google_token_invalid']
            );
        }

        $user = User::where('google_id', $identity['sub'])->first()
            ?? User::whereRaw('LOWER(email) = ?', [$identity['email']])->first();

        // Never seen before, or an application that was turned down and may be sent again: they register next.
        $rejected = $user !== null && !$user->is_active
            && $user->registration?->status === \App\Models\BusinessRegistration::REJECTED
            && ($user->google_id === null || $user->google_id === $identity['sub']);
        if ($user === null || $rejected) {
            return ResponseHelper::success([
                'status' => 'new_user',
                'email' => $identity['email'],
                'name' => $identity['name'],
                'signup_token' => $this->google->signupToken($identity),
            ], 'Karibu. Jaza taarifa za biashara yako. / Welcome. Fill in your business details.');
        }

        // An account that is already tied to another Google person is not theirs.
        if ($user->google_id !== null && $user->google_id !== $identity['sub']) {
            return ResponseHelper::error(
                'Barua pepe hii inatumika na akaunti nyingine ya Google. / This email belongs to another Google account.',
                403,
                ['code' => 'google_account_mismatch']
            );
        }

        // Tying Google to an account that was made with a password is allowed only for a business OWNER (someone who registered
        // themselves). Staff, drivers and the super admin are given their accounts with an email nobody proved they own, and anyone
        // could claim an unused address; they keep signing in with their password.
        if ($user->google_id === null) {
            if ($user->registration === null) {
                return ResponseHelper::error(
                    'Akaunti hii inaingia kwa barua pepe na nenosiri. Tumia "Ingia kwa email". / This account signs in with email and password. Use "Sign in with email".',
                    403,
                    ['code' => 'password_account']
                );
            }
            $user->google_id = $identity['sub'];
            $user->save();
        }

        return $this->auth->completeSignIn($request, $user, false);
    }
}
