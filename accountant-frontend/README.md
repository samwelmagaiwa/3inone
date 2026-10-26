# 3inone Accountant (web)

The accountant's app for a computer. It signs in with the same account as the mobile app and talks to the same API
(`backend_mapato`), so what the accountant does here is what the owner sees on the phone.

Angular 22 · Tailwind 4 · Vitest · served by nginx in Docker. The design is the one of the template this started from; only its
content was changed. No server-side rendering, no address baked into the build.

## What is here

| Part | What it does |
|---|---|
| Sign-in | email + phone number + password, like the mobile app; "forgot password" texts a 6-digit code |
| Shell | sidebar, search, language, shop/salon switch (only for people who work in both), notification bell, profile, help |
| This month | the monthly report: better/worse than last month, profit target, figures, capital, spending, products, debtors, advice |
| Sales | the sales of a period, with what was sold and how it was paid (reading only) |
| Debts | what customers owe and what the business owes, including debts from before the app; part payments |
| Expenses | what the business spent and what the owner took out for themselves, kept apart |

- **Rights:** the menu shows only the pages the person's rights open (the server's own list, `effective_permissions`, read in
  `src/app/core/nav.ts`). Someone with no rights lands on a plain "nothing to open yet" page. The server enforces the same rights.
- **Language:** Swahili first, English one click away (`src/app/core/translations.ts`). A test checks both languages have the same texts
  and that every text the code uses exists.
- **For people new to computers:** plain words, a help window, a question before anything is deleted or you are signed out, and empty
  pages that say what to do.

Adding a page: a folder under `src/app/pages/`, a route in `src/app/app.routes.ts`, an entry in `src/app/core/nav.ts` (who may open it),
and its texts in `translations.ts`.

## Run it in Docker (easiest)

You need Docker Desktop. The backend (`backend_mapato`) must be running on this computer on port 8000 with its database.

```bash
cd accountant-frontend
docker compose up --build
```

Open <http://localhost:8080> and sign in. Stop with `Ctrl+C` (or `docker compose down`).

nginx serves the page and also sends `/api/...` to the backend, so the browser sees one address and needs no CORS. Where `/api` goes is
set at run time, never in the build:

```bash
API_UPSTREAM=https://3inone.nexoryatech.com API_HOST=3inone.nexoryatech.com docker compose up --build   # another backend
WEB_PORT=9000 docker compose up --build                                                              # another port
```

(Copy `.env.example` to `.env` to keep such settings.)

## Run it for development (no Docker)

You need Node 22.22.3 or newer (Angular 22 refuses older Node; check with `node -v`, or use Docker).

```bash
cd accountant-frontend
npm install
npm start            # http://localhost:4200, /api is forwarded to http://localhost:8000 (proxy.conf.json)
```

Other commands: `npm test` (unit tests), `npm run lint` (type check), `npm run build` (output in `dist/accountant-web/browser`).

## On the live server

The app lives under the same domain as the API: **https://3inone.nexoryatech.com/web/** (sign-in at `/web/login`). Build it for that
address with `docker build --build-arg BASE_HREF=/web/ -t 3inone/accountant-web:live .` (from PowerShell on Windows; Git Bash rewrites
`/web/` into a file path). The container listens on `127.0.0.1:8088` on the server, and the site's nginx sends `/web/` to it
(`extension/3inone.nexoryatech.com/accountant.conf`). `/app/` still redirects to `/web/`.

## Safety

- Nothing secret is in the repository or the build. The token lives in the browser's `localStorage` and is dropped on sign out or when the
  server answers 401.
- Never put a real `.env` in git (it is ignored).
- The server decides what each person may see; the app only hides what the API refuses.
