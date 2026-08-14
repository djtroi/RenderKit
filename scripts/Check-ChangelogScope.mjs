import { appendFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { versionBranchPattern } from './Validate-ChangeTicket.mjs';

function normalizeVersionCandidate(value) {
  return (value || '').replace(/\s+\(#\d+\)\s*$/u, '').trim();
}

export function requiresChangelog(messageValue) {
  const message = messageValue || '';
  const lines = message
    .split(/\r?\n/u)
    .map((line) => line.trim())
    .filter(Boolean);
  const subject = lines[0] || '';
  const sourceTitle = normalizeVersionCandidate(subject);

  if (versionBranchPattern.test(sourceTitle)) {
    return false;
  }

  // A release PR can be integrated with either squash/rebase semantics or a
  // normal GitHub merge commit. In the latter case the version-only PR title
  // lives in the merge message body rather than the subject. Treat that exact
  // version line as the same release cut so changelog automation cannot turn
  // the release merge itself into a new Unreleased entry.
  if (/^Merge pull request #\d+\b/iu.test(subject)) {
    const mergedTitle = lines
      .slice(1)
      .map(normalizeVersionCandidate)
      .find((line) => versionBranchPattern.test(line));

    if (mergedTitle) {
      return false;
    }
  }

  const branchMerge = subject.match(
    /^Merge branch ['"](?<version>\d+\.\d+\.\d+(?:-rc\d+)?)['"] into main$/iu,
  );
  if (branchMerge && versionBranchPattern.test(branchMerge.groups.version)) {
    return false;
  }

  return true;
}

async function main() {
  const required = requiresChangelog(process.env.COMMIT_MESSAGE);

  if (process.env.GITHUB_OUTPUT) {
    await appendFile(
      process.env.GITHUB_OUTPUT,
      `required=${String(required)}\n`,
      'utf8',
    );
  }

  console.log(
    required
      ? 'The pushed commit requires changelog processing.'
      : 'Skipping changelog processing for a version-only release cut.',
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error.message || error);
    process.exitCode = 1;
  });
}
