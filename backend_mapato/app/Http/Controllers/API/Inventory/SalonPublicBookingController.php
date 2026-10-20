<?php

namespace App\Http\Controllers\API\Inventory;

use App\Support\Salon\OnlineBooking;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Routing\Controller;
use OpenApi\Attributes as OA;

/**
 * The public side of online booking: a client opens the salon's own address, sees its services and free times, and books
 * with a name and a phone number. Nobody is signed in; an address that is unknown, switched off or whose salon's plan has
 * ended is simply "not found". Every call is throttled and the form carries a trap field that only a robot fills in.
 */
#[OA\Tag(name: 'Public salon', description: 'Online booking, for clients (no sign-in)')]
class SalonPublicBookingController extends Controller
{
    #[OA\Get(path: '/public/salon/book/{slug}', summary: 'The salon\'s services, stylists and booking rules', tags: ['Public salon'], parameters: [new OA\Parameter(name: 'slug', in: 'path', required: true, schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 200, description: 'Success'), new OA\Response(response: 404, description: 'Not taking bookings')])]
    public function catalog(string $slug): JsonResponse
    {
        $found = OnlineBooking::find($slug);
        abort_if($found === null, 404, 'Saluni hii haipokei miadi mtandaoni. / This salon is not taking online bookings.');

        return response()->json(['data' => OnlineBooking::catalog(...$found)]);
    }

    #[OA\Get(path: '/public/salon/book/{slug}/slots', summary: 'The free times on a day for the chosen services', tags: ['Public salon'], parameters: [new OA\Parameter(name: 'slug', in: 'path', required: true, schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function slots(Request $request, string $slug): JsonResponse
    {
        $found = OnlineBooking::find($slug);
        abort_if($found === null, 404, 'Saluni hii haipokei miadi mtandaoni. / This salon is not taking online bookings.');
        $data = $request->validate([
            'service_ids' => ['required', 'regex:/^\d+(,\d+){0,7}$/'],
            'date' => 'required|date_format:Y-m-d',
            'staff_id' => 'nullable|string|max:64',
        ]);

        return response()->json(['data' => OnlineBooking::slots($found[1], array_map('intval', explode(',', $data['service_ids'])), $data['date'], $data['staff_id'] ?? null)]);
    }

    #[OA\Post(path: '/public/salon/book/{slug}', summary: 'Book an appointment', tags: ['Public salon'], parameters: [new OA\Parameter(name: 'slug', in: 'path', required: true, schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 201, description: 'Booked'), new OA\Response(response: 422, description: 'Not possible')])]
    public function book(Request $request, string $slug): JsonResponse
    {
        $found = OnlineBooking::find($slug);
        abort_if($found === null, 404, 'Saluni hii haipokei miadi mtandaoni. / This salon is not taking online bookings.');
        // A number is often typed with spaces or dashes: +255 711 000 001.
        if (is_string($request->input('phone'))) {
            $request->merge(['phone' => preg_replace('/[\s-]+/', '', $request->input('phone'))]);
        }
        $data = $request->validate([
            'name' => 'required|string|min:2|max:80',
            'phone' => ['required', 'string', 'regex:/^(\+?255|0)[67]\d{8}$/'],
            'services' => 'required|array|min:1|max:8',
            'services.*.product_id' => 'required|integer',
            'services.*.label' => 'nullable|string|max:40',
            'starts_at' => 'required|date_format:Y-m-d H:i',
            'staff_id' => 'nullable|string|max:64',
            'notes' => 'nullable|string|max:500',
            // A trap: people never see this field, robots fill in everything.
            'website' => 'nullable|string|max:200',
        ]);

        if (!empty($data['website'])) {
            // Looks like it worked; nothing is saved.
            return response()->json(['message' => 'Miadi imepokelewa. / Your booking is received.', 'data' => ['id' => 0]], 201);
        }

        $phone = (string) preg_replace('/\s+/', '', $data['phone']);
        $phone = preg_match('/^(\+?255)/', $phone) ? '0' . substr(ltrim($phone, '+'), 3) : $phone;
        $result = OnlineBooking::book($found[0], $found[1], ['phone' => $phone] + $data);

        return response()->json(['message' => 'Miadi imepokelewa. / Your booking is received.', 'data' => $result], 201);
    }

