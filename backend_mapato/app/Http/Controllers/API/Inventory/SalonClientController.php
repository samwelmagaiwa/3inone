<?php

namespace App\Http\Controllers\API\Inventory;

use App\Models\Business;
use App\Services\SmsService;
use App\Support\PrivateFile;
use App\Support\Salon\AppointmentPlanner;
use App\Support\Salon\ClientSegments;
use App\Support\Salon\SalonAccess;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use OpenApi\Attributes as OA;

/**
 * What a salon remembers about its clients and what it says to them: how they like their hair, their birthday, photos of
 * past styles (only with their consent), who sent them, who is new, who comes back, who has gone quiet, and messages to
 * a group of them. Texts always respect "do not text me" and go out under the salon's own sender name.
 */
#[OA\Tag(name: 'Inventory / Salon', description: 'Salon clients: preferences, photos, groups and messages')]
class SalonClientController extends Controller
{
    private function today(): Carbon
    {
        return Carbon::now(AppointmentPlanner::TIMEZONE)->startOfDay();
    }

    private function requireManager(Request $request): void
    {
        abort_unless(SalonAccess::isManager($request->user()), 403, 'Ni mmiliki au meneja tu anayeweza kufanya hivi. / Only the owner or a manager can do this.');
    }

    // ------------------------------------------------------------------ photos

    #[OA\Get(path: '/inventory/salon/clients/{id}/photos', summary: 'Photos of a client\'s past styles (shown only with consent)', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function photos(int $id): JsonResponse
    {
        abort_if(DB::table('inventory_customers')->where('id', $id)->doesntExist(), 404, 'Client not found');

        $rows = DB::table('inventory_client_photos')->where('customer_id', $id)->where('consent', true)->orderByDesc('taken_on')->orderByDesc('id')->get()
            ->map(fn ($p) => ['id' => (int) $p->id, 'url' => PrivateFile::url($p->path), 'caption' => $p->caption, 'taken_on' => Carbon::parse($p->taken_on)->toDateString()])
            ->values();

        return response()->json(['data' => $rows]);
    }

