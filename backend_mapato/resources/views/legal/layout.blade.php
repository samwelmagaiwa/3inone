<!doctype html>
<html lang="sw">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{ $title }} - 3 in One</title>
<meta name="description" content="{{ $description }}">
<style>
  body{margin:0;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;color:#1f2937;background:#f6f8fb;line-height:1.6}
  header{background:#0b3d91;color:#fff;padding:14px clamp(14px,2.5vw,40px);display:flex;flex-wrap:wrap;align-items:center;gap:6px 0}
  header a{color:#fff;text-decoration:none;font-weight:700}
  nav a{color:#cfe0ff;margin-left:16px;font-weight:400;font-size:14px}
  main{width:min(96vw,1600px);margin:24px auto;padding:0 0 40px;box-sizing:border-box}
  article{background:#fff;border-radius:12px;padding:clamp(18px,3.5vw,56px);font-size:clamp(15px,1.15vw + 11px,19px);box-shadow:0 1px 3px rgba(0,0,0,.08);margin-bottom:20px}
  h1{margin-top:0;font-size:clamp(24px,2.2vw + 14px,38px)} h2{font-size:clamp(17px,1vw + 12px,24px);margin-top:24px}
  @media (max-width:600px){main{width:100%}article{border-radius:0}}
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
