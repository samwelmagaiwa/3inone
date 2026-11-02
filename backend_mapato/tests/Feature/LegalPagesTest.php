<?php

namespace Tests\Feature;

use Tests\TestCase;

/** The home page, privacy policy and terms Google requires before the app can be published: public, in both languages, no sign-in. */
class LegalPagesTest extends TestCase
{
    public function test_the_three_pages_are_public_and_say_what_they_are(): void
    {
        $this->get('/about')->assertOk()->assertSee('3 in One')->assertSee('About (English)', false);
        $this->get('/privacy')->assertOk()->assertSee('Sera ya faragha')->assertSee('Privacy policy (English)', false)->assertSee('jina lako na anwani ya barua pepe', false);
        $this->get('/terms')->assertOk()->assertSee('Masharti ya matumizi')->assertSee('Terms of use (English)', false);
    }
}
