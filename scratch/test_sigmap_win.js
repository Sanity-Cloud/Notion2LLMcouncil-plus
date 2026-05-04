const { execSync } = require('child_process');
const cwd = process.cwd();
try {
  const cmd = `git log --oneline -5 --no-decorate 2>/dev/null`;
  console.log('Running:', cmd);
  const out = execSync(cmd, { cwd, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
  console.log('Output:', out);
} catch (e) {
  console.error('Error:', e.message);
  if (e.stderr) console.error('Stderr:', e.stderr.toString());
}
