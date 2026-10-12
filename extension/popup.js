// The toolbar popup: whether Sotto is connected, and the one-time
// permission to read pages when Sotto asks (without it, only the tab where
// you open this popup can be read).
const api = globalThis.browser ?? globalThis.chrome;
const es = (navigator.language || '').toLowerCase().startsWith('es');
const t = es
  ? {
      on: 'Conectado',
      off: 'Sin conexión',
      allow: 'Permitir leer páginas cuando Sotto lo pida',
      allowed: 'Puede leer la pestaña activa cuando Sotto lo pide.',
      limited: 'Ahora solo puede leer esta pestaña.',
      reconnect: 'Reconectar',
      note: 'Nunca lee contraseñas ni datos de pago, y no hace nada por su cuenta.',
    }
  : {
      on: 'Connected',
      off: 'Not connected',
      allow: 'Allow reading pages when Sotto asks',
      allowed: 'It can read the active tab when Sotto asks.',
      limited: 'For now it can only read this tab.',
      reconnect: 'Reconnect',
      note: 'It never reads passwords or payment details, and never acts on its own.',
    };
const sites = { origins: ['http://*/*', 'https://*/*'] };

async function refresh() {
  const s = await api.runtime.sendMessage({ type: 'status' }).catch(() => null);
  const connected = !!(s && s.connected);
  const pill = document.getElementById('status');
  pill.className = connected ? 'pill on' : 'pill';
  pill.textContent = connected ? t.on : t.off;
  const granted = await api.permissions.contains(sites);
  document.getElementById('sites-text').textContent = granted ? t.allowed : t.limited;
  const allow = document.getElementById('allow');
  allow.hidden = granted;
  allow.textContent = t.allow;
}

document.getElementById('allow').addEventListener('click', async () => {
  await api.permissions.request(sites).catch(() => false);
  await refresh();
});
document.getElementById('reconnect').textContent = t.reconnect;
document.getElementById('reconnect').addEventListener('click', async () => {
  await api.runtime.sendMessage({ type: 'reconnect' }).catch(() => null);
  setTimeout(refresh, 300);
});
document.getElementById('note').textContent = t.note;
void refresh();
