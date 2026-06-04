const fs = require('fs');
const path = require('path');
const { app } = require('electron');
const { ensureDir, getAppRoot, getRuntimeRoot, getUserDataRoot, isInsideAsar } = require('./utils');
const { getLogsDir } = require('./logger');

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

function getDefaultConfigPath(repoRoot) {
  return path.join(repoRoot, 'config', 'default.json');
}

function getLocalConfigPath(repoRoot) {
  if (process.env.NOTION2COUNCIL_CONFIG) return process.env.NOTION2COUNCIL_CONFIG;
  if (app.isPackaged || isInsideAsar(repoRoot)) {
    return path.join(ensureDir(path.join(getUserDataRoot(), 'config')), 'local.json');
  }
  return path.join(repoRoot, 'config', 'local.json');
}

function resolveRuntimePath(repoRoot, value, fallbackRelative) {
  const configured = value || fallbackRelative;
  if (!configured) return '';

  if (path.isAbsolute(configured)) return configured;

  const repoResolved = path.resolve(repoRoot, configured);
  if (!app.isPackaged && !isInsideAsar(repoResolved)) return repoResolved;

  return path.resolve(getRuntimeRoot(), configured);
}

function getIntegrationConfig() {
  const repoRoot = getAppRoot();
  const configPath = getLocalConfigPath(repoRoot);
  const defaultConfig = readJsonFile(getDefaultConfigPath(repoRoot));
  const localConfig = readJsonFile(configPath);

  const notionPort = Number(getConfigValue(localConfig, defaultConfig, ['notion', 'port'], 8000));
  const notionAppMode = getConfigValue(localConfig, defaultConfig, ['notion', 'appMode'], 'standard');
  const notionPersistThreads = getConfigValue(localConfig, defaultConfig, ['notion', 'persistThreads'], false);
  const notionGenerateTitles = getConfigValue(localConfig, defaultConfig, ['notion', 'generateTitles'], false);
  const notionSaveThreadOperations = getConfigValue(localConfig, defaultConfig, ['notion', 'saveThreadOperations'], false);
  const notionSetUnreadState = getConfigValue(localConfig, defaultConfig, ['notion', 'setUnreadState'], false);
  const notionDeleteEphemeralThreads = getConfigValue(localConfig, defaultConfig, ['notion', 'deleteEphemeralThreads'], true);
  const councilBackendPort = Number(getConfigValue(localConfig, defaultConfig, ['council', 'backendPort'], 8001));
  const councilFrontendPort = Number(getConfigValue(localConfig, defaultConfig, ['council', 'frontendPort'], 5173));
  const providerUrlPath = getConfigValue(localConfig, defaultConfig, ['provider', 'urlPath'], '/v1');
  const providerApplyDefaultCouncil = getConfigValue(localConfig, defaultConfig, ['provider', 'applyDefaultCouncil'], false);
  const providerEnabledKey = getConfigValue(localConfig, defaultConfig, ['provider', 'enabledKey'], 'custom');
  const providerName = getConfigValue(localConfig, defaultConfig, ['provider', 'name'], 'Notion2API');
  const notionRoot = resolveRuntimePath(repoRoot, getConfigValue(localConfig, defaultConfig, ['notion', 'localRoot'], ''), 'vendor\\notion2api');
  const councilRoot = resolveRuntimePath(repoRoot, getConfigValue(localConfig, defaultConfig, ['council', 'localRoot'], ''), 'vendor\\the-ai-counsel');
  const settingsMode = getConfigValue(localConfig, defaultConfig, ['council', 'settingsMode'], 'auto');
  const verifyProvider = getConfigValue(localConfig, defaultConfig, ['council', 'verifyProvider'], true);
  const askSmokeTest = getConfigValue(localConfig, defaultConfig, ['council', 'askSmokeTest'], true);
  const clearUiStorageOnProviderDrift = getConfigValue(localConfig, defaultConfig, ['council', 'clearUiStorageOnProviderDrift'], true);
  const councilModels = getConfigValue(localConfig, defaultConfig, ['provider', 'councilModels'], ['custom:gpt-5.5']);
  const chairmanModel = getConfigValue(localConfig, defaultConfig, ['provider', 'chairmanModel'], 'custom:claude-opus4.7');
  const logsDir = getLogsDir();
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
    settingsMode,
    verifyProvider,
    askSmokeTest,
    clearUiStorageOnProviderDrift,
    notionAppMode,
    notionPersistThreads,
    notionGenerateTitles,
    notionSaveThreadOperations,
    notionSetUnreadState,
    notionDeleteEphemeralThreads,
    providerApplyDefaultCouncil,
    providerUrlPath,
    councilModels,
    chairmanModel,
  };
}

function getEditableLocalConfig() {
  const current = getIntegrationConfig();
  return {
    configPath: current.configPath,
    values: {
      notionLocalRoot: current.notionRoot,
      notionPort: current.notionPort,
      notionAppMode: current.notionAppMode,
      notionPersistThreads: current.notionPersistThreads,
      notionGenerateTitles: current.notionGenerateTitles,
      notionSaveThreadOperations: current.notionSaveThreadOperations,
      notionSetUnreadState: current.notionSetUnreadState,
      notionDeleteEphemeralThreads: current.notionDeleteEphemeralThreads,
      providerApplyDefaultCouncil: current.providerApplyDefaultCouncil,
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
      appMode: values.notionAppMode || current.notionAppMode,
      persistThreads: Boolean(values.notionPersistThreads),
      generateTitles: Boolean(values.notionGenerateTitles),
      saveThreadOperations: Boolean(values.notionSaveThreadOperations),
      setUnreadState: Boolean(values.notionSetUnreadState),
      deleteEphemeralThreads: Boolean(values.notionDeleteEphemeralThreads),
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
      applyDefaultCouncil: Boolean(values.providerApplyDefaultCouncil),
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
