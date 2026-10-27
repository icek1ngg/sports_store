// Read-only verification of pre-audit files; writes only MH09 audit artifacts.
const fs = require('fs');
const path = require('path');
const { createHash } = require('crypto');
const { execFileSync } = require('child_process');
const root = process.cwd();
const output = 'docs/features/mh09/artifacts';
const read = file => fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
const json = file => JSON.parse(read(file));
const write = (name, value) => fs.writeFileSync(`${output}/${name}.json`, JSON.stringify(value, null, 2) + '\n');
const hash = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const lines = file => {
  const content = read(file);
  return content ? content.split(/\r?\n/).length - (content.endsWith('\n') ? 1 : 0) : 0;
};
const baseline = json(`${output}/source_baseline.json`);
const before = json(`${output}/workspace_before.json`);
const changed = [], missing = [];
for (const item of baseline.files) {
  if (!fs.existsSync(item.path)) missing.push(item.path);
  else if (hash(item.path) !== item.sha256) changed.push(item.path);
}
const verification = { checkedAt: new Date().toISOString(), baselineFiles: baseline.files.length,
  unchanged: baseline.files.length - changed.length - missing.length, changed, missing };
write('source_verification', verification);
const gitFiles = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard'],
  { encoding: 'utf8' }).trim().split(/\r?\n/);
const relevant = file => [
  'lib/features/orders/', 'test/features/orders/', 'lib/core/state/',
  'tool/ui_preview/', 'test/ui_preview/', 'test/fixtures/', 'docs/features/mh09/',
].some(prefix => file.startsWith(prefix)) || [
  'lib/shared/widgets/async_content.dart', 'lib/shared/widgets/feature_access_gate.dart',
  'lib/shared/widgets/foreground_refresh.dart', 'lib/core/utils/display_formatters.dart',
  'lib/app/router/app_router.dart', 'test/visual_refinement/visual_layout_test.dart',
  'test/visual_refinement/preview_app_test.dart', 'test/shared/widgets/feature_access_gate_test.dart',
  'test/shared/widgets/foreground_refresh_test.dart',
  'docs/ui_mocks/MH09_Manager_Order_Details.html',
].includes(file);
function category(file) {
  if (file.endsWith('/HANDOFF.md')) return ['handoff', 100];
  if (file.endsWith('.md')) return ['feature markdown', 200];
  if (/\.(cjs|ps1|py)$/.test(file)) return ['renderer/utility', 150];
  if (!file.endsWith('.dart')) return ['reference', null];
  if (file.startsWith('test/')) return ['test/support', 400];
  if (file.startsWith('tool/')) return ['preview', 250];
  if (/\/(read_snapshot|session_scope|read_retry_policy)\.dart$/.test(file)) return ['domain/helper/formatter/DTO', 150];
  if (file.includes('/view_models/') || file.includes('/core/state/')) return ['viewmodel/controller', 250];
  if (file.includes('/pages/') || file.includes('/router/')) return ['page/coordinator', 300];
  if (file.includes('/widgets/')) return ['widget/section', 180];
  if (file.includes('/data/repositories/')) return ['repository adapter', 250];
  return ['domain/helper/formatter/DTO', 150];
}
const inventory = [...new Set(gitFiles)].filter(file => relevant(file) &&
  /\.(dart|md|cjs|html)$/.test(file) && fs.existsSync(file)).sort().map(file => {
  const [kind, limit] = category(file), loc = lines(file);
  return { path: file, kind, loc, limit, exceeds: limit != null && loc > limit,
    existedBefore: baseline.files.some(item => item.path === file) };
});
write('loc_inventory', inventory);
const docFiles = inventory.filter(item => item.kind === 'feature markdown' || item.kind === 'handoff');
const brokenLinks = [];
let linksChecked = 0;
for (const { path: file } of docFiles) {
  for (const match of read(file).matchAll(/!?\[[^\]]*\]\(([^)]+)\)/g)) {
    const target = match[1].replace(/^<|>$/g, '').split('#')[0];
    if (!target || /^[a-z]+:/i.test(target)) continue;
    linksChecked++;
    if (!fs.existsSync(path.resolve(path.dirname(file), decodeURIComponent(target)))) {
      brokenLinks.push({ file, target });
    }
  }
}
const status = execFileSync('git', ['status', '--porcelain=v1', '--untracked-files=all'],
  { encoding: 'utf8' }).trimEnd().split(/\r?\n/);
const allowed = file => file.startsWith('docs/features/mh09/') || [
  'tool/ui_preview/render_mh09_reference.cjs', 'tool/ui_preview/audit_mh09.cjs',
].includes(file);
const unexpectedNew = status.filter(entry => !before.status.includes(entry) && !allowed(entry.slice(3)));
const lostStatusEntries = before.status.filter(entry => !status.includes(entry));
const ownedViolations = inventory.filter(item => !item.existedBefore && item.exceeds);
const diff = execFileSync('git', ['diff', '--check'], { encoding: 'utf8' });
const manifest = json(`${output}/html_render_manifest.json`);
const artifactHashesMatch = manifest.screenshots.every(item => hash(item.path) === item.sha256);
const pngDimensions = manifest.screenshots.map(item => {
  const bytes = fs.readFileSync(item.path);
  return { path: item.path, width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
});
for (const file of ['render_mh09_reference.cjs', 'audit_mh09.cjs']) {
  execFileSync(process.execPath, ['--check', `tool/ui_preview/${file}`]);
}
const focusedLog = read(`${output}/focused_tests_elevated.log`);
const checks = { linksChecked, brokenLinks, ownedViolations, unexpectedNew, lostStatusEntries,
  baselineStatusEntries: before.statusEntryCount, currentStatusEntries: status.length,
  sourceUnchanged: !changed.length && !missing.length, diffCheck: diff.trim() || 'PASS',
  artifactHashesMatch, htmlSourceHashMatches: hash(manifest.source) === manifest.sourceSha256Before,
  pngDimensions, utilitySyntax: 'PASS', focusedLogReports39Passed: focusedLog.includes('+39: All tests passed!'),
  htmlRendered: manifest.viewport.width === 390 && manifest.viewport.height === 844 &&
    manifest.viewport.dpr === 1 && !manifest.sourceModified && !manifest.failures.length &&
    manifest.fontLoads.every(item => item.faces > 0 && item.loaded),
};
write('workspace_after', { branch: before.branch, status });
write('audit_validation', checks);
console.log(JSON.stringify({ ...checks, baselineFiles: verification.baselineFiles,
  inventoryFiles: inventory.length, legacyViolations: inventory.filter(i => i.existedBefore && i.exceeds).length }));
if (!checks.sourceUnchanged || brokenLinks.length || ownedViolations.length || unexpectedNew.length ||
    lostStatusEntries.length || !artifactHashesMatch || !checks.htmlSourceHashMatches || !checks.htmlRendered) {
  process.exitCode = 1;
}