    #[OA\Post(path: '/inventory/salon/clients/{id}/photos', summary: 'Keep a photo of a style, with the client\'s consent', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 201, description: 'Created')])]
    public function storePhoto(Request $request, int $id): JsonResponse
    {
        abort_if(DB::table('inventory_customers')->where('id', $id)->doesntExist(), 404, 'Client not found');
        $data = $request->validate([
            'photo' => 'required|file|image|mimes:jpg,jpeg,png|max:5120',
            'caption' => 'nullable|string|max:120',
            'consent' => 'required|accepted',
        ]);

        $path = PrivateFile::store($request->file('photo'), 'salon_client_photos');
        $photoId = DB::table('inventory_client_photos')->insertGetId([
            'customer_id' => $id,
            'path' => $path,
            'caption' => !empty($data['caption']) ? trim($data['caption']) : null,
            'consent' => true,
            'taken_on' => $this->today()->toDateString(),
            'created_by' => (string) $request->user()->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return response()->json(['message' => 'Photo kept', 'data' => ['id' => (int) $photoId, 'url' => PrivateFile::url($path)]], 201);
    }

    #[OA\Delete(path: '/inventory/salon/photos/{id}', summary: 'Delete a client photo', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function destroyPhoto(int $id): JsonResponse
    {
        $photo = DB::table('inventory_client_photos')->find($id);
        abort_if($photo === null, 404, 'Photo not found');
        Storage::disk(PrivateFile::DISK)->delete($photo->path);
        DB::table('inventory_client_photos')->where('id', $id)->delete();

        return response()->json(['message' => 'Deleted']);
    }

    // ------------------------------------------------------------------ the clients at a glance

    #[OA\Get(path: '/inventory/salon/clients/overview', summary: 'New and returning clients, birthdays this month, those gone quiet', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function overview(Request $request): JsonResponse
    {
        $data = $request->validate(['inactive_weeks' => 'nullable|integer|min:1|max:104']);
        $today = $this->today();
        $weeks = (int) ($data['inactive_weeks'] ?? ClientSegments::DEFAULT_INACTIVE_WEEKS);
        $pick = fn (string $segment) => ClientSegments::members($segment, $today, $weeks);

        $birthdays = $pick(ClientSegments::BIRTHDAY)
            ->sortBy(fn ($c) => substr((string) $c['birthday'], 5))
            ->map(fn ($c) => ['id' => $c['id'], 'name' => $c['name'], 'birthday' => $c['birthday'], 'phone' => $c['phone']])
            ->values();

        return response()->json(['data' => [
            'total' => ClientSegments::clients()->count(),
            'new' => $pick(ClientSegments::NEW)->count(),
            'returning' => $pick(ClientSegments::RETURNING)->count(),
            'inactive' => $pick(ClientSegments::INACTIVE)->count(),
            'inactive_weeks' => $weeks,
            'birthdays' => $birthdays,
            'top_spenders' => $pick(ClientSegments::TOP)->map(fn ($c) => ['id' => $c['id'], 'name' => $c['name'], 'spent' => $c['spent'], 'visits' => $c['visits']])->values(),
        ]]);
    }

    // ------------------------------------------------------------------ messages to a group

    #[OA\Get(path: '/inventory/salon/campaigns', summary: 'The groups a message can go to (with how many it would reach) and the messages sent', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function campaigns(Request $request): JsonResponse
    {
        $this->requireManager($request);
        $data = $request->validate(['inactive_weeks' => 'nullable|integer|min:1|max:104']);
        $today = $this->today();
        $weeks = (int) ($data['inactive_weeks'] ?? ClientSegments::DEFAULT_INACTIVE_WEEKS);

        $segments = collect(ClientSegments::SEGMENTS)->map(fn (string $s) => [
            'segment' => $s,
            'members' => ClientSegments::members($s, $today, $weeks)->count(),
            'reachable' => ClientSegments::textable($s, $today, $weeks)->count(),
        ])->values();

        $sent = DB::table('inventory_campaigns')->orderByDesc('id')->limit(30)->get()->map(fn ($c) => [
            'id' => (int) $c->id,
            'name' => $c->name,
            'segment' => $c->segment,
            'message' => $c->message,
            'recipients' => (int) $c->recipients,
            'sent' => (int) $c->sent,
            'at' => Carbon::parse($c->created_at)->format('Y-m-d H:i'),
        ])->values();

        return response()->json(['data' => ['segments' => $segments, 'campaigns' => $sent, 'max_per_message' => self::MAX_RECIPIENTS, 'inactive_weeks' => $weeks]]);
    }

    /** More than this in one message is a mistake, not a campaign (and a big SMS bill). */
    private const MAX_RECIPIENTS = 300;

    #[OA\Post(path: '/inventory/salon/campaigns', summary: 'Text a group of clients ({name} becomes their first name)', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 201, description: 'Created')])]
    public function sendCampaign(Request $request): JsonResponse
    {
        $this->requireManager($request);
        abort_if($request->user()->seesAllAccounts(), 403, 'Tuma ujumbe kutoka kwenye akaunti ya saluni yenyewe. / Send messages from the salon\'s own account.');
        $data = $request->validate([
            'name' => 'nullable|string|max:120',
            'segment' => ['required', Rule::in(ClientSegments::SEGMENTS)],
            'message' => 'required|string|min:5|max:320',
            'inactive_weeks' => 'nullable|integer|min:1|max:104',
        ]);

        $recipients = ClientSegments::textable($data['segment'], $this->today(), isset($data['inactive_weeks']) ? (int) $data['inactive_weeks'] : null);
        if ($recipients->isEmpty()) {
            throw ValidationException::withMessages(['segment' => ['Hakuna mteja wa kumtumia ujumbe katika kundi hili. / Nobody in this group can be texted.']]);
        }
        if ($recipients->count() > self::MAX_RECIPIENTS) {
            throw ValidationException::withMessages(['segment' => ['Kundi ni kubwa mno (zaidi ya ' . self::MAX_RECIPIENTS . '). / This group is too big to message at once (over ' . self::MAX_RECIPIENTS . ').']]);
        }

        $business = Business::forUser($request->user());
        $sent = 0;
        foreach ($recipients as $client) {
            $text = trim(str_replace('{name}', ClientSegments::firstName($client['name']), $data['message']));
            if (SmsService::sendFor($business, $client['phone'], $text)) {
                $sent++;
            }
        }

        $id = DB::table('inventory_campaigns')->insertGetId([
            'name' => !empty($data['name']) ? trim($data['name']) : $data['segment'],
            'segment' => $data['segment'],
            'message' => $data['message'],
            'recipients' => $recipients->count(),
            'sent' => $sent,
            'created_by' => (string) $request->user()->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return response()->json(['message' => 'Sent', 'data' => ['id' => (int) $id, 'recipients' => $recipients->count(), 'sent' => $sent]], 201);
    }
}
