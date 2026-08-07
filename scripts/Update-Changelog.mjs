import { appendFile, readFile, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';

const CHANGELOG_PATH = process.env.CHANGELOG_PATH || 'CHANGELOG.md';
const BEFORE_SHA = process.env.BEFORE_SHA || '';
const AFTER_SHA = process.env.AFTER_SHA || 'HEAD';
const ZERO_SHA = /^0+$/;
const TICKET_PATTERN = /\bRS-\d+\b/gi;
const SKIP_PATTERN = /\[skip changelog\]/i;
const CATEGORY_ORDER = ['Added', 'Changed', 'Deprecated', 'Removed', 'Fixed', 'Security'];

function runGit(args) {
  return execFileSync('git', args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 8 * 1024 * 1024,
  }).trimEnd();
}

function parseCommits(raw) {
  return raw
    .split('\x1e')
    .map((record) => record.trim())
    .filter(Boolean)
    .map((record) => {
      const [sha = '', subject = '', body = '', authorEmail = ''] = record.split('\x1f');
      return {
        sha,
        subject: subject.trim(),
        body: body.trim(),
        authorEmail: authorEmail.trim(),
      };
    });
}

function loadCommits() {
  const format = '%H%x1f%s%x1f%b%x1f%ae%x1e';
  const after = AFTER_SHA || 'HEAD';
  const hasBefore = BEFORE_SHA && !ZERO_SHA.test(BEFORE_SHA);

  try {
    if (hasBefore) {
      return parseCommits(
        runGit(['log', '--reverse', `--format=${format}`, `${BEFORE_SHA}..${after}`]),
      );
    }
    return parseCommits(runGit(['show', '-s', `--format=${format}`, after]));
  } catch (error) {
    if (!hasBefore) {
      throw error;
    }
    console.warn('Commit range was unavailable; evaluating the pushed head commit only.');
    return parseCommits(runGit(['show', '-s', `--format=${format}`, after]));
  }
}

function uniqueTickets(text) {
  return [...new Set(
    (text.match(TICKET_PATTERN) || []).map((ticket) => ticket.toUpperCase()),
  )];
}

function categoryFor(subject) {
  const type = subject.match(/^([a-z]+)(?:\([^)]*\))?!?:\s*/i)?.[1]?.toLowerCase();

  switch (type) {
    case 'feat':
      return 'Added';
    case 'fix':
      return 'Fixed';
    case 'security':
      return 'Security';
    case 'remove':
    case 'removed':
      return 'Removed';
    case 'deprecate':
    case 'deprecated':
      return 'Deprecated';
    default:
      return 'Changed';
  }
}

function cleanDescription(subject) {
  let description = subject
    .replace(/^([a-z]+)(?:\([^)]*\))?!?:\s*/i, '')
    .replace(TICKET_PATTERN, '')
    .replace(/^\s*[-:–—]+\s*/, '')
    .replace(/\s+/g, ' ')
    .trim();

  if (!description) {
    return '';
  }

  description = description[0].toUpperCase() + description.slice(1);
  return description.replace(/[.;:,]+$/, '');
}

function isWeakDescription(description) {
  if (description.length < 18) {
    return true;
  }

  return /^(update|changes?|misc|work|wip|cleanup|adjustments?|improvements?|fix(?:es)?|stuff)(?:\s+.*)?$/i
    .test(description);
}

function commitDiff(sha) {
  try {
    return runGit([
      'show',
      '--format=',
      '--unified=1',
      '--no-ext-diff',
      sha,
    ]).slice(0, 12000);
  } catch {
    return '';
  }
}

function extractResponseText(payload) {
  if (typeof payload.output_text === 'string') {
    return payload.output_text.trim();
  }

  const parts = [];
  for (const item of payload.output || []) {
    for (const content of item.content || []) {
      if (typeof content.text === 'string') {
        parts.push(content.text);
      }
    }
  }
  return parts.join('\n').trim();
}