    /** The page itself: choose services, a day, a time, say who you are. Plain HTML that works on any phone. */
    public function page(string $slug): Response
    {
        $found = OnlineBooking::find($slug);
        if ($found === null) {
            return $this->html('<h1>Haipatikani / Not found</h1><p>Saluni hii haipokei miadi mtandaoni. / This salon is not taking online bookings.</p>', 404, 'Miadi / Booking');
        }
        $name = htmlspecialchars((string) $found[0]->name, ENT_QUOTES, 'UTF-8');
        $slugJs = json_encode(strtolower($slug));

        $body = <<<HTML
<h1>{$name}</h1>
<p>Weka miadi yako / Book your appointment</p>
<div id="mine"></div>
<button id="install" type="button" hidden>Weka kwenye simu / Install on your phone</button>
<p id="ios" hidden>iPhone: bonyeza Share kisha "Add to Home Screen". / iPhone: tap Share, then Add to Home Screen.</p>
<form id="f" autocomplete="off">
  <h2>1. Huduma / Services</h2><div id="services">…</div>
  <h2>2. Siku / Day</h2><input type="date" id="date" required>
  <h2>3. Mhudumu / Stylist</h2><select id="staff"><option value="">Yeyote / Anyone</option></select>
  <h2>4. Saa / Time</h2><div id="slots"><em>Chagua huduma na siku. / Choose services and a day.</em></div>
  <h2>5. Wewe / You</h2>
  <input id="name" placeholder="Jina / Name" maxlength="80" required>
  <input id="phone" placeholder="Simu / Phone (07…)" inputmode="tel" required>
  <textarea id="notes" rows="2" maxlength="500" placeholder="Maelezo / Notes (hiari / optional)"></textarea>
  <input id="website" tabindex="-1" autocomplete="off" aria-hidden="true" style="position:absolute;left:-5000px">
  <button id="send" type="submit" disabled>Weka miadi / Book</button>
  <p id="note" role="status"></p>
</form>
<script>
var slug = {$slugJs}, chosenTime = null, catalog = null;
function api(path, opts) { return fetch('/api/public/salon/book/' + encodeURIComponent(slug) + path, opts).then(function (r) { return r.json().then(function (j) { return {ok: r.ok, j: j}; }); }); }
function fmt(n) { return 'TSh ' + Number(n).toLocaleString('en-US'); }
function msg(x) { return x.j && x.j.errors ? Object.values(x.j.errors)[0][0] : (x.j && x.j.message) || 'Imeshindikana / Failed'; }
function chosen() { var out = []; document.querySelectorAll('#services input[type=checkbox]:checked').forEach(function (c) { var o = {product_id: parseInt(c.value, 10)}; var s = document.getElementById('opt' + c.value); if (s && s.value) o.label = s.value; out.push(o); }); return out; }
function loadSlots() {
  chosenTime = null; document.getElementById('send').disabled = true;
  var ids = chosen().map(function (c) { return c.product_id; }).join(','), date = document.getElementById('date').value, el = document.getElementById('slots');
  if (!ids || !date) { el.innerHTML = '<em>Chagua huduma na siku. / Choose services and a day.</em>'; return; }
  el.textContent = '…';
  api('/slots?service_ids=' + ids + '&date=' + date + '&staff_id=' + encodeURIComponent(document.getElementById('staff').value)).then(function (x) {
    if (!x.ok) { el.textContent = msg(x); return; }
    var slots = x.j.data.slots; el.innerHTML = '';
    if (!slots.length) { el.innerHTML = '<em>Hakuna saa wazi siku hiyo. / No free times that day.</em>'; return; }
    slots.forEach(function (s) { var b = document.createElement('button'); b.type = 'button'; b.className = 'slot'; b.textContent = s.time; b.onclick = function () { document.querySelectorAll('.slot').forEach(function (z) { z.classList.remove('on'); }); b.classList.add('on'); chosenTime = s.time; document.getElementById('send').disabled = false; }; el.appendChild(b); });
  });
}
api('').then(function (x) {
  var box = document.getElementById('services');
  if (!x.ok) { box.textContent = msg(x); return; }
  catalog = x.j.data; box.innerHTML = '';
  catalog.services.forEach(function (s) {
    var row = document.createElement('label'); row.className = 'svc';
    var c = document.createElement('input'); c.type = 'checkbox'; c.value = s.id; c.onchange = loadSlots;
    row.appendChild(c); row.appendChild(document.createTextNode(' ' + s.name + ' — ' + fmt(s.price) + (s.minutes ? ' (' + s.minutes + ' min)' : '')));
    if (s.options && s.options.length) { var sel = document.createElement('select'); sel.id = 'opt' + s.id; sel.onchange = loadSlots; var d = document.createElement('option'); d.value = ''; d.textContent = 'Bei ya kawaida / Usual'; sel.appendChild(d); s.options.forEach(function (o) { var op = document.createElement('option'); op.value = o.label; op.textContent = o.label + ' — ' + fmt(o.price); sel.appendChild(op); }); row.appendChild(document.createElement('br')); row.appendChild(sel); }
    box.appendChild(row);
  });
  var st = document.getElementById('staff'); catalog.stylists.forEach(function (p) { var o = document.createElement('option'); o.value = p.id; o.textContent = p.name + (p.specialization ? ' (' + p.specialization + ')' : ''); st.appendChild(o); });
  var dt = document.getElementById('date'), now = new Date(), pad = function (n) { return ('0' + n).slice(-2); };
  dt.min = now.getFullYear() + '-' + pad(now.getMonth() + 1) + '-' + pad(now.getDate());
});
// Bookings made from this phone are remembered here (and shown when the app is opened, even with no signal).
var KEY = 'bk_' + slug;
function mine() { try { return JSON.parse(localStorage.getItem(KEY) || '[]'); } catch (e) { return []; } }
function showMine() {
  var box = document.getElementById('mine'), list = mine().filter(function (b) { return b.at >= new Date(Date.now() - 3600000).toISOString().slice(0, 16).replace('T', ' '); });
  if (!list.length) { box.innerHTML = ''; return; }
  box.innerHTML = '<h2>Miadi zako / Your bookings</h2>' + list.map(function (b) { return '<div class="svc">' + b.at + (b.who ? ' (' + b.who + ')' : '') + '</div>'; }).join('');
}
function remember(at, who) { var l = mine(); l.push({at: at, who: who || ''}); try { localStorage.setItem(KEY, JSON.stringify(l.slice(-10))); } catch (e) {} }
showMine();
// An app on the home screen: the salon's own name and icon, opens with no signal.
if ('serviceWorker' in navigator) { navigator.serviceWorker.register('/book/' + encodeURIComponent(slug) + '/sw.js', {scope: '/book/' + encodeURIComponent(slug)}).catch(function () {}); }
var deferred = null;
window.addEventListener('beforeinstallprompt', function (e) { e.preventDefault(); deferred = e; document.getElementById('install').hidden = false; });
document.getElementById('install').onclick = function () { if (deferred) { deferred.prompt(); deferred = null; this.hidden = true; } };
if (/iphone|ipad/i.test(navigator.userAgent) && !window.navigator.standalone) { document.getElementById('ios').hidden = false; }
document.getElementById('date').onchange = loadSlots; document.getElementById('staff').onchange = loadSlots;
document.getElementById('f').onsubmit = function (e) {
  e.preventDefault(); var btn = document.getElementById('send'), note = document.getElementById('note'); btn.disabled = true; note.textContent = '…';
  api('', {method: 'POST', headers: {'Content-Type': 'application/json', 'Accept': 'application/json'}, body: JSON.stringify({
    name: document.getElementById('name').value, phone: document.getElementById('phone').value, services: chosen(), starts_at: document.getElementById('date').value + ' ' + chosenTime,
    staff_id: document.getElementById('staff').value || null, notes: document.getElementById('notes').value, website: document.getElementById('website').value})
  }).then(function (x) {
    if (x.ok) { remember(x.j.data.starts_at, x.j.data.staff_name); document.body.innerHTML = '<main><h1>Asante! / Thank you!</h1><p>Miadi yako imepokelewa: ' + x.j.data.starts_at + (x.j.data.staff_name ? ' (' + x.j.data.staff_name + ')' : '') + '. / Your booking is received.</p></main>'; return; }
    note.textContent = msg(x); btn.disabled = false; if (x.j && x.j.errors && x.j.errors.starts_at) { loadSlots(); }
  }).catch(function () { note.textContent = 'Hakuna mtandao / No connection'; btn.disabled = false; });
};
</script>
HTML;

        $base = '/book/' . rawurlencode(strtolower($slug));
        $head = '<link rel="manifest" href="' . $base . '/manifest.webmanifest"><meta name="theme-color" content="#0b3a4a">'
            . '<link rel="icon" href="' . $base . '/icon.svg" type="image/svg+xml"><link rel="apple-touch-icon" href="' . $base . '/icon.svg">'
            . '<meta name="apple-mobile-web-app-capable" content="yes"><meta name="mobile-web-app-capable" content="yes">';

        return $this->html($body, 200, "{$name}: Miadi / Booking", $head);
    }

