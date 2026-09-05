import test from 'node:test';
import assert from 'node:assert/strict';
import {repository, prefix, selectRelease} from '../../docs/release-model.mjs';
function release(tag, channels = ['stable', 'beta']) {
  return {tag_name:tag, prerelease:tag.includes('-beta.'), draft:false,
    assets:channels.flatMap(channel => ['arm64','x64'].map(arch => {
      const name = `${prefix}${channel === 'beta' ? '-Beta' : ''}-${tag}-macos-${arch}.zip`;
      return {name, browser_download_url:`https://github.com/${repository}/releases/download/${tag}/${name}`};
    }))};
}
test('stable excludes beta, drafts, and malformed tags', () => {
  assert.equal(selectRelease([release('v0.1.0'),release('v0.2.0-beta.1',['beta']),{...release('v9.0.0'),draft:true},release('nonsense')],'stable','arm64').release.tag_name,'v0.1.0');
});
test('beta tracks newest semantic version including stable', () => {
  assert.equal(selectRelease([release('v0.2.0-beta.9',['beta']),release('v0.2.0')],'beta','x64').release.tag_name,'v0.2.0');
  assert.equal(selectRelease([release('v0.2.0'),release('v0.3.0-beta.2',['beta'])],'beta','arm64').release.tag_name,'v0.3.0-beta.2');
});
test('missing package never substitutes stable or an old build', () => {
  const selected = selectRelease([release('v0.1.0'),release('v0.2.0',['stable'])],'beta','arm64');
  assert.equal(selected.release.tag_name,'v0.2.0'); assert.equal(selected.asset, undefined);
});
test('only exact trusted asset URLs are download links', () => {
  const item=release('v0.1.0'); item.assets[0].browser_download_url='https://example.com/fake.zip';
  assert.equal(selectRelease([item],'stable','arm64').asset,undefined);
});
test('empty and inconsistent prerelease data is unavailable', () => {
  assert.equal(selectRelease([],'stable','arm64'),null);
  assert.equal(selectRelease([{...release('v0.1.0-beta.1'),prerelease:false}],'stable','arm64'),null);
});
