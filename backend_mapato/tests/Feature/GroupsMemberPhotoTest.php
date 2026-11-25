<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Groups\GroupAccess;
use App\Support\PrivateFile;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * Groups (Vikundi): every member (a leader too) sets their own profile photo, and the photo link shows in the register and in "me".
 */
class GroupsMemberPhotoTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;

    /** @var array<string, User> */
    private array $people = [];

    /** @var array<string, int> */
    private array $ids = [];

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake(PrivateFile::DISK);
        $this->withoutMiddleware(ThrottleRequests::class);
        $this->owner = $this->givenServices(User::factory()->create(['name' => 'MEG Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0711000999']), 'groups');
        Business::forOwnerId($this->owner->id)->update(['name' => 'MEG Group']);
        foreach ([['asha', '0713000001'], ['juma', '0713000002']] as [$key, $phone]) {
            $id = $this->api($this->owner, 'POST', '/members', ['full_name' => ucfirst($key) . ' Member', 'phone' => $phone, 'existing' => true])->assertCreated()->json('data.member.id');
            $this->api($this->owner, 'POST', "/members/{$id}/sign-in")->assertCreated();
            $this->ids[$key] = $id;
            $this->people[$key] = User::query()->find(DB::table('group_members')->where('id', $id)->value('user_id'));
        }
    }

    /** A real PNG of [size] pixels a side (fake images need the GD extension, which the test image may not have). */
    private function png(string $name, int $size = 300): UploadedFile
    {
        $path = tempnam(sys_get_temp_dir(), 'png');
        file_put_contents($path, \App\Support\Groups\DemoGroup::solidPng($size));

        return new UploadedFile($path, $name, 'image/png', null, true);
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        GroupAccess::forget();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, '/api/groups' . $uri, $body);
    }

    public function test_an_ordinary_member_sets_their_own_photo_and_it_shows_in_me_and_the_register(): void
    {
        $r = $this->api($this->people['asha'], 'POST', '/members/me/photo', ['file' => $this->png('me.png', 400)]);
        $r->assertCreated();
        $url = $r->json('data.photo_url');
        $this->assertStringContainsString('/files/private/group_documents/', $url);

        $this->assertSame($url !== null, true);
        $this->assertNotNull($this->api($this->people['asha'], 'GET', '/me')->assertOk()->json('data.member.photo_url'));
        $row = collect($this->api($this->owner, 'GET', '/members')->assertOk()->json('data.members'))->firstWhere('id', $this->ids['asha']);
        $this->assertNotNull($row['photo_url']);
        $other = collect($this->api($this->owner, 'GET', '/members')->json('data.members'))->firstWhere('id', $this->ids['juma']);
        $this->assertNull($other['photo_url']);
    }

    public function test_the_same_photo_rules_apply_and_nobody_can_set_another_members_photo_this_way(): void
    {
        $this->api($this->people['asha'], 'POST', '/members/me/photo', ['file' => $this->png('tiny.png', 50)])->assertStatus(422)->assertJsonPath('code', 'photo_too_small');
        $this->api($this->people['asha'], 'POST', '/members/me/photo', ['file' => UploadedFile::fake()->create('paper.pdf', 100, 'application/pdf')])->assertStatus(422);
        $this->api($this->people['asha'], 'POST', '/members/me/photo', [])->assertStatus(422);

        // It only ever touches the caller's own file.
        $this->api($this->people['asha'], 'POST', '/members/me/photo', ['file' => $this->png('me.png', 300), 'member_id' => $this->ids['juma']])->assertCreated();
        $this->assertNull(DB::table('group_members')->where('id', $this->ids['juma'])->value('photo_path'));
        $this->assertNotNull(DB::table('group_members')->where('id', $this->ids['asha'])->value('photo_path'));
    }

    public function test_someone_who_is_not_a_member_cannot_use_it(): void
    {
        $stranger = $this->givenServices(User::factory()->create(['name' => 'Stranger', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0711555000']), 'groups');
        $this->api($stranger, 'POST', '/members/me/photo', ['file' => $this->png('me.png', 300)])->assertForbidden();
    }
}
