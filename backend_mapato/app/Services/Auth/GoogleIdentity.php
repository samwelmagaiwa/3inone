<?php

namespace App\Services\Auth;

use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\Http;

/**
 * Who Google says a person is. The phone sends the ID token Google gave it; this asks Google whether the token is real, was made for
 * THIS app, has not expired and carries a verified email. Nothing the phone says about itself is believed: the email and name come
 * from Google's answer, and the sign-up token handed back is sealed (encrypted) so a registration can prove it is that same person.
 */
class GoogleIdentity
{
    private const SIGNUP_MINUTES = 60;

    /** @return array{sub: string, email: string, name: string}|null null when the token is not acceptable */
    public function verify(string $idToken): ?array
    {
        try {
            $response = Http::timeout(8)->get('https://oauth2.googleapis.com/tokeninfo', ['id_token' => $idToken]);
        } catch (\Throwable) {
            return null;
        }
        if (!$response->ok()) {
            return null;
        }

        $claims = $response->json();
        if (!is_array($claims)) {
            return null;
        }

        $audiences = (array) config('services.google.client_ids', []);
        $issuer = (string) ($claims['iss'] ?? '');
        $verified = filter_var($claims['email_verified'] ?? false, FILTER_VALIDATE_BOOLEAN);
        $expires = (int) ($claims['exp'] ?? 0);

        if (!in_array((string) ($claims['aud'] ?? ''), $audiences, true)
            || !in_array($issuer, ['accounts.google.com', 'https://accounts.google.com'], true)
            || !$verified
            || $expires < time()
            || empty($claims['sub'])
            || empty($claims['email'])) {
            return null;
        }

        return [
            'sub' => (string) $claims['sub'],
            'email' => strtolower(trim((string) $claims['email'])),
            'name' => trim((string) ($claims['name'] ?? '')) ?: (string) strstr((string) $claims['email'], '@', true),
        ];
    }

    /** A sealed, short-lived proof that this person (sub + email + name) signed in with Google. */
    public function signupToken(array $identity): string
    {
        return Crypt::encryptString(json_encode($identity + ['until' => time() + self::SIGNUP_MINUTES * 60]));
    }

    /** @return array{sub: string, email: string, name: string}|null null for a forged, damaged or expired token */
    public function readSignupToken(string $token): ?array
    {
        try {
            $data = json_decode(Crypt::decryptString($token), true);
        } catch (\Throwable) {
            return null;
        }

        if (!is_array($data) || ($data['until'] ?? 0) < time() || empty($data['sub']) || empty($data['email'])) {
            return null;
        }

        return ['sub' => (string) $data['sub'], 'email' => (string) $data['email'], 'name' => (string) ($data['name'] ?? '')];
    }
}
