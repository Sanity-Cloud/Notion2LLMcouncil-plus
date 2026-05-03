# Notion2Council Development Guide

## Architecture

The application is split into two main parts:
1. **Electron Shell**: Provides the desktop interface, tray menu, and global hotkeys.
2. **PowerShell Orchestrator**: Manages the lifecycle of backend services (Notion2API and Council Plus).

### Electron Structure
- `electron/main.js`: Core entry point and orchestrator.
- `electron/lib/`: Internal modules for logging, configuration, service launching, and utilities.
- `electron/windows/`: Management of the main application window and hotkey settings UI.

### PowerShell Structure
- `scripts/launch.ps1`: Main entry point for starting/stopping services.
- `scripts/lib/`: Modularized PowerShell modules (`.psm1`) for specific concerns like process management, configuration, and networking.

## Security
- **Sandboxing**: All Electron windows run with `sandbox: true` enabled.
- **Context Isolation**: Node.js integration is disabled in the renderer; communication happens via `preload.js` and IPC.
- **CSP**: A Content Security Policy is enforced on internal pages.

## Configuration
- `config/default.json`: Shared default settings.
- `config/local.json`: Environment-specific overrides (ignored by git).
- `config/schema.json`: JSON schema for configuration validation.
- `config/local.example.json`: Template for creating your own `local.json`.

## Building and Releasing
Use the following commands:
- `npm run start`: Start the application in development mode.
- `npm run electron:build`: Build all release targets (Portable EXE, ZIP, MSI).
- `npm run release:local`: Package the source and runtime bundle.
