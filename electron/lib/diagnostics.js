const fs = require('fs');
const http = require('http');
const path = require('path');
const { getIntegrationConfig } = require('./integration-config');

function readJson(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (error) {
    return { error: error.message };
  }
}

function readEnvValue(filePath, name) {
  try {
    if (!fs.existsSync(filePath)) return '';
    const lines = fs.readFileSync(filePath, 'utf8').split(/\r?\n/);
    const prefix = `${name}=`;
    const line = lines.find(item => item.trimStart().startsWith(prefix));
    if (!line) return '';
    return line.trim().slice(prefix.length).replace(/^["']|["']$/g, '');
  } catch {
    return '';
  }
}

function tailFile(filePath, maxChars = 4000) {
  try {
    if (!fs.existsSync(filePath)) return '';
    const content = fs.readFileSync(filePath, 'utf8');
    return content.slice(Math.max(0, content.length - maxChars));
  } catch (error) {
    return `Unable to read ${path.basename(filePath)}: ${error.message}`;
  }
}

function requestText(url, options = {}) {
  return new Promise(resolve => {
    const headers = options.headers || {};
    const started = Date.now();
    const request = http.get(url, { headers, timeout: options.timeoutMs || 2500 }, response => {
      let body = '';
      response.setEncoding('utf8');
      response.on('data', chunk => {
        if (body.length < 12000) body += chunk;
      });
      response.on('end', () => {
        const statusOk = options.requireSuccess
          ? response.statusCode >= 200 && response.statusCode < 300
          : response.statusCode >= 200 && response.statusCode < 500;
        resolve({
          ok: statusOk,
          statusCode: response.statusCode,
          ms: Date.now() - started,
          body,
        });
      });
    });

    request.on('timeout', () => {
      request.destroy();
      resolve({ ok: false, error: 'Timed out' });
    });
    request.on('error', error => resolve({ ok: false, error: error.message }));
  });
}

function titleContains(body, expectedTitle) {
  if (!expectedTitle) return true;
  const match = /<title>(.*?)<\/title>/is.exec(body || '');
  return !!(match && match[1].includes(expectedTitle));
}

async function testService(name, url, options = {}) {
  const result = await requestText(url, options);
  const contentOk = options.expectedContent ? (result.body || '').includes(options.expectedContent) : true;
  const titleOk = titleContains(result.body, options.expectedTitle);
  return {
    name,
    url,
    ok: !!(result.ok && contentOk && titleOk),
    statusCode: result.statusCode || null,
    ms: result.ms || null,
    error: result.error || '',
    detail: result.error || (!contentOk ? `Missing expected content: ${options.expectedContent}` : (!titleOk ? `Missing expected title: ${options.expectedTitle}` : '')),
  };
}

async function getDiagnosticsStatus() {
  const config = getIntegrationConfig();
  const state = readJson(config.statePath);
  const apiKey = readEnvValue(path.join(config.notionRoot, '.env'), 'API_KEY');
  const services = await Promise.all([
    testService('Notion2API health', config.notionHealthUrl, { expectedContent: 'ok' }),
    testService('LLM Council backend', config.councilSettingsUrl, { expectedContent: 'council_models' }),
    testService('LLM Council frontend', config.councilUiUrl, { expectedTitle: 'LLM Council' }),
    apiKey
      ? testService('Notion2API models', config.notionModelsUrl, { headers: { Authorization: `Bearer ${apiKey}` }, requireSuccess: true })
      : Promise.resolve({ name: 'Notion2API models', url: config.notionModelsUrl, ok: false, detail: 'API_KEY is missing from Notion2API .env' }),
  ]);

  const capabilitiesUrl = config.councilBackendUrl;
  const [settingsExportRes, askRes, healthRes] = await Promise.all([
    requestText(`${capabilitiesUrl}/api/settings/export`),
    requestText(`${capabilitiesUrl}/api/ask`),
    requestText(`${capabilitiesUrl}/api/health`),
  ]);

  const capabilities = {
    settings: services.find(s => s.name === 'LLM Council backend')?.ok || false,
    settingsExport: settingsExportRes.ok,
    settingsImport: settingsExportRes.ok,
    ask: askRes.statusCode !== 404,
    health: healthRes.ok,
  };

  const settingsResponse = await requestText(config.councilSettingsUrl);
  let provider = { ok: false, detail: 'Settings endpoint is unavailable' };
  if (settingsResponse.ok) {
    try {
      const settings = JSON.parse(settingsResponse.body);
      const enabled = settings.enabled_providers && settings.enabled_providers[config.providerEnabledKey] === true;
      const urlMatches = settings.custom_endpoint_url === config.providerUrl;
      const keyPresent = !!settings.custom_endpoint_api_key;
      provider = {
        ok: !!(enabled && urlMatches && keyPresent),
        name: settings.custom_endpoint_name || '',
        endpointUrl: settings.custom_endpoint_url || '',
        expectedEndpointUrl: config.providerUrl,
        enabled,
        keyPresent,
        urlMatches,
        detail: (enabled && urlMatches && keyPresent)
          ? ''
          : `${!enabled ? 'Custom provider disabled. ' : ''}${!urlMatches ? `URL mismatch (expected '${config.providerUrl}', got '${settings.custom_endpoint_url || '-'}'). ` : ''}${!keyPresent ? 'API key missing. ' : ''}`.trim(),
      };
    } catch (error) {
      provider = { ok: false, detail: `Could not parse settings JSON: ${error.message}` };
    }
  }

  return {
    checkedAt: new Date().toISOString(),
    config,
    state,
    provider,
    capabilities,
    services,
    logs: {
      notionError: tailFile(path.join(config.logsDir, 'notion2api.err.log')),
      notionOutput: tailFile(path.join(config.logsDir, 'notion2api.out.log')),
      backendError: tailFile(path.join(config.logsDir, 'council-backend.err.log')),
      frontendError: tailFile(path.join(config.logsDir, 'council-frontend.err.log')),
    },
  };
}

module.exports = {
  getDiagnosticsStatus,
};