    /** The salon's own app on a client's phone: name, colours and where it opens (so it can be added to the home screen). */
    public function manifest(string $slug): \Illuminate\Http\JsonResponse
    {
        $found = OnlineBooking::find($slug);
        abort_if($found === null, 404);
        $base = '/book/' . rawurlencode(strtolower($slug));
        $name = (string) $found[0]->name;

        return response()->json([
            'name' => $name,
            'short_name' => mb_substr($name, 0, 12),
            'description' => 'Weka miadi / Book an appointment',
            'start_url' => $base,
            'scope' => $base,
            'display' => 'standalone',
            'background_color' => '#0b3a4a',
            'theme_color' => '#0b3a4a',
            'lang' => 'sw',
            'icons' => [['src' => $base . '/icon.svg', 'sizes' => 'any', 'type' => 'image/svg+xml', 'purpose' => 'any']],
        ])->header('Content-Type', 'application/manifest+json')->header('Cache-Control', 'public, max-age=3600');
    }

    /** A round icon with the salon's first letter (no image file needed). */
    public function icon(string $slug): Response
    {
        $found = OnlineBooking::find($slug);
        abort_if($found === null, 404);
        $letter = htmlspecialchars(mb_strtoupper(mb_substr(trim((string) $found[0]->name) ?: 'S', 0, 1)), ENT_QUOTES, 'UTF-8');
        $svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><rect width="512" height="512" rx="112" fill="#0b3a4a"/>'
            . '<circle cx="256" cy="256" r="170" fill="#1fb8ce"/><text x="256" y="320" font-family="Arial,sans-serif" font-size="210" font-weight="700" text-anchor="middle" fill="#04222b">' . $letter . '</text></svg>';

        return response($svg, 200)->header('Content-Type', 'image/svg+xml')->header('Cache-Control', 'public, max-age=3600');
    }

