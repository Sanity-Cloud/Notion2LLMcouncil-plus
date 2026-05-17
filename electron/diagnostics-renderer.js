const api = window.notion2CouncilDiagnostics;
let lastData = null;
let activeLog = 'notionError';

const checkedAt = document.getElementById('checkedAt');
const servicesEl = document.getElementById('services');
const providerEl = document.getElementById('provider');
const configEl = document.getElementById('config');
const stateEl = document.getElementById('state');
const logEl = document.getElementById('log');
const statusEl = document.getElementById('status');
const configPathEl = document.getElementById('configPath');
const configFields = ['notionLocalRoot', 'notionPort', 'councilLocalRoot', 'councilBackendPort', 'councilFrontendPort', 'providerUrlPath'];

function setStatus(text) {
  statusEl.textContent = text || '';
}

function formatValue(value) {
  if (value === undefined || value === null || value === '') return '-';
  if (typeof value === 'boolean') return value ? 'yes' : 'no';
  return String(value);
}

function renderDefinitionList(el, entries) {
  el.textContent = '';
  for (const [key, value] of entries) {
    const dt = document.createElement('dt');
    dt.textContent = key;
    const dd = document.createElement('dd');
    dd.textContent = formatValue(value);
    el.append(dt, dd);
  }
}

function renderServices(services) {
  servicesEl.textContent = '';
  for (const service of services || []) {
    const row = document.createElement('div');
    row.className = 'service';

    const dot = document.createElement('div');
    dot.className = `dot ${service.ok ? 'ok' : 'bad'}`;

    const body = document.createElement('div');
    const name = document.createElement('div');
    name.className = 'name';
    name.textContent = service.name;
    const url = document.createElement('div');
    url.className = 'url';
    url.textContent = service.detail ? `${service.url} - ${service.detail}` : service.url;
    body.append(name, url);

    const pill = document.createElement('div');
    pill.className = 'pill';
    pill.textContent = service.statusCode ? `${service.statusCode} / ${service.ms}ms` : 'offline';

    row.append(dot, body, pill);
    servicesEl.append(row);
  }
}

function render(data) {
  lastData = data;
  checkedAt.textContent = `Last checked: ${new Date(data.checkedAt).toLocaleString()}`;
  renderServices(data.services);
  renderDefinitionList(providerEl, [
    ['Status', data.provider.ok ? 'configured' : 'needs attention'],
    ['Name', data.provider.name],
    ['Enabled', data.provider.enabled],
    ['Endpoint', data.provider.endpointUrl],
    ['Expected', data.provider.expectedEndpointUrl],
    ['URL Match', data.provider.urlMatches],
    ['API Key Present', data.provider.keyPresent],
    ['/api/settings', data.capabilities?.settings ? 'yes' : 'no'],
    ['/api/settings/export', data.capabilities?.settingsExport ? 'yes' : 'no'],
    ['/api/settings/import', data.capabilities?.settingsImport ? 'yes' : 'no'],
    ['/api/ask', data.capabilities?.ask ? 'yes' : 'no'],
    ['/api/health', data.capabilities?.health ? 'yes' : 'no'],
    ['Detail', data.provider.detail],
  ]);
  renderDefinitionList(configEl, [
    ['Repo root', data.config.repoRoot],
    ['Config path', data.config.configPath],
    ['Notion root', data.config.notionRoot],
    ['Council root', data.config.councilRoot],
    ['Notion URL', data.config.notionBaseUrl],
    ['Council API', data.config.councilBackendUrl],
    ['Council UI', data.config.councilUiUrl],
    ['Logs', data.config.logsDir],
  ]);
  stateEl.textContent = data.state ? JSON.stringify(data.state, null, 2) : 'No launcher state file has been written yet.';
  logEl.textContent = data.logs?.[activeLog] || 'No log output.';
}

function readConfigForm() {
  return Object.fromEntries(configFields.map(id => [id, document.getElementById(id).value.trim()]));
}

function writeConfigForm(data) {
  configPathEl.textContent = `Saved at: ${data.configPath}`;
  for (const id of configFields) {
    document.getElementById(id).value = data.values?.[id] ?? '';
  }
}

async function refresh() {
  setStatus('Checking services...');
  try {
    const [statusRes, configRes] = await Promise.allSettled([api.status(), api.getConfig()]);
    const messages = [];

    if (statusRes.status === 'fulfilled') {
      render(statusRes.value);
    } else {
      messages.push(`Diagnostics status check error: ${statusRes.reason?.message || statusRes.reason}`);
    }

    if (configRes.status === 'fulfilled') {
      writeConfigForm(configRes.value);
    } else {
      messages.push(`Config load error: ${configRes.reason?.message || configRes.reason}`);
    }

    setStatus(messages.join(' | '));
  } catch (error) {
    setStatus(`Diagnostics error: ${error.message}`);
  }
}

document.getElementById('refresh').addEventListener('click', refresh);
document.getElementById('start').addEventListener('click', async () => {
  setStatus('Starting stack...');
  await api.start();
  setTimeout(refresh, 1500);
});
document.getElementById('stop').addEventListener('click', async () => {
  setStatus('Stopping stack...');
  await api.stop();
  setTimeout(refresh, 1500);
});
document.getElementById('openUi').addEventListener('click', () => api.openCouncil());
document.getElementById('openDocs').addEventListener('click', () => api.openDocs());
document.getElementById('openLogs').addEventListener('click', () => api.openLogs());
document.getElementById('saveConfig').addEventListener('click', async () => {
  setStatus('Saving local configuration...');
  try {
    writeConfigForm(await api.saveConfig(readConfigForm()));
    await refresh();
    setStatus('Local configuration saved. Restart the stack for port or path changes to take effect.');
  } catch (error) {
    setStatus(`Could not save local configuration: ${error.message}`);
  }
});

document.querySelectorAll('[data-log]').forEach(button => {
  button.addEventListener('click', () => {
    document.querySelectorAll('[data-log]').forEach(item => item.classList.remove('active'));
    button.classList.add('active');
    activeLog = button.dataset.log;
    if (lastData) logEl.textContent = lastData.logs?.[activeLog] || 'No log output.';
  });
});

refresh();
