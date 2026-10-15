/* sw.js — بيخلي الموقع نفسه (الصفحة والتصميم) يفتح من غير نت.
   بيانات Supabase (المواد والأسئلة) لسه محتاجة نت، وعمدًا مش بتتخزن هنا. */
const V = 'tamreedy-v1';
const SHELL = ['./', 'index.html', 'app.js', 'extras.js', 'config.js', 'icon.svg', 'manifest.json'];
self.addEventListener('install', e => {
  e.waitUntil(caches.open(V).then(c => Promise.all(SHELL.map(u => c.add(u).catch(() => {})))).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== V).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const r = e.request, u = new URL(r.url);
  if (r.method !== 'GET' || /supabase\.co$/.test(u.hostname)) return;
  const cdn = /(^|\.)(jsdelivr\.net|googleapis\.com|gstatic\.com)$/.test(u.hostname);
  if (u.origin === location.origin) {
    e.respondWith(fetch(r).then(res => { const c = res.clone(); caches.open(V).then(x => x.put(r, c)); return res; })
      .catch(() => caches.match(r).then(m => m || caches.match('index.html'))));
  } else if (cdn) {
    e.respondWith(caches.match(r).then(m => m || fetch(r).then(res => { const c = res.clone(); caches.open(V).then(x => x.put(r, c)); return res; })));
  }
});
