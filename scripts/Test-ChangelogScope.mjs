import assert from 'node:assert/strict';
import { requiresChangelog } from './Check-ChangelogScope.mjs';

assert.equal(requiresChangelog('1.1.3'), false);
assert.equal(requiresChangelog('1.1.3 (#81)'), false);
assert.equal(requiresChangelog('1.1.3-rc1'), false);
assert.equal(requiresChangelog('1.1.3-rc12 (#81)'), false);
assert.equal(requiresChangelog('Release 1.1.3 (#81)'), true);
assert.equal(requiresChangelog('v1.1.3 (#81)'), true);
assert.equal(
  requiresChangelog('fix(changelog): RS-1404 retain ticket validation'),
  true,
);

console.log('Changelog scope rules passed.');
