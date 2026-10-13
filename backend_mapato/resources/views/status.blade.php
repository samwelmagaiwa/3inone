<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <meta name="color-scheme" content="dark light">
    <title>3 in One API</title>
    <style>
        :root {
            --bg-top: #04121a;
            --bg-bottom: #0d485a;
            --card: rgba(255, 255, 255, .08);
            --card-edge: rgba(255, 255, 255, .18);
            --text: #fff;
            --muted: rgba(255, 255, 255, .68);
            --accent: #20b8ce;
            --ok: #34d399;
        }
        @media (prefers-color-scheme: light) {
            :root {
                --bg-top: #e8f4f7;
                --bg-bottom: #cfe6ec;
                --card: rgba(255, 255, 255, .75);
                --card-edge: rgba(13, 61, 77, .18);
                --text: #0d3d4d;
                --muted: rgba(13, 61, 77, .72);
                --accent: #0a8497;
                --ok: #059669;
            }
        }
        * { box-sizing: border-box; }
        html, body { height: 100%; margin: 0; }
        body {
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 24px;
            background: linear-gradient(180deg, var(--bg-top), var(--bg-bottom)) fixed;
            color: var(--text);
            font-family: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            -webkit-font-smoothing: antialiased;
        }
        main {
            width: 100%;
            max-width: 460px;
            padding: 36px 32px 28px;
            background: var(--card);
            border: 1px solid var(--card-edge);
            border-radius: 24px;
            box-shadow: 0 24px 60px rgba(0, 0, 0, .35), 0 0 60px rgba(32, 184, 206, .12);
            text-align: center;
        }
        .mark {
            display: inline-flex;
            align-items: baseline;
            gap: 6px;
            font-weight: 800;
            font-size: 44px;
            letter-spacing: -1px;
            line-height: 1;
        }
        .mark small { font-size: 18px; font-weight: 600; color: var(--accent); letter-spacing: 0; }
        h1 { margin: 14px 0 4px; font-size: 22px; font-weight: 700; }
        .tag { margin: 0 0 26px; color: var(--muted); font-size: 14px; letter-spacing: .4px; }
        .status {
            display: inline-flex;
            align-items: center;
            gap: 10px;
            padding: 10px 18px;
            border-radius: 999px;
            border: 1px solid color-mix(in srgb, var(--ok) 45%, transparent);
            background: color-mix(in srgb, var(--ok) 14%, transparent);
            font-weight: 600;
            font-size: 15px;
        }
        .dot {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            background: var(--ok);
            box-shadow: 0 0 0 0 color-mix(in srgb, var(--ok) 60%, transparent);
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0%   { box-shadow: 0 0 0 0 color-mix(in srgb, var(--ok) 55%, transparent); }
            70%  { box-shadow: 0 0 0 10px transparent; }
            100% { box-shadow: 0 0 0 0 transparent; }
        }
        @media (prefers-reduced-motion: reduce) { .dot { animation: none; } }
        dl { margin: 26px 0 0; padding: 0; text-align: left; }
        dl div {
            display: flex;
            justify-content: space-between;
            gap: 16px;
            padding: 11px 2px;
            border-top: 1px solid var(--card-edge);
            font-size: 14px;
        }
        dt { color: var(--muted); }
        dd { margin: 0; font-weight: 600; font-variant-numeric: tabular-nums; text-align: right; }
        .link {
            display: inline-block;
            margin-top: 22px;
            padding: 10px 20px;
            border-radius: 12px;
            border: 1px solid var(--accent);
            color: var(--accent);
            font-weight: 600;
            font-size: 14px;
            text-decoration: none;
        }
        .link:hover, .link:focus-visible { background: color-mix(in srgb, var(--accent) 16%, transparent); outline: none; }
        footer { margin-top: 24px; color: var(--muted); font-size: 12px; }
    </style>
</head>
<body>
    <main>
        <div class="mark" aria-hidden="true">3<small>in</small>One</div>
        <h1>3 in One API</h1>
        <p class="tag">Transport &middot; Rental &middot; Inventory</p>

        <div class="status" role="status">
            <span class="dot" aria-hidden="true"></span>
            The API is running
        </div>

        <dl>
            <div><dt>Status</dt><dd>Online</dd></div>
            <div><dt>Version</dt><dd>{{ $version }}</dd></div>
            <div><dt>Server time (UTC)</dt><dd>{{ $time }}</dd></div>
        </dl>

        <a class="link" href="/api/health">Open the health check</a>

        <footer>&copy; {{ $year }} 3 in One</footer>
    </main>
</body>
</html>
