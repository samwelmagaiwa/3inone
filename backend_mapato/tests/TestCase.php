<?php

namespace Tests;

use App\Models\User;
use App\Services\ServiceAssignment;
use App\Services\Sms\SmsGateway;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use Tests\Support\FakeSmsGateway;

abstract class TestCase extends BaseTestCase
{
    /** Every text message the app "sent" during the test. Nothing ever reaches a real provider. */
    protected FakeSmsGateway $sms;

    protected function setUp(): void
    {
        parent::setUp();

        $this->sms = new FakeSmsGateway();
        $this->app->instance(SmsGateway::class, $this->sms);
    }

    protected function tearDown(): void
    {
        // The tenant context is static; never let one test's business leak into the next.
        TenantContext::reset();

        parent::tearDown();
    }

    /**
     * Give a user services, as a super admin does in real life. The API only
     * serves a service to users who have been given it, so a test that calls
     * a service's routes as an admin must say which service that admin has.
     *
     * A business owner given inventory also gets its own settings and default
     * crate types, exactly as when a super admin assigns the service.
     */
    protected function givenServices(User $user, string ...$services): User
    {
        foreach ($services as $service) {
            $user->services()->firstOrCreate(['service_type' => $service]);
        }

        app(ServiceAssignment::class)->prepareServices($user);

        return $user;
    }

    /**
     * Make $business the owner of any raw rows the test writes (and the scope of
     * any it reads) while nobody is signed in. Requests are unaffected: the
     * signed-in user always wins.
     */
    protected function actAsBusiness(User $business): User
    {
        TenantContext::useDefaultBusiness($business);

        return $business;
    }
}
