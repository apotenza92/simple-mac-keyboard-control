import {repository, selectRelease} from './release-model.mjs';
const params = new URLSearchParams(location.search);
let channel = params.get('channel') === 'beta' ? 'beta' : 'stable';
let arch = params.get('arch') === 'x64' ? 'x64' : 'arm64';
let releases = [], state = 'loading';
const appearance = matchMedia('(prefers-color-scheme: dark)');
appearance.addEventListener('change', () => render());
const byId = id => document.getElementById(id);
function render() {
  document.body.classList.toggle('beta', channel === 'beta');
  document.querySelectorAll('[data-channel]').forEach(button => button.setAttribute('aria-pressed', button.dataset.channel === channel));
  document.querySelectorAll('[data-arch]').forEach(button => button.setAttribute('aria-pressed', button.dataset.arch === arch));
  byId('app-icon').src = `assets/icon-${channel}-${appearance.matches ? 'dark' : 'light'}.svg`;
  byId('app-title').textContent = `Simple Mac Keyboard Control${channel === 'beta' ? ' Beta' : ''}`;
  byId('channel-description').hidden = channel !== 'beta';
  byId('compatibility').textContent = arch === 'arm64' ? 'Hardware brightness over DDC/CI requires a compatible monitor and connection.' : 'Intel uses software dimming for external displays; hardware DDC is not supported in the first release.';
  const selected = selectRelease(releases, channel, arch);
  const link = byId('download-link'), notes = byId('release-notes');
  link.href = `https://github.com/${repository}/releases`;
  link.textContent = 'Browse releases ↗';
  notes.hidden = true;
  if (state === 'loading') byId('release-status').textContent = 'Checking available releases…';
  else if (state === 'error') byId('release-status').textContent = 'Release information is unavailable. The project may still be private; please check GitHub.';
  else if (!selected) byId('release-status').textContent = `No ${channel} release has been published yet.`;
  else if (!selected.asset) byId('release-status').textContent = `${selected.release.tag_name}: no ${channel} download is available for this Mac yet.`;
  else {
    byId('release-status').textContent = `${selected.release.tag_name} · macOS 14.4 or later · ZIP download`;
    link.href = selected.asset.browser_download_url;
    link.textContent = `Download ${channel === 'beta' ? 'beta' : 'stable'} for ${arch === 'arm64' ? 'Apple silicon' : 'Intel'} ↓`;
    notes.href = `https://github.com/${repository}/releases/tag/${selected.release.tag_name}`;
    notes.hidden = false;
  }
}
function choose() {
  const url = new URL(location.href);
  url.searchParams.set('channel', channel); url.searchParams.set('arch', arch);
  history.replaceState(null, '', url);
  render();
}
document.querySelectorAll('[data-channel]').forEach(button => button.addEventListener('click', () => { channel = button.dataset.channel; choose(); }));
document.querySelectorAll('[data-arch]').forEach(button => button.addEventListener('click', () => { arch = button.dataset.arch; choose(); }));
render();
try {
  // GitHub returns newest-created first; collect all pages before sorting by version.
  for (let page = 1; ; page++) {
    const response = await fetch(`https://api.github.com/repos/${repository}/releases?per_page=100&page=${page}`, {headers:{Accept:'application/vnd.github+json'}, signal:AbortSignal.timeout(10000)});
    if (!response.ok) throw new Error('Release lookup failed');
    const batch = await response.json();
    if (!Array.isArray(batch)) throw new Error('Invalid release response');
    releases.push(...batch);
    if (batch.length < 100) break;
  }
  state = 'ready';
} catch { state = 'error'; releases = []; }
render();
