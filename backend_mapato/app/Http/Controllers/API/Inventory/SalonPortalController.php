<?php

namespace App\Http\Controllers\API\Inventory;

use App\Models\Business;
use App\Services\SmsService;
use App\Support\Salon\OnlineBooking;
use App\Support\Salon\SalonPortal;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

/**
 * A client's own page, opened from a private link. The staff side makes (and can text) the link; the public side shows the page, lets the
 * client cancel their own appointment and asks for their link again by phone number. Nobody is signed in on the public side; every call is
 * throttled, and an unknown link or number is never explained.
 */
#[OA\Tag(name: 'Public salon', description: 'The client\'s own page (no sign-in)')]
class SalonPortalController extends Controller
{
    // ------------------------------------------------------------------ for the salon

    #[OA\Post(path: '/inventory/salon/clients/{id}/link', summary: 'A client\'s private link, optionally sent to them by text', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function link(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['send' => 'sometimes|boolean']);
        $client = DB::table('inventory_customers')->where('id', $id)->first();
        abort_if($client === null, 404, 'Not found');
        $url = SalonPortal::url(SalonPortal::tokenFor($id));
        $sent = false;
        if (!empty($data['send'])) {
            $phone = trim((string) ($client->phone ?? ''));
            abort_if($phone === '' || (bool) ($client->sms_opt_out ?? false), 422, 'Mteja huyu hana simu au amekataa ujumbe. / This client has no phone number or asked not to be texted.');
            $business = Business::forUser($request->user());
            try {
                $sent = SmsService::sendFor($business, $phone, SalonPortal::message((string) $client->name, (string) ($business?->name ?? ''), $url));
            } catch (\Throwable) {
                $sent = false;
            }
            abort_unless($sent, 422, 'Ujumbe haukutumwa. / The text could not be sent.');
        }