async function improveDescription(commit, fallback) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey || !isWeakDescription(fallback)) {
    return fallback;
  }

  const model = process.env.OPENAI_MODEL || 'gpt-5-mini';
  const diff = commitDiff(commit.sha);
  const input = [
    'Write one concise Keep a Changelog bullet description in English.',
    'Return only the description, without a bullet, ticket number, SHA, category, or Markdown.',
    'Use past tense, describe user or developer impact, and do not invent behavior.',
    '',
    `Commit subject: ${commit.subject}`,
    commit.body ? `Commit body: ${commit.body}` : '',
    diff ? `Diff:\n${diff}` : '',
  ].filter(Boolean).join('\n');

  try {
    const response = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        store: false,
        input,
        max_output_tokens: 100,
      }),
      signal: AbortSignal.timeout(30000),
    });

    if (!response.ok) {
      console.warn(`OpenAI fallback returned HTTP ${response.status}; using the commit subject.`);
      return fallback;
    }

    const text = extractResponseText(await response.json())
      .replace(/^[-*]\s*/, '')
      .replace(TICKET_PATTERN, '')
      .replace(/\s*\([0-9a-f]{7,40}\)\s*$/i, '')
      .replace(/^['"]|['"]$/g, '')
      .replace(/\s+/g, ' ')
      .trim()
      .replace(/[.;:,]+$/, '');

    return text || fallback;
  } catch (error) {
    console.warn(
      `OpenAI fallback was unavailable (${error.name || 'error'}); using the commit subject.`,
    );
    return fallback;
  }
}

function keepAChangelogHeader() {
  return [
    '# Changelog',
    '',
    'All notable changes to this project will be documented in this file.',
    '',
    'The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),',
    'and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).',
    '',
    '',
  ].join('\n');
}

function unreleasedTemplate() {
  return [
    '## [Unreleased]',
    '',
    ...CATEGORY_ORDER.flatMap((category) => [`### ${category}`, '']),
  ].join('\n').trimEnd();
}

function normalizeVersionHeadings(content) {
  return content.replace(
    /^##\s+(?!\[)(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\s+-\s+/gm,
    '## [$1] - ',
  );
}

