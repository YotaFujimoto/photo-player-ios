import fs from 'node:fs';
import path from 'node:path';

// Gate the device archive on the complete source-derived XCTest set, not just
// green matrix jobs. A missing, repeated, failed or timed-out case is fatal.
const directory = process.argv[2];
const groups = ['core', 'playback', 'library', 'frames'];
const expected = ['PhotoPlayerTests', 'PhotoPlayerUITests'].flatMap(module =>
  fs.readdirSync(module).filter(file => file.endsWith('.swift')).flatMap(file => {
    const source = fs.readFileSync(path.join(module, file), 'utf8');
    const type = source.match(/class\s+(\w+)\s*:\s*XCTestCase/);
    return type ? [...source.matchAll(/func\s+(test\w+)\s*\(/g)]
      .map(match => `${module}.${type[1]} ${match[1]}`) : [];
  }));
const cases = [];
let hosts = 0;
for (const group of groups) {
  const log = fs.readFileSync(path.join(directory, `results-${group}.log`), 'utf8');
  if (/TEST EXECUTE FAILED|Restarting after unexpected|exceeded execution time|Timed out while|CI_HOST_CLEANUP_FAILED/.test(log)) {
    throw new Error(`Failed or incomplete test host: ${group}`);
  }
  const completed = [...log.matchAll(/Test Case '-\[(.*?)\]' (passed|failed) \((.*?) seconds\)\./g)];
  if (!completed.length || completed.some(match => match[2] !== 'passed')) {
    throw new Error(`Missing or failed cases: ${group}`);
  }
  cases.push(...completed.map(match => match[1]));
  hosts += [...log.matchAll(/\*\* TEST EXECUTE SUCCEEDED \*\*/g)].length;
  if (group === 'playback' || group === 'frames') {
    const prefix = group === 'frames' ? 'Original' : '';
    for (const orientation of ['Portrait', 'Landscape']) {
      const marker = `CI_HOST_CLEANUP verified_not_running ${prefix}SeekBar${orientation}`;
      if (log.split(marker).length - 1 !== 1) throw new Error(`Missing/repeated process cleanup: ${marker}`);
    }
  }
}
const actual = new Set(cases);
const missing = expected.filter(name => !actual.has(name));
const unexpected = cases.filter(name => !expected.includes(name));
if (actual.size !== cases.length || missing.length || unexpected.length) {
  throw new Error(JSON.stringify({ missing, unexpected, duplicateCount: cases.length - actual.size }));
}
console.log(JSON.stringify({ xctestCases: cases.length, uniqueCases: actual.size, hosts,
  groups, failed: 0, missing: 0, duplicates: 0 }, null, 2));
