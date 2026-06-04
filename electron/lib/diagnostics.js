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

function requestJsonPost(url, bodyObject, options = {}) {
  return new Promise(resolve => {
    const parsedUrl = new URL(url);
    const bodyStr = JSON.stringify(bodyObject);
    const headers = {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(bodyStr),
      ...(options.headers || {})
    };
    const started = Date.now();
    const reqOptions = {
      method: 'POST',
      hostname: parsedUrl.hostname,
      port: parsedUrl.port,
      path: parsedUrl.pathname + parsedUrl.search,
      headers,
      timeout: options.timeoutMs || 5000
    };

    const request = http.request(reqOptions, response => {
      let body = '';
      response.setEncoding('utf8');
      response.on('data', chunk => {
        if (body.length < 12000) body += chunk;
      });
      response.on('end', () => {
        const ok = response.statusCode >= 200 && response.statusCode < 300;
        resolve({
          ok,
          statusCode: response.statusCode,
          ms: Date.now() - started,
          body
        });
      });
    });

    request.on('timeout', () => {
      request.destroy();
      resolve({ ok: false, error: 'Timed out' });
    });
    request.on('error', error => resolve({ ok: false, error: error.message }));

    request.write(bodyStr);
    request.end();
  });
}

function getCouncilSmokePayload(config, options = {}) {
  const testModel = (Array.isArray(config.councilModels) && config.councilModels.length > 0)
    ? config.councilModels[0]
    : 'custom:gpt-5.5';
  return {
    content: options.content || 'Reply with exactly: pong',
    models: [testModel],
    chairman_model: config.chairmanModel || 'custom:claude-opus4.7',
    web_search: false,
    execution_mode: 'chat_only',
  };
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

  const runtimeNotionBaseUrl = (state && state.notion && state.notion.url)
    ? state.notion.url
    : config.notionBaseUrl;

  const runtimeProviderUrl = `${runtimeNotionBaseUrl}${config.providerUrlPath || '/v1'}`;
  const notionHealthUrl = `${runtimeNotionBaseUrl}/health`;
  const notionModelsUrl = `${runtimeProviderUrl}/models`;

  const runtimeCouncilBackendUrl = (state && state.councilBackend && state.councilBackend.url)
    ? state.councilBackend.url
    : config.councilBackendUrl;

  const runtimeCouncilUiUrl = (state && state.councilFrontend && state.councilFrontend.url)
    ? state.councilFrontend.url
    : config.councilUiUrl;

  const councilSettingsUrl = `${runtimeCouncilBackendUrl}/api/settings`;

  const services = await Promise.all([
    testService('Notion2API health', notionHealthUrl, { expectedContent: 'ok' }),
    testService('LLM Council backend', councilSettingsUrl, { expectedContent: 'council_models' }),
    testService('LLM Council frontend', runtimeCouncilUiUrl),
    apiKey
      ? testService('Notion2API models', notionModelsUrl, { headers: { Authorization: `Bearer ${apiKey}` }, requireSuccess: true })
      : Promise.resolve({ name: 'Notion2API models', url: notionModelsUrl, ok: false, detail: 'API_KEY is missing from Notion2API .env' }),
  ]);

  const [settingsExportRes, askRes, healthRes] = await Promise.all([
    requestText(`${runtimeCouncilBackendUrl}/api/settings/export`),
    requestText(`${runtimeCouncilBackendUrl}/api/ask`),
    requestText(`${runtimeCouncilBackendUrl}/api/health`),
  ]);

  const capabilities = {
    settings: services.find(s => s.name === 'LLM Council backend')?.ok || false,
    settingsExport: settingsExportRes.ok,
    settingsImport: settingsExportRes.ok,
    ask: askRes.statusCode !== 404,
    health: healthRes.ok,
  };

  const settingsResponse = await requestText(councilSettingsUrl);
  let provider = { ok: false, detail: 'Settings endpoint is unavailable' };
  if (settingsResponse.ok) {
    try {
      const settings = JSON.parse(settingsResponse.body);
      const enabled = settings.enabled_providers && settings.enabled_providers[config.providerEnabledKey] === true;
      const urlMatches = settings.custom_endpoint_url === runtimeProviderUrl;
      const keyPresent = !!(settings.custom_endpoint_api_key || settings.custom_endpoint_api_key_set);

      let apiKeyStatus = 'unknown';
      if (keyPresent) {
        const val = settings.custom_endpoint_api_key;
        if (val) {
          if (val.includes('**') || val === 'set' || val === 'true') {
            apiKeyStatus = 'redacted';
          } else {
            apiKeyStatus = 'saved';
          }
        } else if (settings.custom_endpoint_api_key_set) {
          apiKeyStatus = 'saved/redacted';
        }
      }

      let smokeTestOk = true;
      let smokeDetail = '';
      if (enabled && urlMatches && config.askSmokeTest !== false) {
        try {
          const smokePayload = getCouncilSmokePayload(config, {
            content: 'Reply with exactly: pong'
          });
          const smokeRes = await requestJsonPost(`${runtimeCouncilBackendUrl}/api/ask`, smokePayload, { timeoutMs: 30000 });
          if (smokeRes.ok) {
            const smokeJson = JSON.parse(smokeRes.body);
            if (smokeJson.responses && smokeJson.responses[0]) {
              const firstResp = smokeJson.responses[0];
              if (firstResp.error) {
                smokeTestOk = false;
                smokeDetail = `Smoke test model returned error: ${firstResp.error}`;
              }
            } else if (smokeJson.error) {
              smokeTestOk = false;
              smokeDetail = `Smoke test returned error: ${smokeJson.error}`;
            }
          } else {
            smokeTestOk = false;
            smokeDetail = `Smoke test HTTP failed: ${smokeRes.statusCode || smokeRes.error || 'unknown error'}`;
          }
        } catch (smokeError) {
          smokeTestOk = false;
          smokeDetail = `Smoke test failed: ${smokeError.message}`;
        }
      }

      provider = {
        ok: !!(enabled && urlMatches && smokeTestOk),
        name: settings.custom_endpoint_name || '',
        endpointUrl: settings.custom_endpoint_url || '',
        expectedEndpointUrl: runtimeProviderUrl,
        enabled,
        urlMatches,
        keyPresent,
        apiKeyStatus,
        smokeTestOk,
        detail: (enabled && urlMatches && smokeTestOk)
          ? ''
          : `${!enabled ? 'Custom provider disabled. ' : ''}${!urlMatches ? `URL mismatch (expected '${runtimeProviderUrl}', got '${settings.custom_endpoint_url || '-'}'). ` : ''}${!smokeTestOk ? `${smokeDetail}. ` : ''}`.trim(),
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