    /**
     * The page's service worker: the app opens even with no signal, showing the last page and the last list of services and
     * prices it saw. Booking itself always needs a connection (it must ask the salon whether the time is free).
     */
    public function worker(string $slug): Response
    {
        $found = OnlineBooking::find($slug);
        abort_if($found === null, 404);
        $s = strtolower($slug);
        $js = <<<JS
var CACHE = 'book-' + {$this->js($s)}, PAGE = '/book/' + {$this->js($s)}, CATALOG = '/api/public/salon/book/' + {$this->js($s)};
self.addEventListener('install', function (e) { self.skipWaiting(); });
self.addEventListener('activate', function (e) { e.waitUntil(self.clients.claim()); });
self.addEventListener('fetch', function (e) {
  var r = e.request, u = new URL(r.url);
  if (r.method !== 'GET' || u.origin !== location.origin) return;
  // Only this salon's page and its list of services; free times and bookings are never kept (they must be live).
  if (u.pathname !== PAGE && u.pathname !== CATALOG) return;
  e.respondWith(fetch(r).then(function (res) {
    if (res.ok) { var copy = res.clone(); caches.open(CACHE).then(function (c) { c.put(r, copy); }); }
    return res;
  }).catch(function () { return caches.match(r); }));
});
JS;

        return response($js, 200)->header('Content-Type', 'application/javascript')->header('Service-Worker-Allowed', '/book/' . $s)->header('Cache-Control', 'no-cache');
    }

    private function js(string $v): string
    {
        return json_encode($v, JSON_UNESCAPED_SLASHES | JSON_HEX_TAG | JSON_HEX_AMP);
    }

    private function html(string $body, int $status, string $title, string $head = ''): Response
    {
        $html = '<!doctype html><html lang="sw"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            . '<meta name="robots" content="noindex,nofollow">' . $head . '<title>' . $title . '</title><style>'
            . 'body{font-family:system-ui,sans-serif;background:#0b3a4a;color:#fff;margin:0;padding:20px}body>*{max-width:520px;margin-left:auto;margin-right:auto}'
            . 'h1{font-size:22px}h2{font-size:15px;margin:18px 0 6px;color:#9fd9e6}.svc{display:block;padding:8px 0;border-bottom:1px solid #1d5a6e}'
            . 'input,select,textarea{width:100%;box-sizing:border-box;margin:4px 0;border-radius:10px;border:1px solid #2b6b7e;background:#0f4a5e;color:#fff;padding:11px;font-size:16px}'
            . '.svc input[type=checkbox]{width:auto}.slot{display:inline-block;width:auto;margin:3px;padding:9px 14px;border-radius:10px;border:1px solid #2b6b7e;background:#0f4a5e;color:#fff;font-size:15px}'
            . '.slot.on{background:#1fb8ce;color:#04222b;font-weight:700}#send{width:100%;margin-top:14px;padding:14px;border:0;border-radius:12px;background:#1fb8ce;color:#04222b;font-size:17px;font-weight:700}'
            . '#send:disabled{opacity:.5}#note{color:#ffb4a9}#install{margin:8px 0;padding:10px 14px;border-radius:10px;border:1px solid #1fb8ce;background:none;color:#1fb8ce;font-size:15px}#ios{font-size:13px;color:#9fd9e6}</style></head><body>' . $body . '</body></html>';

        return response($html, $status)
            ->header('Content-Type', 'text/html; charset=UTF-8')
            ->header('Cache-Control', 'no-store')
            ->header('X-Robots-Tag', 'noindex, nofollow')
            ->header('Referrer-Policy', 'no-referrer');
    }
}
