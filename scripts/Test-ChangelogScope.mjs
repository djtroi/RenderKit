import assert from 'node:assert/strict';
import { requiresChangelog } from './Check-ChangelogScope.mjs';

assert.equal(requiresChangelog('1.1.3'), false);
assert.equal(requiresChangelog('1.1.3 (#81)'), false);
assert.equal(requiresChangelog('1.1.3-rc1'), false);
assert.equal(requiresChangelog('1.1.3-rc12 (#81)'), false);
assert.equal(
  requiresChangelog(
    'Merge pull request #86 from djtroi/1.1.5\n\n1.1.5',
  ),
  false,
);
assert.equal(
  requiresChangelog(
    "Merge branch '1.1.5' into main",
  ),
  false,
);
assert.equal(
  requiresChangelog(
    'Merge pull request #89 from djtroi/fix/RS-1513-worker-diagnostics-best-effort\n\nRS-1513: Harden worker diagnostic logging',
  ),
  true,
);
assert.equal(requiresChangelog('Release 1.1.3 (#81)'), true);
assert.equal(requiresChangelog('v1.1.3 (#81)'), true);
assert.equal(
  requiresChangelog('fix(changelog): RS-1404 retain ticket validation'),
  true,
);

console.log('Changelog scope rules passed.');
