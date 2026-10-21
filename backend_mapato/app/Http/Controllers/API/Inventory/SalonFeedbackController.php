<?php

namespace App\Http\Controllers\API\Inventory;

use App\Models\User;
use App\Support\Salon\AppointmentPlanner;
use App\Support\Salon\SalonAccess;
use App\Support\Salon\SalonFeedback;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Routing\Controller;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use OpenApi\Attributes as OA;

/**
 * What clients say about the salon: ratings, comments and complaints. Staff can write one down for a client; clients can
 * send one themselves from the link in the text they get after a visit (the public part, with no sign-in). The owner and
 * managers see all of it and settle complaints; a stylist sees only what is about them.
 */
#[OA\Tag(name: 'Inventory / Salon', description: 'Salon feedback and complaints')]
class SalonFeedbackController extends Controller
{
    private function manager(Request $request): bool
    {
        return SalonAccess::isManager($request->user());
    }

    // ------------------------------------------------------------------ for the salon

    #[OA\Get(path: '/inventory/salon/feedback', summary: 'Ratings, comments and complaints with their averages', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'status' => ['nullable', Rule::in(['new', 'resolved'])],
            'kind' => ['nullable', Rule::in(['review', 'complaint'])],
            'from' => 'nullable|date',
            'to' => 'nullable|date|after_or_equal:from',
        ]);
        $manager = $this->manager($request);

        $base = DB::table('inventory_feedback as f')
            ->leftJoin('inventory_customers as c', 'c.id', '=', 'f.customer_id')
            ->when(!$manager, fn ($q) => $q->where('f.staff_id', (string) $request->user()->id))
            ->when(!empty($data['from']), fn ($q) => $q->whereDate('f.created_at', '>=', $data['from']))
            ->when(!empty($data['to']), fn ($q) => $q->whereDate('f.created_at', '<=', $data['to']));

        $rows = (clone $base)
            ->when(!empty($data['status']), fn ($q) => $q->where('f.status', $data['status']))
            ->when(!empty($data['kind']), fn ($q) => $q->where('f.kind', $data['kind']))
            ->orderByRaw("CASE WHEN f.status = 'new' THEN 0 ELSE 1 END")
            ->orderByDesc('f.id')
            ->limit(200)
            ->get(['f.*', 'c.name as customer_name', 'c.phone as customer_phone'])
            ->map(fn ($f) => [
                'id' => (int) $f->id,
                'kind' => $f->kind,
                'rating' => $f->rating === null ? null : (int) $f->rating,
                'message' => $f->message,
                'client' => $f->customer_name,
                // The owner and managers can ring the client back; a stylist sees the feedback about her, not the number.
                'client_phone' => $manager ? $f->customer_phone : null,
                'staff_id' => $f->staff_id,
                'staff_name' => $f->staff_name,
                'status' => $f->status,
                'resolution' => $f->resolution,
                'source' => $f->source,
                'at' => Carbon::parse($f->created_at)->format('Y-m-d H:i'),
            ])->values();

        $rated = (clone $base)->whereNotNull('f.rating');
        $avg = (clone $rated)->avg('f.rating');
        $byStaff = !$manager ? collect() : (clone $rated)->whereNotNull('f.staff_id')->groupBy('f.staff_id')
            ->selectRaw('f.staff_id as staff_id, MAX(f.staff_name) as name, AVG(f.rating) as average, COUNT(*) as ratings')
            ->orderByDesc(DB::raw('AVG(f.rating)'))
            ->get()
            ->map(fn ($r) => ['staff_id' => $r->staff_id, 'name' => $r->name, 'average' => round((float) $r->average, 1), 'ratings' => (int) $r->ratings])->values();

        return response()->json(['data' => [
            'summary' => [
                'average' => $avg === null ? null : round((float) $avg, 1),
                'ratings' => (clone $rated)->count(),
                'open_complaints' => (clone $base)->where('f.kind', 'complaint')->where('f.status', 'new')->count(),
                'total' => (clone $base)->count(),
                'by_staff' => $byStaff,
            ],
            'feedback' => $rows,
        ]]);
    }

    #[OA\Post(path: '/inventory/salon/feedback', summary: 'Write down what a client said', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 201, description: 'Created')])]
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'kind' => ['required', Rule::in(['review', 'complaint'])],
            'rating' => 'nullable|integer|between:1,5',
            'message' => 'nullable|string|max:500',
            'customer_id' => 'nullable|integer',
            'staff_id' => 'nullable|string|max:64',
        ]);
        $message = trim((string) ($data['message'] ?? ''));
        if ($data['kind'] === 'complaint' && $message === '') {
            throw ValidationException::withMessages(['message' => ['Andika malalamiko yalikuwa nini. / Write what the complaint is.']]);
        }
        if ($data['kind'] === 'review' && empty($data['rating']) && $message === '') {
            throw ValidationException::withMessages(['rating' => ['Chagua nyota au andika maoni. / Choose a rating or write a comment.']]);
        }
        if (!empty($data['customer_id']) && DB::table('inventory_customers')->where('id', $data['customer_id'])->doesntExist()) {
            throw ValidationException::withMessages(['customer_id' => ['That client does not exist.']]);
        }
        $staff = null;
        if (!empty($data['staff_id'])) {
            $staff = User::query()->whereIn('id', $request->user()->accountMemberIds())->where('id', $data['staff_id'])->first(['id', 'name']);
            if ($staff === null) {
                throw ValidationException::withMessages(['staff_id' => ['That person is not in this business.']]);
            }
        }

        $id = DB::table('inventory_feedback')->insertGetId([
            'customer_id' => $data['customer_id'] ?? null,
            'staff_id' => $staff ? (string) $staff->id : null,
            'staff_name' => $staff?->name,
            'kind' => $data['kind'],
            'rating' => $data['rating'] ?? null,
            'message' => $message === '' ? null : $message,
            'status' => 'new',
            'source' => 'staff',
            'created_by' => (string) $request->user()->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        if ($data['kind'] === 'complaint') {
            SalonFeedback::tellAboutComplaint((int) $id, (string) ($staff?->name ?? ''), $message, (string) $request->user()->id, SalonFeedback::who($data['customer_id'] ?? null));
        }

        return response()->json(['message' => 'Saved', 'data' => ['id' => (int) $id]], 201);
    }

    #[OA\Post(path: '/inventory/salon/feedback/{id}/resolve', summary: 'Say a complaint has been dealt with', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function resolve(Request $request, int $id): JsonResponse
    {
        abort_unless($this->manager($request), 403, 'Ni mmiliki au meneja tu anayeweza kufunga malalamiko. / Only the owner or a manager can close a complaint.');
        $data = $request->validate(['note' => 'nullable|string|max:255']);
        $row = DB::table('inventory_feedback')->find($id);
        abort_if($row === null, 404, 'Not found');
        if ($row->status === 'resolved') {
            throw ValidationException::withMessages(['status' => ['Hii imeshashughulikiwa. / This is already dealt with.']]);
        }
        DB::table('inventory_feedback')->where('id', $id)->update([
            'status' => 'resolved',
            'resolution' => !empty($data['note']) ? trim($data['note']) : null,
            'resolved_by' => (string) $request->user()->id,
            'resolved_at' => now(),
            'updated_at' => now(),
        ]);

        return response()->json(['message' => 'Resolved']);
    }

    // ------------------------------------------------------------------ for the client (nobody is signed in)

    #[OA\Get(path: '/public/salon/feedback/{token}', summary: 'Who is asking, for the page a client opens', tags: ['Public salon'], parameters: [new OA\Parameter(name: 'token', in: 'path', required: true, schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 200, description: 'Success'), new OA\Response(response: 404, description: 'Not a good link')])]
    public function show(string $token): JsonResponse
    {
        $info = SalonFeedback::lookup($token);
        abort_if($info === null, 404, 'Kiungo hiki si sahihi au kimeisha muda. / This link is not valid, or has expired.');

        return response()->json(['data' => $info]);
    }

    #[OA\Post(path: '/public/salon/feedback/{token}', summary: 'A client\'s rating, comment or complaint', tags: ['Public salon'], parameters: [new OA\Parameter(name: 'token', in: 'path', required: true, schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 201, description: 'Thank you'), new OA\Response(response: 422, description: 'Not a good link, or nothing said')])]
    public function answer(Request $request, string $token): JsonResponse
    {
        $data = $request->validate([
            'rating' => 'nullable|integer|between:1,5',
            'message' => 'nullable|string|max:500',
            'complaint' => 'sometimes|boolean',
        ]);
        SalonFeedback::submit($token, $data);

        return response()->json(['message' => 'Asante! / Thank you!'], 201);
    }

    /** The page itself: a few stars, a box, a button. Plain HTML that works on any phone, in Swahili and English. */
    public function page(string $token): Response
    {
        $info = SalonFeedback::lookup($token);
        $e = fn (?string $v) => htmlspecialchars((string) $v, ENT_QUOTES, 'UTF-8');
        $tokenJs = json_encode($token);

        if ($info === null) {
            $body = '<h1>Kiungo hiki kimeisha muda</h1><p>This link has already been used or has expired. / Kiungo hiki kimeshatumika au kimeisha muda.</p>';
        } else {
            $hello = $info['client'] ? $e($info['client']) : '';
            $who = $info['stylist'] ? ' (' . $e($info['stylist']) . ')' : '';
            $services = $info['services'] === [] ? '' : '<p class="svc">' . $e(implode(', ', $info['services'])) . '</p>';
            $body = <<<HTML
<h1>{$e($info['business'])}</h1>
<p>Habari {$hello}! Ulihudumiwa vipi{$who}? / Hello {$hello}! How was your visit{$who}?</p>
{$services}
<div id="stars" role="radiogroup" aria-label="rating">
  <button type="button" data-v="1">★</button><button type="button" data-v="2">★</button><button type="button" data-v="3">★</button><button type="button" data-v="4">★</button><button type="button" data-v="5">★</button>
</div>
<textarea id="msg" maxlength="500" rows="4" placeholder="Maoni yako / Your comment (hiari / optional)"></textarea>
<label class="chk"><input type="checkbox" id="complaint"> Nina malalamiko / I have a complaint</label>
<button id="send" type="button">Tuma / Send</button>
<p id="note" role="status"></p>
<script>
var rating = 0, token = {$tokenJs};
document.querySelectorAll('#stars button').forEach(function (b) {
  b.addEventListener('click', function () {
    rating = parseInt(b.dataset.v, 10);
    document.querySelectorAll('#stars button').forEach(function (x) { x.className = parseInt(x.dataset.v, 10) <= rating ? 'on' : ''; });
  });
});
var thanks = function () { document.body.innerHTML = '<main><h1>Asante! / Thank you!</h1><p>Tumepokea maoni yako. / We have your answer.</p></main>'; };
var key = 'fb_' + token;
var post = function (payload) {
  return fetch('/api/public/salon/feedback/' + encodeURIComponent(token), {
    method: 'POST', headers: {'Content-Type': 'application/json', 'Accept': 'application/json'}, body: JSON.stringify(payload)
  }).then(function (r) { return r.json().then(function (j) { return {ok: r.ok, j: j}; }); });
};
// No signal when the client pressed Send: the answer waits on the phone and goes by itself when the connection is back
// (the page must stay open or be opened again in the same browser).
var flush = function () {
  var saved = null;
  try { saved = JSON.parse(localStorage.getItem(key) || 'null'); } catch (e) {}
  if (!saved) return;
  post(saved).then(function (x) {
    if (x.ok || (x.j && x.j.errors)) { try { localStorage.removeItem(key); } catch (e) {} if (x.ok) thanks(); }
  }).catch(function () {});
};
window.addEventListener('online', flush);
flush();
document.getElementById('send').addEventListener('click', function () {
  var note = document.getElementById('note');
  var btn = this; btn.disabled = true;
  var payload = {rating: rating || null, message: document.getElementById('msg').value, complaint: document.getElementById('complaint').checked};
  post(payload).then(function (x) {
    if (x.ok) { try { localStorage.removeItem(key); } catch (e) {} thanks(); return; }
    var m = x.j && x.j.errors ? Object.values(x.j.errors)[0][0] : (x.j && x.j.message) || 'Imeshindikana / Failed';
    note.textContent = m; btn.disabled = false;
  }).catch(function () {
    try { localStorage.setItem(key, JSON.stringify(payload)); } catch (e) {}
    note.textContent = 'Hakuna mtandao. Jibu lako limehifadhiwa kwenye simu na litatumwa mtandao ukirudi (acha ukurasa huu wazi). / No connection. Your answer is saved on your phone and will be sent when you are back online (keep this page open).';
    btn.disabled = false;
  });
});
</script>
HTML;
        }

        $html = '<!doctype html><html lang="sw"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            . '<meta name="robots" content="noindex,nofollow"><title>Maoni / Feedback</title><style>'
            . 'body{font-family:system-ui,sans-serif;background:#0b3a4a;color:#fff;margin:0;padding:24px}main,body>*{max-width:480px;margin-left:auto;margin-right:auto}'
            . 'h1{font-size:22px}#stars button{font-size:38px;background:none;border:0;color:#6b7f87;padding:4px;cursor:pointer}#stars button.on{color:#ffc107}'
            . 'textarea{width:100%;box-sizing:border-box;border-radius:12px;border:1px solid #2b6b7e;background:#0f4a5e;color:#fff;padding:12px;font-size:16px}'
            . '.chk{display:block;margin:12px 0}#send{width:100%;padding:14px;border:0;border-radius:12px;background:#1fb8ce;color:#04222b;font-size:17px;font-weight:700}#note{color:#ffb4a9}'
            . '</style></head><body>' . $body . '</body></html>';

        return response($html, $info === null ? 404 : 200)
            ->header('Content-Type', 'text/html; charset=UTF-8')
            ->header('Cache-Control', 'no-store')
            ->header('X-Robots-Tag', 'noindex, nofollow')
            ->header('Referrer-Policy', 'no-referrer');
    }
}