        return response()->json(['data' => ['url' => $url, 'sent' => $sent]]);
    }

    // ------------------------------------------------------------------ for the client (nobody is signed in)

    #[OA\Get(path: '/public/salon/me/{token}', summary: 'The client\'s page: visits coming up, points, packages, history, what they owe', tags: ['Public salon'], parameters: [new OA\Parameter(name: 'token', in: 'path', required: true, schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 200, description: 'Success'), new OA\Response(response: 404, description: 'Not a good link')])]
    public function show(string $token): JsonResponse
    {
        $view = SalonPortal::view($token);
        abort_if($view === null, 404, 'Kiungo hiki si sahihi. / This link is not valid.');

        return response()->json(['data' => $view]);
    }

    #[OA\Post(path: '/public/salon/me/{token}/appointments/{id}/cancel', summary: 'The client cancels one of their own appointments', tags: ['Public salon'], parameters: [new OA\Parameter(name: 'token', in: 'path', required: true, schema: new OA\Schema(type: 'string')), new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Cancelled'), new OA\Response(response: 422, description: 'Not possible')])]
    public function cancel(string $token, int $id): JsonResponse
    {
        SalonPortal::cancel($token, $id);

        return response()->json(['message' => 'Miadi imefutwa. / The appointment is cancelled.']);
    }

    #[OA\Post(path: '/public/salon/book/{slug}/my-link', summary: 'A client asks for their page to be texted to their phone', tags: ['Public salon'], parameters: [new OA\Parameter(name: 'slug', in: 'path', required: true, schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 200, description: 'Always the same answer')])]
    public function requestLink(Request $request, string $slug): JsonResponse
    {
        $found = OnlineBooking::find($slug);
        abort_if($found === null, 404, 'Saluni hii haipokei miadi mtandaoni. / This salon is not taking online bookings.');
        $data = $request->validate(['phone' => ['required', 'string', 'max:30']]);
        SalonPortal::sendLinkTo($found[0], $found[1], $data['phone']);

        // The same words whether or not the number is known: nobody can find out who a salon's clients are.
        return response()->json(['message' => 'Kama namba hii ipo kwetu, utapokea ujumbe wenye kiungo chako. / If this number is ours, you will get a text with your link.']);
    }

    /** The page itself: plain HTML that works on any phone, in Swahili and English. */
    public function page(string $token): Response
    {
        $view = SalonPortal::view($token);
        $tokenJs = json_encode($token);
        if ($view === null) {
            $body = '<h1>Kiungo hiki si sahihi</h1><p>This link is not valid. / Kiungo hiki si sahihi.</p>';
        } else {
            $name = htmlspecialchars((string) $view['business'], ENT_QUOTES, 'UTF-8');
            $body = <<<HTML
<h1>{$name}</h1>
<p id="hello">…</p>
<section id="upcoming"></section>
<section id="owed"></section>
<section id="points"></section>
<section id="packages"></section>
<section id="visits"></section>
<p id="book"></p>
<p id="note" role="status"></p>
<script>
var token = {$tokenJs};
var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) { return {'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'}[c]; }); };
var tsh = function (n) { return 'TSh ' + Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ','); };
var api = '/api/public/salon/me/' + encodeURIComponent(token);
var render = function (d) {
  document.getElementById('hello').textContent = 'Habari ' + d.client + '! / Hello ' + d.client + '!';
  var up = document.getElementById('upcoming');
  up.innerHTML = '<h2>Miadi yako / Your appointments</h2>' + (d.upcoming.length ? d.upcoming.map(function (a) {
    return '<div class="row"><div><b>' + esc(a.starts_at.replace('T', ' ')) + '</b><br>' + esc(a.services.join(', ')) + (a.staff_name ? ' · ' + esc(a.staff_name) : '') + '</div>'
      + (a.can_cancel ? '<button class="cancel" data-id="' + a.id + '">Futa / Cancel</button>' : '<small>Piga simu kwa saluni / Call the salon</small>') + '</div>';
  }).join('') : '<p class="muted">Huna miadi inayokuja. / No appointments coming up.</p>');
  document.getElementById('owed').innerHTML = d.owed > 0 ? '<h2>Deni / What you owe</h2><div class="row"><b class="due">' + tsh(d.owed) + '</b>' + (d.phone ? '<small>' + esc(d.phone) + '</small>' : '') + '</div>' : '';
  document.getElementById('points').innerHTML = d.points === null ? '' : '<h2>Pointi / Points</h2><div class="row"><b>' + d.points + '</b></div>';
  document.getElementById('packages').innerHTML = d.packages.length ? '<h2>Vifurushi / Packages</h2>' + d.packages.map(function (p) {
    return '<div class="row"><div>' + esc(p.name) + '<br><small>' + (p.expires_on ? 'Hadi / Until ' + esc(p.expires_on) : '') + '</small></div><b>' + p.sessions_left + ' / ' + p.sessions_total + '</b></div>';
  }).join('') : '';
  document.getElementById('visits').innerHTML = d.visits.length ? '<h2>Historia / History</h2>' + d.visits.map(function (v) {
    return '<div class="row"><div>' + esc(v.at) + '<br><small>' + esc(v.services.join(', ')) + '</small></div><div class="r">' + tsh(v.total) + (v.paid < v.total ? '<br><small class="due">Imebaki / Left ' + tsh(v.total - v.paid) + '</small>' : '') + '</div></div>';
  }).join('') : '';
  document.getElementById('book').innerHTML = d.booking_url ? '<a class="btn" href="' + esc(d.booking_url) + '">Weka miadi mpya / Book again</a>' : '';
};
var load = function () { fetch(api, {headers: {'Accept': 'application/json'}}).then(function (r) { return r.json(); }).then(function (j) { if (j.data) render(j.data); }); };
document.addEventListener('click', function (e) {
  var b = e.target.closest('.cancel');
  if (!b || !confirm('Futa miadi hii? / Cancel this appointment?')) return;
  b.disabled = true;
  fetch(api + '/appointments/' + b.dataset.id + '/cancel', {method: 'POST', headers: {'Accept': 'application/json'}}).then(function (r) { return r.json().then(function (j) { return {ok: r.ok, j: j}; }); }).then(function (x) {
    var m = x.j && x.j.errors ? Object.values(x.j.errors)[0][0] : (x.j && x.j.message) || '';
    document.getElementById('note').textContent = m;
    load();
  });
});
load();
</script>
HTML;
        }

        $html = '<!doctype html><html lang="sw"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            . '<meta name="robots" content="noindex,nofollow"><title>Ukurasa wangu / My page</title><style>'
            . 'body{font-family:system-ui,sans-serif;background:#0b3a4a;color:#fff;margin:0;padding:20px}main,body>*{max-width:520px;margin-left:auto;margin-right:auto}'
            . 'h1{font-size:22px;margin-bottom:4px}h2{font-size:14px;letter-spacing:.06em;text-transform:uppercase;color:#7fd6e6;margin:22px 0 8px}'
            . '.row{display:flex;justify-content:space-between;gap:12px;align-items:center;padding:12px 14px;margin-bottom:8px;border-radius:14px;background:#0f4a5e;border:1px solid #1d6479}'
            . '.r{text-align:right}.muted,small{color:#9bc5d0}.due{color:#ffb86b}button.cancel{background:#ff6b6b;border:0;color:#fff;border-radius:10px;padding:8px 12px;font-weight:700}'
            . '.btn{display:block;text-align:center;margin-top:22px;padding:14px;border-radius:12px;background:#1fb8ce;color:#04222b;font-weight:700;text-decoration:none}#note{color:#ffb4a9}'
            . '</style></head><body>' . $body . '</body></html>';

        return response($html, $view === null ? 404 : 200)
            ->header('Content-Type', 'text/html; charset=UTF-8')
            ->header('Cache-Control', 'no-store')
            ->header('X-Robots-Tag', 'noindex, nofollow')
            ->header('Referrer-Policy', 'no-referrer');
    }
}
