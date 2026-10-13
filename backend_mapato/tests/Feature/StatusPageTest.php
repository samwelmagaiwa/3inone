<?php

namespace Tests\Feature;

use Illuminate\Http\Request;
use Tests\TestCase;

/**
 * What a person sees when they open the server's address in a browser, and the health check programs use.
 */
class StatusPageTest extends TestCase
{
    public function test_the_address_shows_that_the_api_is_running(): void
    {
        $page = $this->get('/');

        $page->assertOk();
        $page->assertHeader('Content-Type', 'text/html; charset=UTF-8');
        $page->assertSee('3 in One API');
        $page->assertSee('The API is running');
        $page->assertSee('Online');
        foreach (['Transport', 'Rental', 'Inventory'] as $service) {
            $page->assertSee($service);
        }
    }

    public function test_it_shows_the_version_and_the_server_time_in_utc(): void
    {
        config(['app.api_version' => '9.8.7']);
        $this->travelTo(now()->setDate(2026, 10, 13)->setTime(9, 15, 30));

        $page = $this->get('/');

        $page->assertSee('9.8.7');
        $page->assertSee('2026-10-13 09:15:30');
        $page->assertSee('2026 3 in One', false);
    }

    public function test_it_links_to_the_health_check(): void
    {
        $this->get('/')->assertSee('href="/api/health"', false);
    }

    public function test_it_is_not_the_laravel_welcome_page_and_gives_nothing_away(): void
    {
        $html = $this->get('/')->getContent();

        $this->assertStringNotContainsString('Laravel', $html);
        $this->assertStringNotContainsString('laracasts', strtolower($html));
        $this->assertStringNotContainsString(PHP_VERSION, $html, 'the PHP version is nobody\'s business');
        $this->assertFalse(view()->exists('welcome'), 'the stock welcome view is gone');
    }

    public function test_search_engines_and_caches_are_told_to_leave_it_alone(): void
    {
        $page = $this->get('/');

        $page->assertHeader('X-Robots-Tag', 'noindex, nofollow');
        $this->assertStringContainsString('no-store', (string) $page->headers->get('Cache-Control'));
        $page->assertSee('<meta name="robots" content="noindex, nofollow">', false);
    }

    public function test_it_needs_no_session_so_it_answers_even_when_the_database_is_down(): void
    {
        // The session is kept in the database in production. A page that started one would fail with the
        // database, which is exactly when someone opens it to see whether the server is alive.
        $router = app('router');
        $route = $router->getRoutes()->match(Request::create('/'));
        $middleware = $router->gatherRouteMiddleware($route);

        foreach ([
            \Illuminate\Session\Middleware\StartSession::class,
            \Illuminate\View\Middleware\ShareErrorsFromSession::class,
            \Illuminate\Foundation\Http\Middleware\ValidateCsrfToken::class,
        ] as $needsSession) {
            $this->assertNotContains($needsSession, $middleware, "{$needsSession} would touch the session store");
        }

        $this->get('/')->assertOk()->assertCookieMissing(config('session.cookie'));
    }

    public function test_the_health_check_says_the_same_and_does_not_reveal_versions(): void
    {
        config(['app.api_version' => '9.8.7']);

        $health = $this->getJson('/api/health');

        $health->assertOk();
        $health->assertJsonPath('status', 'success');
        $health->assertJsonPath('message', '3 in One API is running');
        $health->assertJsonPath('version', '9.8.7');
        $health->assertJsonStructure(['status', 'message', 'timestamp', 'version', 'server_time']);
        $this->assertArrayNotHasKey('php_version', $health->json());
        $this->assertStringNotContainsString(PHP_VERSION, $health->getContent());
    }
}
