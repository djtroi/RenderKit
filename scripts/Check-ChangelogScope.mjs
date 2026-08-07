import { appendFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { versionBranchPattern } from './Validate-ChangeTicket.mjs';

export function requiresChangelog(messageValue) {
  const subject = (messageValue || '').split(/\r?\n/u, 1)[0].trim();
  const sourceTitle = subject.replace(/\s+\(#\d+\)\s*$/u, '').trim();

  return !versionBranchPattern.test(sourceTitle);
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
      : 'Skipping changelog processing for a version-only squash commit.',
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error.message || error);
    process.exitCode = 1;
  });
}
