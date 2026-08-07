import { pathToFileURL } from 'node:url';

const ticketPattern = /\bRS-\d+\b/i;
export const versionBranchPattern = /^\d+\.\d+\.\d+(?:-rc\d+)?$/i;

export function validateChangeTicket(titleValue, headRefValue) {
  const title = (titleValue || '').trim();
  const headRef = (headRefValue || '').trim();

  if (versionBranchPattern.test(headRef)) {
    return {
      exempt: true,
      headRef,
      ticket: null,
    };
  }

  if (!title) {
    throw new Error('Pull request title is unavailable.');
  }

  const ticket = title.match(ticketPattern)?.[0]?.toUpperCase();
  if (!ticket) {
    throw new Error(
      'Pull request title must contain an RS ticket, for example RS-1404.',
    );
  }

  return {
    exempt: false,
    headRef,
    ticket,
  };
}

function main() {
  try {
    const result = validateChangeTicket(
      process.env.PR_TITLE,
      process.env.PR_HEAD_REF,
    );

    if (result.exempt) {
      console.log(
        `Version branch ${result.headRef} is exempt from RS ticket validation.`,
      );
      return;
    }

    console.log(`Validated change ticket ${result.ticket} in the pull request title.`);
  } catch (error) {
    console.error(error.message || error);
    process.exitCode = 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
