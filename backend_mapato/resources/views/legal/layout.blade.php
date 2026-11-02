<!doctype html>
<html lang="sw">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{ $title }} - 3 in One</title>
<meta name="description" content="{{ $description }}">
<style>
  body{margin:0;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;color:#1f2937;background:#f6f8fb;line-height:1.6}
  header{background:#0b3d91;color:#fff;padding:14px 20px}
  header a{color:#fff;text-decoration:none;font-weight:700}
  nav a{color:#cfe0ff;margin-left:16px;font-weight:400;font-size:14px}
  main{max-width:1180px;margin:24px auto;padding:0 24px 40px}
  article{background:#fff;border-radius:12px;padding:32px 40px;box-shadow:0 1px 3px rgba(0,0,0,.08);margin-bottom:20px}
  h1{margin-top:0;font-size:26px} h2{font-size:18px;margin-top:22px}
  .en{color:#4b5563;border-top:1px dashed #d1d5db;margin-top:28px;padding-top:6px}
  footer{text-align:center;color:#6b7280;font-size:13px;padding-bottom:30px}
</style>
</head>
<body>
<header><a href="/about">3 in One</a>
  <nav style="display:inline"><a href="/privacy">Faragha / Privacy</a><a href="/terms">Masharti / Terms</a></nav>
</header>
<main>@yield('content')</main>
<footer>&copy; {{ now()->utc()->year }} 3 in One &middot; 3inone.nexoryatech.com</footer>
</body>
</html>
