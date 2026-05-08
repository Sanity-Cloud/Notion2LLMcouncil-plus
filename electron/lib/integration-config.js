const fs = require('fs');
const path = require('path');
const { getAppRoot } = require('./utils');

function readJsonFile(filePath) {
  try {
    if (!fs.existsSync(filePath)) return {};
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return {};
  }
}

function getNested(source, parts) {
  let cursor = source;
  for (const part of parts) {
    if (!cursor || !Object.prototype.hasOwnProperty.call(cursor, part)) return undefined;
    cursor = cursor[part];
  }
  return cursor;
}

function getConfigValue(localConfig, defaultConfig, parts, fallback) {
  const localValue = getNested(localConfig, parts);
  if (localValue !== undefined && localValue !== null && `${localValue}` !== '') return localValue;
  const defaultValue = getNested(defaultConfig, parts);
  if (defaultValue !== undefined && defaultValue !== null && `${defaultValue}` !== '') return defaultValue;
  return fallback;
}

function resolveRepoPath(repoRoot, value) {
  if (!value) return '';
  return path.isAbsolute(value) ? value : path.resolve(repoRoot, value);
}

function getIntegrationConfig() {
  const repoRoot = getAppRoot();
  const configPath = process.env.NOTION2COUNCIL_CONFIG || path.join(repoRoot, 'config', 'local.json');
  const defaultConfig = readJsonFile(path.join(repoRoot, 'config', 'default.json'));
  const localConfig = readJsonFile(configPath);

  const notionPort = Number(getConfigValue(localConfig, defaultConfig, ['notion', 'port'], 8000));
  const councilBackendPort = Number(getConfigValue(localConfig, defaultConfig, ['council', 'backendPort'], 8001));
  const councilFrontendPort = Number(getConfigValue(localConfig, defaultConfig, ['council', 'frontendPort'], 5173));
  const providerUrlPath = getConfigValue(localConfig, defaultConfig, ['provider', 'urlPath'], '/v1');
  const providerEnabledKey = getConfigValue(localConfig, defaultConfig, ['provider', 'enabledKey'], 'custom');
  const providerName = getConfigValue(localConfig, defaultConfig, ['provider', 'name'], 'Notion2API');
  const notionRoot = resolveRepoPath(repoRoot, getConfigValue(localConfig, defaultConfig, ['notion', 'localRoot'], 'vendor\\notion2api'));
  const councilRoot = resolveRepoPath(repoRoot, getConfigValue(localConfig, defaultConfig, ['council', 'localRoot'], 'vendor\\llm-council-plus'));
  const logsDir = path.join(repoRoot, 'logs');
  const notionBaseUrl = process.env.NOTION2API_URL || `http://127.0.0.1:${notionPort}`;
  const councilBackendUrl = process.env.NOTION2COUNCIL_API_URL || `http://127.0.0.1:${councilBackendPort}`;
  const councilUiUrl = process.env.NOTION2COUNCIL_UI_URL || `http://127.0.0.1:${councilFrontendPort}/`;

  return {
    repoRoot,
    configPath,
    notionRoot,
    councilRoot,
    logsDir,
    statePath: path.join(logsDir, 'launcher-state.json'),
    restartFlagPath: path.join(logsDir, 'restart-notion.flag'),
    notionPort,
    councilBackendPort,
    councilFrontendPort,
    notionBaseUrl,
    notionHealthUrl: `${notionBaseUrl}/health`,
    notionDocsUrl: `${notionBaseUrl}/docs`,
    notionModelsUrl: `${notionBaseUrl}${providerUrlPath}/models`,
    councilBackendUrl,
    councilSettingsUrl: `${councilBackendUrl}/api/settings`,
    councilUiUrl,
    providerUrl: `${notionBaseUrl}${providerUrlPath}`,
    providerName,
    providerEnabledKey,
  };
}

function getEditableLocalConfig() {
  const current = getIntegrationConfig();
  return {
    configPath: current.configPath,
    values: {
      notionLocalRoot: current.notionRoot,
      notionPort: current.notionPort,
      councilLocalRoot: current.councilRoot,
      councilBackendPort: current.councilBackendPort,
      councilFrontendPort: current.councilFrontendPort,
      providerUrlPath: current.providerUrl.replace(current.notionBaseUrl, '') || '/v1',
    },
  };
}

function saveLocalIntegrationConfig(values) {
  const current = getIntegrationConfig();
  const existing = readJsonFile(current.configPath);
  const localConfig = {
    ...existing,
    notion: {
      ...(existing.notion || {}),
      localRoot: values.notionLocalRoot || undefined,
      port: Number(values.notionPort) || current.notionPort,
    },
    council: {
      ...(existing.council || {}),
      localRoot: values.councilLocalRoot || undefined,
      backendPort: Number(values.councilBackendPort) || current.councilBackendPort,
      frontendPort: Number(values.councilFrontendPort) || current.councilFrontendPort,
    },
    provider: {
      ...(existing.provider || {}),
      urlPath: values.providerUrlPath || '/v1',
    },
  };

  fs.mkdirSync(path.dirname(current.configPath), { recursive: true });
  fs.writeFileSync(current.configPath, `${JSON.stringify(localConfig, null, 2)}\n`, 'utf8');
  return getEditableLocalConfig();
}

module.exports = {
  getIntegrationConfig,
  getEditableLocalConfig,
  saveLocalIntegrationConfig,
};
