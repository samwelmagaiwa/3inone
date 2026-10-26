# 3inone Accountant (web)

The accountant's app for a computer. It signs in with the same account as the mobile app and talks to the same API
(`backend_mapato`), so what the accountant does here is what the owner sees on the phone.

Angular 22 · Tailwind 4 · Vitest · served by nginx in Docker. No server-side rendering, no address baked into the build.

## What is here

| Part | What it does |
|---|---|
| Sign-in | email + phone number + password, exactly like the mobile app (`POST /api/auth/login`) |
| Shell | sidebar (a drawer on a phone), the signed-in person, sign out |
| Dashboard | the month in full from `GET /api/inventory/monthly-report`: better/worse than last month, profit target, figures, capital |
| Core | token kept in `localStorage`; an interceptor adds `Authorization` and `X-Service` and signs out on a 401; route guards |

Debts, expenses, sales and reports are listed in the sidebar as "soon". Adding one is: a folder under `src/app/pages/`, a route in
`src/app/app.routes.ts`, and an entry in `nav` in `src/app/layouts/shell.ts`.

## Run it in Docker (easiest)

You need Docker Desktop. The backend (`backend_mapato`) must be running on this computer on port 8000
(`docker compose up -d` in `backend_mapato`).

```bash
cd accountant-frontend
docker compose up --build
```

Open <http://localhost:8080> and sign in. Stop with `Ctrl+C` (or `docker compose down`).

The page is served by nginx, which also sends `/api/...` to the backend, so the browser sees one address and needs no CORS.
Where `/api` goes is set at run time, never in the build:

```bash
# another backend (copy .env.example to .env, or set it in the shell)
API_UPSTREAM=https://3inone.nexoryatech.com API_HOST=3inone.nexoryatech.com docker compose up --build
WEB_PORT=9000 docker compose up --build        # another port
```

Without Compose:

```bash
docker build -t 3inone/accountant-web .
docker run --rm -p 8080:80 --add-host host.docker.internal:host-gateway -e API_UPSTREAM=http://host.docker.internal:8000 3inone/accountant-web
```

## Run it for development (no Docker)

You need Node 22.22.3 or newer (or 24.15+): Angular 22 refuses to start on older Node. Check with `node -v`; if yours is older, use the Docker way above.

```bash
cd accountant-frontend
npm install
npm start            # http://localhost:4200, /api is forwarded to http://localhost:8000 (proxy.conf.json)
```

Other commands: `npm test` (unit tests), `npm run lint` (type check), `npm run build` (output in `dist/accountant-web/browser`),
`npm run format`.

To point development at another backend, edit `target` in `proxy.conf.json`.

## How it connects

- The app calls relative addresses (`/api/...`, see `src/environments/environment.ts`). In Docker nginx forwards them
  (`nginx/default.conf.template`); in `npm start` the dev server forwards them (`proxy.conf.json`).
- The same idea works on the live server: put this app on `https://3inone.nexoryatech.com/app/` and keep `/api` where it is, so
  there is one domain, one certificate and no CORS.
- Every call carries `X-Service: inventory`, so the server answers from the shop's books. Change it in `environment.ts`.

## Safety

- Nothing secret is in the repository or the build. The token lives in the browser's `localStorage` and is dropped on sign out
  or when the server answers 401.
- Never put a real `.env` in git (it is ignored). `.env.example` shows what can be set.
- The server decides what each person may see; the app only hides what the API refuses.
