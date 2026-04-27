/**
 * JSX/TSX Audit — testa cada fixture contra compiler e linter
 * Uso: node tests/jsx/audit.mjs
 */
import { spawnSync } from 'node:child_process';
import { readdirSync, readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { resolve, join, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..', '..');

const COMPILER = resolve(ROOT, 'zig-out', 'bin', 'nxc-compiler');
const LINTER = resolve(ROOT, 'zig-out', 'bin', 'nxc-linter');
const RESULT_DIR = resolve(__dirname, '..', '..', 'docs');

const TIMEOUT_MS = 10_000;

function testTool(toolPath, args, filePath, label) {
  const start = Date.now();
  const result = spawnSync(toolPath, [...args, filePath], {
    encoding: 'utf-8',
    maxBuffer: 100 * 1024 * 1024,
    timeout: TIMEOUT_MS,
    stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env },
  });
  const elapsed = Date.now() - start;

  if (result.error) {
    if (result.error.code === 'ETIMEDOUT') return { status: 'TIMEOUT', elapsed, msg: 'timeout >' + TIMEOUT_MS + 'ms' };
    return { status: 'ERROR', elapsed, msg: result.error.message };
  }
  if (result.signal === 'SIGTERM') return { status: 'TIMEOUT', elapsed, msg: 'killed after ' + TIMEOUT_MS + 'ms' };
  if (result.status !== 0) return { status: 'FAIL', elapsed, msg: (result.stderr || result.stdout || 'exit ' + result.status).slice(0, 200) };
  return { status: 'OK', elapsed, msg: '' };
}

function collectFixtures(baseDir) {
  const files = [];
  if (!existsSync(baseDir)) return files;
  for (const entry of readdirSync(baseDir)) {
    const p = join(baseDir, entry);
    files.push({ name: entry, path: p, ext: extname(entry) });
  }
  return files.sort();
}

function runAudit(label, fixturesDir) {
  const fixtures = collectFixtures(fixturesDir);
  console.log(`\n## ${label} Fixtures (${fixtures.length} files)\n`);

  const results = [];

  for (const f of fixtures) {
    const name = f.name.replace(/\.(jsx|tsx)$/, '');

    const compilerResult = testTool(COMPILER, ['--no-ts'], f.path, name);
    // Use --no-ts para tratar como JSX (não tenta strip types)
    const compilerTS = testTool(COMPILER, [], f.path, name);
    const linterResult = testTool(LINTER, [], f.path, name);
    const linterFixResult = testTool(LINTER, ['--fix'], f.path, name);

    const feature = name.replace(/-/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
    console.log(`  ${feature.padEnd(28)} compiler=${compilerResult.status.padEnd(8)} linter=${linterResult.status.padEnd(8)} linter-fix=${linterFixResult.status.padEnd(8)} (${compilerResult.elapsed}ms)`);

    results.push({
      feature,
      file: f.name,
      compiler: compilerResult.status,
      compilerTS: compilerTS.status,
      linter: linterResult.status,
      linterFix: linterFixResult.status,
      compilerMs: compilerResult.elapsed,
      linterMs: linterResult.elapsed,
      compilerError: compilerResult.msg,
      linterError: linterResult.msg,
    });
  }

  return results;
}

// ── Main ──
const jsxResults = runAudit('JSX', resolve(__dirname, 'fixtures'));
const tsxResults = runAudit('TSX', resolve(__dirname, '..', 'tsx', 'fixtures'));

// Generate markdown matrix
let md = `# JSX/TSX Compatibility Matrix

> Auto-generated: ${new Date().toISOString().slice(0, 19)}
> Compiler: ${COMPILER}
> Linter: ${LINTER}

---

## JSX Features

| Feature | Compiler | Linter | Formatter (--fix) | Status |
|---------|:--------:|:------:|:-----------------:|:------:|
`;

for (const r of jsxResults) {
  const ok = r.compiler === 'OK' && r.linter !== 'TIMEOUT';
  const statusIcon = ok ? '✅' : r.linter === 'TIMEOUT' ? '🔴' : '🟡';
  const formatterStat = r.linterFix === 'OK' ? 'OK' : r.linterFix;
  md += `| ${r.feature} | ${r.compiler} | ${r.linter} | ${formatterStat} | ${statusIcon} |\n`;
}

md += `\n## TSX Features\n\n| Feature | Compiler | Linter | Formatter (--fix) | Status |\n|---------|:--------:|:------:|:-----------------:|:------:|\n`;

for (const r of tsxResults) {
  const ok = r.compiler === 'OK' && r.linter !== 'TIMEOUT';
  const statusIcon = ok ? '✅' : r.linter === 'TIMEOUT' ? '🔴' : '🟡';
  const formatterStat = r.linterFix === 'OK' ? 'OK' : r.linterFix;
  md += `| ${r.feature} | ${r.compiler} | ${r.linter} | ${formatterStat} | ${statusIcon} |\n`;
}

// Summary
const all = [...jsxResults, ...tsxResults];
const okCount = all.filter(r => r.compiler === 'OK' && r.linter === 'OK').length;
const timeoutCount = all.filter(r => r.linter === 'TIMEOUT' || r.compiler === 'TIMEOUT').length;
const failCount = all.length - okCount - timeoutCount;

md += `\n## Summary\n\n`;
md += `| Category | Count |\n|----------|:----:|\n`;
md += `| Total fixtures | ${all.length} |\n`;
md += `| ✅ Fully working (compiler + linter) | ${okCount} |\n`;
md += `| 🔴 Timeout | ${timeoutCount} |\n`;
md += `| 🟡 Other failures | ${failCount} |\n`;

md += `\n## Linter Timeouts\n\n`;
const timeouts = all.filter(r => r.linter === 'TIMEOUT');
if (timeouts.length === 0) {
  md += `None! 🎉\n`;
} else {
  for (const t of timeouts) {
    md += `- **${t.feature}** (${t.file})\n`;
  }
}

md += `\n---\n*Generated by tests/jsx/audit.mjs*\n`;

const outPath = join(RESULT_DIR, 'jsx-compatibility-matrix.md');
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, md);
console.log(`\n📄 Matrix saved to: ${outPath}`);