function normalizeChangelog(original) {
  let content = original.replace(/\r\n/g, '\n').trimEnd();
  content = content ? `${content}\n` : keepAChangelogHeader();
  content = normalizeVersionHeadings(content);

  if (!content.startsWith('# Changelog')) {
    content = `${keepAChangelogHeader()}${content.replace(/^\s+/, '')}`;
  } else if (!content.includes('Keep a Changelog')) {
    content = content.replace(/^# Changelog\s*\n/, keepAChangelogHeader());
  }

  if (!/^## \[Unreleased\][ \t]*$/m.test(content)) {
    const firstVersion = content.search(/^## \[[^\]]+\](?:\s+-\s+.*)?$/m);
    const block = `${unreleasedTemplate()}\n\n`;

    if (firstVersion >= 0) {
      content = `${content.slice(0, firstVersion)}${block}${content.slice(firstVersion)}`;
    } else {
      content = `${content.trimEnd()}\n\n${block}`;
    }
  }

  const unreleasedStart = content.search(/^## \[Unreleased\][ \t]*$/m);
  const headingEnd = content.indexOf('\n', unreleasedStart);
  const nextVersionRelative = content.slice(headingEnd + 1).search(/^## /m);
  const unreleasedEnd = nextVersionRelative >= 0
    ? headingEnd + 1 + nextVersionRelative
    : content.length;

  let block = content.slice(unreleasedStart, unreleasedEnd).trimEnd();
  for (const category of CATEGORY_ORDER) {
    if (!new RegExp(`^### ${category}[ \t]*$`, 'm').test(block)) {
      block += `\n\n### ${category}`;
    }
  }

  const remainder = content.slice(unreleasedEnd).replace(/^\s+/, '');
  return `${content.slice(0, unreleasedStart)}${block}\n\n${remainder}`.trimEnd() + '\n';
}

function addEntry(content, category, entry, shortSha) {
  if (content.includes(`(\`${shortSha}\`)`)) {
    return { content, added: false };
  }

  const unreleasedStart = content.search(/^## \[Unreleased\][ \t]*$/m);
  const headingEnd = content.indexOf('\n', unreleasedStart);
  const nextVersionRelative = content.slice(headingEnd + 1).search(/^## /m);
  const unreleasedEnd = nextVersionRelative >= 0
    ? headingEnd + 1 + nextVersionRelative
    : content.length;
  const block = content.slice(unreleasedStart, unreleasedEnd);

  const sectionPattern = new RegExp(`(^### ${category}[ \\t]*$\\n)`, 'm');
  const match = sectionPattern.exec(block);
  if (!match) {
    throw new Error(`Missing Unreleased category: ${category}`);
  }

  const insertAt = unreleasedStart + match.index + match[0].length;
  const remainder = content.slice(insertAt).replace(/^\n+/, '');
  const separator = remainder.startsWith('- ') ? '\n' : '\n\n';
  return {
    content: `${content.slice(0, insertAt)}\n${entry}${separator}${remainder}`,
    added: true,
  };
}

async function writeOutputs(values) {
  if (!process.env.GITHUB_OUTPUT) {
    return;
  }

  const lines = Object.entries(values)
    .map(([key, value]) => `${key}=${value}`)
    .join('\n');
  await appendFile(process.env.GITHUB_OUTPUT, `${lines}\n`, 'utf8');
}

async function main() {
  const commits = loadCommits().filter((commit) => {
    const message = `${commit.subject}\n${commit.body}`;
    return !SKIP_PATTERN.test(message)
      && !/github-actions\[bot\]/i.test(commit.authorEmail);
  });

  if (commits.length === 0) {
    console.log('No changelog-relevant commits found.');
    await writeOutputs({ changed: 'false', tickets: '', entries: '0' });
    return;
  }

  const missingTickets = commits.filter(
    (commit) => uniqueTickets(`${commit.subject}\n${commit.body}`).length === 0,
  );
  if (missingTickets.length > 0) {
    const list = missingTickets
      .map((commit) => `- ${commit.sha.slice(0, 7)} ${commit.subject}`)
      .join('\n');
    throw new Error(`Every change must reference an RS ticket. Missing ticket:\n${list}`);
  }

  let original = '';
  try {
    original = await readFile(CHANGELOG_PATH, 'utf8');
  } catch (error) {
    if (error.code !== 'ENOENT') {
      throw error;
    }
  }

  let content = normalizeChangelog(original);
  const allTickets = new Set();
  let addedCount = 0;

  for (const commit of commits) {
    const tickets = uniqueTickets(`${commit.subject}\n${commit.body}`);
    tickets.forEach((ticket) => allTickets.add(ticket));

    const ticket = tickets[0];
    const shortSha = commit.sha.slice(0, 7);
    const fallback = cleanDescription(commit.subject) || `Updated ${ticket}`;
    const description = await improveDescription(commit, fallback);
    const sentence = /[.!?]$/.test(description) ? description : `${description}.`;
    const entry = `- **${ticket}:** ${sentence} (\`${shortSha}\`)`;

    const result = addEntry(content, categoryFor(commit.subject), entry, shortSha);
    content = result.content;
    if (result.added) {
      addedCount += 1;
    }
  }

  const normalizedOriginal = original.replace(/\r\n/g, '\n');
  const changed = content !== normalizedOriginal;
  if (changed) {
    await writeFile(CHANGELOG_PATH, content, 'utf8');
  }

  await writeOutputs({
    changed: String(changed),
    tickets: [...allTickets].join(','),
    entries: String(addedCount),
  });

  console.log(
    changed
      ? `Updated ${CHANGELOG_PATH} with ${addedCount} new entr${addedCount === 1 ? 'y' : 'ies'}.`
      : 'Changelog is already current.',
  );
}

main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});
