# Attendance from an approved device

Off by default. The owner (or anyone given the right **"Offices, staff devices and the attendance log"**, `inv_salon_devices`) switches it on in
the app: Team > Attendance > Devices and offices.

## How it works

1. **Register.** On first use the app makes an ECDSA P-256 key pair on the phone. The private key stays in the phone's secure storage; only the
   public key, a random device id and facts (name, manufacturer, model, OS and version, app version, IP, user agent) go to the server
   (`POST attendance/device/enroll`). No MAC address or IMEI is used. A person has **one** device; a device belongs to **one** person.
2. **Approve.** The device is `pending` until an administrator approves, rejects or blocks it
   (`POST attendance/admin/devices/{id}/decision`). Approving a new device puts the person's previous one away as `replaced`;
   `reset` does the same without a new one. Nothing is ever deleted: devices, attendance and the log stay.
3. **Start / finish work.** The app asks for a challenge (`POST attendance/challenge`: device id, office, in/out), signs the returned payload
   `3INONE-ATT|v1|{id}|{nonce}|{user}|{office}|{device}|{purpose}` with the private key and sends it back with the phone's place
   (`POST attendance/verify`). The challenge lives 90 seconds, works once (it is burned before anything else, so a replay finds it used)
   and is bound to the person, device, office and purpose. Signatures are accepted as ASN.1 DER or raw r||s (browsers).
4. **Checks, in this order, and attendance is written only if all pass:** challenge valid and unused (`challenge_expired`) · the person is the
   challenge's owner · device is the person's current device and approved (`device_mismatch`, `pending`, `rejected`, `blocked`) · signature valid
   (`signature_invalid`) · no open session / an open session to close (`already_clocked_in`, `no_active_session`) · office exists, is active and
   the person is assigned to it (`office_not_authorized`) · if the office requires its geofence, a location within the radius
   (`location_out_of_range`). The write is one transaction with row locking, so there are never two open sessions.
5. **The server's clock is the official time** (`Africa/Dar_es_Salaam`, changeable in the policy). The phone's time is never used.
6. **Log.** Every attempt, good or bad, is written to `inventory_attendance_checks` (person, device, office, purpose, outcome, IP, user agent,
   place) and listed under Devices and offices > Log.

With the policy on, the older plain `clock-in` / `clock-out` is refused (`device_verification_required`) for a person starting **their own** day;
a manager starting or finishing someone else's day, and holders of `inv_salon_devices`, may still do it (recorded as `source = manual`).
Rate limits: enrol 6/min, challenge and verify 30/min.

## In a shop or depot too (inventory service)

Everything above works in the **inventory** service (a shop or depot) exactly as in the salon, in the shop's own books: the tables are split by
`service`, so a business with both keeps **two separate sets** of phones, offices, places, switch and log (a phone approved in the salon is nobody
in the shop, and an office of one cannot be used from the other).

* **Who may start work:** every person on the staff, whatever their role (cashier, operator, accountant, even a read-only viewer). The routes have
  a group of their own, so this never depends on a right that has nothing to do with attendance.
* **The administrator's four rights** (`inv_salon_devices`, `inv_salon_offices`, `inv_salon_attendance_log`, `inv_salon_attendance_policy`) are
  **enforced in both services** by the `attendance_right` middleware (`salon_module` lets everyone through outside a salon, so it cannot be used
  here: a cashier must never approve a phone or read the log). Only the owner holds all four by default; the owner gives each to a person
  on the access screen (and can take it back), which lists these four for a shop (and none of the salon-only switches).
* **In the app:** "Attendance" is in the shop's menu for everyone; the "Devices and offices" button shows only for people who hold at least one
  right, and each tab only for the right that opens it. An office can be one of the shop's branches.
* The same URLs are used (`/inventory/salon/attendance/...`); the app's `X-Service` header (absent in a shop) decides whose books are meant.

## The business admin does not start work

The owner (roles `admin`, `administrator`, `super_admin`) **controls** the staff and so has no Start work button, no phone to register, and is never
an office's staff. The server refuses the owner's own enrol, challenge and plain clock-in/out (`admin_does_not_start_work`) and drops the owner from
an office's staff list. The owner's Attendance page shows who came in and who did not, from the staff's own starts. A manager is staff and still starts
their own work.

## Nobody starts someone else's day

Each person starts their own work, so the owner can tell who came and who did not. `clock-in` for another person is refused for everyone, the owner
included (`start_own_work`), and the app has no "start someone's day" button. An owner can still **finish** a forgotten session for someone
(recorded as manual), so one forgotten tap does not block the next morning.

