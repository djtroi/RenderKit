import assert from 'node:assert/strict';
import {
  validateChangeTicket,
  versionBranchPattern,
} from './Validate-ChangeTicket.mjs';

assert.equal(versionBranchPattern.test('1.1.3'), true);
assert.equal(versionBranchPattern.test('1.1.3-rc1'), true);
assert.equal(versionBranchPattern.test('1.1.3-rc12'), true);
assert.equal(versionBranchPattern.test('release/1.1.3'), false);
assert.equal(versionBranchPattern.test('v1.1.3'), false);
assert.equal(versionBranchPattern.test('1.1.3-rc'), false);

assert.deepEqual(validateChangeTicket('1.1.3', '1.1.3'), {
  exempt: true,
  headRef: '1.1.3',
  ticket: null,
});

assert.deepEqual(validateChangeTicket('Release candidate', '1.1.3-rc12'), {
  exempt: true,
  headRef: '1.1.3-rc12',
  ticket: null,
});

assert.equal(
  validateChangeTicket(
    'fix(changelog): RS-1404 retain ticket validation',
    'fix/RS-1404-ticket-validation',
  ).ticket,
  'RS-1404',
);

assert.throws(
  () => validateChangeTicket('Release 1.1.3', 'release/1.1.3'),
  /must contain an RS ticket/u,
);

assert.throws(
  () => validateChangeTicket('Fix validation', 'fix/ticket-validation'),
  /must contain an RS ticket/u,
);

console.log('Ticket validation rules passed.');
