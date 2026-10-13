<?php

namespace App\Providers;

use App\Models\User;
use App\Observers\UserObserver;
use App\Services\Sms\KilakonaSmsGateway;
use App\Services\Sms\LogSmsGateway;
use App\Services\Sms\SmsGateway;
use App\Support\SessionPolicy;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\URL;
use Illuminate\Support\ServiceProvider;
use Laravel\Sanctum\Sanctum;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        // What happens to a text message: a real provider, or just the log (see config/sms.php).
        $this->app->singleton(SmsGateway::class, fn () => match (config('sms.driver')) {
            'kilakona' => new KilakonaSmsGateway(),
            default => new LogSmsGateway(),
        });
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // Whoever heads an account is a business, and a business has its record (name, address,
        // TIN, logo, plan) from the moment its owner's login exists.
        User::observe(UserObserver::class);

        // The container sits behind aaPanel's nginx, which terminates TLS
        // and proxies to us over plain HTTP -- with no trusted-proxy config,
        // Laravel can't see the request was HTTPS, so asset()/url() (used by
        // the Swagger UI view for its CSS/JS/favicon links) generated
        // http:// URLs and got blocked as mixed content on the https:// page.
        // This is a single known HTTPS-only production domain, so forcing
        // the scheme is simpler and more reliable than trusting proxy
        // headers we don't control.
        if ($this->app->environment('production')) {
            URL::forceScheme('https');
        }

        // 10 attempts/minute per email+IP. Keeps shared-IP offices usable while
        // making password guessing against a known email impractical.
        RateLimiter::for('login', fn (Request $request) => Limit::perMinute(10)
            ->by(strtolower((string) $request->input('email')) . '|' . $request->ip()));

        // A deactivated account's existing tokens must stop working at once, on
        // every route, instead of waiting for the app's next background refresh. That
        // includes everyone working for a business that has been suspended: when the
        // OWNER is deactivated, so are their staff, drivers and tenants.
        Sanctum::authenticateAccessTokensUsing(
            fn ($accessToken, bool $isValid) => $isValid
                && (bool) ($accessToken->tokenable?->is_active)
                && $accessToken->tokenable->accountIsActive()
                // A device in regular use is never signed out; only one nobody has touched for
                // a very long time (see SessionPolicy).
                && !SessionPolicy::isIdle($accessToken)
        );
    }
}