## Consent and the audit trail

* **Consent first.** Before a phone is registered the app tells the person what is collected (phone name and model, system and app version, the
  phone's own made-up id, the network address, the place at start/finish; never IMEI, MAC, files, messages or contacts) and asks "I agree". The
  server refuses `device/enroll` without `consent: true` (older apps are told to update) and keeps `consent_at` and `consent_version` (`v1`) on the device.
* **A different phone is kept, not just refused.** Using any phone other than the one registered to the person still fails (`device_mismatch`),
  but the attempt is now flagged in the log as **"Not the logged-in device"**: the registered device id, the id and name of the phone that was
  used, the person, the office, the network address and the time. People holding `inv_salon_devices` are notified once per spell (not on every
  retry). The log's **Seen** button (`POST attendance/admin/checks/{id}/acknowledge`, right `inv_salon_attendance_log`) marks the person's open
  spell as seen; the lines stay. `GET attendance/admin/checks?flagged=1` lists only these, with `meta.flagged_open` the count still unseen.
* **Every line of the log** also carries the attendance it made (`attendance_id`), so a start can be traced from the log to the attendance row.
* The MAC address is still not collected (the phone's operating system returns a fixed fake value for it).

## Offices

Each office has a number shown with its name everywhere ("Kariakoo · #3"), an optional centre and radius, an "must be near" switch and a list
of people who work there. A person can only start work at an office they are assigned to and that is active.

## Honest limits

* **GPS is a hint, not proof.** It can be faked on a rooted phone or by a mock-location app. It is recorded (position, accuracy, time) and only
  *blocks* when an office asks for it.
* **The key is not hardware-bound.** It is kept in the platform's secure storage (Android Keystore-protected, iOS Keychain). The app cannot
  export it, but a rooted phone could read it. Moving to a hardware-backed non-exportable key (Android Keystore / Secure Enclave) is the next
  hardening step and needs a native plugin; the server protocol does not change. Administrator approval and the log are the compensating controls.
* **A browser is a weaker identity.** A web device would be a Web Crypto key (non-exportable) in IndexedDB plus a browser id; anyone with the browser
  profile can use it, clearing site data loses it, and the user agent is easily changed. The server already accepts `platform = web` and raw
  r||s signatures, but **no web screen has been built**: attendance from a browser is not offered.
* Use HTTPS only (the production host is); the signature protects the request's meaning, not its secrecy.

## Is the person really at work? (place proof)

The administrator captures a reference place **from their own phone, standing there** (the server refuses a fix worse than ±100 m):

* **For the whole office** (Offices > the office > "Use my location"): every person assigned to the office is measured from it.
* **For one person, optionally** (open the saved office, tap that person's pin): their own place wins over the office's, with an optional radius of their own. The unpin button goes back to the office place.

At **every** start and finish the server measures the distance from that place to where the phone says it is and keeps a verdict on the attendance
and in the log: `at_work`, `away`, `no_location`, `stale` (fix older than 180 s), `weak_signal` (worse than ±100 m), `mocked` (the phone reports a fake
location; Android), or `no_reference` (nothing captured yet). The GPS's own uncertainty is allowed for (167 m away with ±30 m counts as inside a 150 m
circle; the same spot with ±5 m does not). Only an office that **requires** its place blocks a *start* on anything but `at_work`; finishing is never
blocked. The person is told at once ("You are at work: 35 m from the office (150 m allowed)").

## Rights (Access screen)

Four switches, each a right a business admin can give or take away per person on the access screen. **They are all OFF for everyone but the owner** (the business admin) until the owner decides to hand them out, a manager included:

| Right | Lets them |
|---|---|
| `inv_salon_devices` | approve, reject, block and reset staff phones |
| `inv_salon_offices` | create offices (or make a branch an office), assign staff, capture places |
| `inv_salon_attendance_log` | read the log of every attempt |
| `inv_salon_attendance_policy` | switch device-verified attendance on or off, set the time zone |

The app shows only the tabs a person holds a right to, and asks the server for nothing else.

## Where a business is (registration)

On the registration form the applicant must tap **Capture my current location** while standing at the business; the point (and its accuracy)
is kept on the registration. The super admin sees it in the request's details with an **Open on the map** button (`https://www.google.com/maps?q=lat,lng`).
It is **required**: the form will not send without it, and the server refuses a request with no point, half a point, or a reading worse than
±100 m (`config/registration.php`, switch `REGISTRATION_REQUIRE_LOCATION=false` for an emergency). Older app versions have no capture button and
so cannot register a new business until updated. It never changes how the request is decided.
