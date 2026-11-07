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
