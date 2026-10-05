#!/bin/sh
# Builds src/app.html into two pages:
#   index.html      -> the PWA served by GitHub Pages (registers sw.js)
#   www/index.html  -> the page inside the iPhone app (Capacitor, no service worker)
set -e
cd "$(dirname "$0")"

wrap() { # $1 = output, $2 = extra footer script
  { cat <<'H'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover,user-scalable=no">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="Ma Liaison">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="theme-color" content="#000000">
<link rel="manifest" href="manifest.webmanifest">
<link rel="apple-touch-icon" href="icon-180.png">
H
  awk '/^<\/style>$/ && !d {print; print "</head>\n<body>"; d=1; next} {print}' src/app.html
  printf '%s\n</body>\n</html>\n' "$2"
  } > "$1"
}

wrap index.html "<script>
if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
</script>"
rm -rf fonts && cp -r src/fonts fonts

mkdir -p www
wrap www/index.html ""
rm -rf www/fonts && cp -r src/fonts www/fonts
cp manifest.webmanifest icon-180.png icon-192.png icon-512.png www/
rm -f www/sw.js www/artifact.html www/build.sh
echo "Built index.html and www/index.html"
