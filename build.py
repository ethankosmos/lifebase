#!/usr/bin/env python3
"""Builds index.html (the installable web app) from src/lifebase.html.

src/lifebase.html is the same single-file app that runs inside Claude as an artifact.
This wraps it in a full HTML document and adds the web-app manifest, icons,
config and the offline service worker. Run:  python3 build.py
"""
import pathlib, re, hashlib
root = pathlib.Path(__file__).parent
src = (root / 'src' / 'lifebase.html').read_text(encoding='utf-8')
cut = src.index('</style>') + len('</style>')
head, body = src[:cut], src[cut:]
version = hashlib.sha1(src.encode()).hexdigest()[:10]
page = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#F3F5F8" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0E1217" media="(prefers-color-scheme: dark)">
<meta name="description" content="LifeBase: your calendar, to-dos, money, home, career and health in one private place.">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="LifeBase">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<link rel="manifest" href="manifest.webmanifest">
<link rel="icon" href="icons/icon-192.png" type="image/png">
<link rel="apple-touch-icon" href="icons/apple-touch-icon.png">
<script src="config.js"></script>
{head}
</head>
<body>
{body}
<script>
if ('serviceWorker' in navigator && location.protocol !== 'file:') {{
  addEventListener('load', () => navigator.serviceWorker.register('sw.js?v={version}').catch(() => {{}}));
}}
</script>
</body>
</html>
'''
(root / 'index.html').write_text(page, encoding='utf-8')
sw = (root / 'sw.template.js').read_text(encoding='utf-8').replace('__VERSION__', version)
(root / 'sw.js').write_text(sw, encoding='utf-8')
print('Built index.html and sw.js, version', version)
