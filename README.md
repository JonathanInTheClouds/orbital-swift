# Orbital

**SSH client and server manager for iPhone.**

Orbital lets you manage remote Linux and macOS servers from your iPhone. It combines saved server profiles, live metrics dashboards, interactive terminal sessions, container controls, and secure credential storage in a single SwiftUI app.

![Platform](https://img.shields.io/badge/platform-iOS%2026.4%2B-blue) ![Swift](https://img.shields.io/badge/swift-5.0-orange) ![Xcode](https://img.shields.io/badge/xcode-16%2B-blue)

---

## Features

- **Saved Server Profiles** — Add and edit Linux or macOS hosts with passwords, pasted private keys, or stored key references
- **SSH Terminal** — Full interactive shell sessions rendered via xterm.js with Ctrl, Tab, and arrow key support
- **Server Monitoring** — Live CPU, memory, disk, network, uptime, and load metrics collected over SSH
- **Container Management** — View, inspect, start, stop, restart, pause, and remove Docker or Podman containers
- **SSH Key Management** — Generate ED25519 keys, import existing private keys, and deploy public keys to servers
- **Credential Vault** — Passwords and SSH private keys stored in the iOS Keychain, with biometric unlock support for the vault
- **Known Hosts** — Host key fingerprint tracking, mismatch detection, and manual clearing from Settings
- **Connection Reuse** — Shared SSH transports for terminal sessions, commands, and metrics polling
- **Script Models** — `Script` and `ScriptRun` persistence models are present for future automation work, but there is no script UI yet

---

## Screenshots

*Screenshots coming soon.*

---

## Requirements

| Requirement | Version |
|---|---|
| Xcode | 16+ |
| iOS Deployment Target | 26.4+ |
| macOS (build machine) | 14.4+ |

---

## Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/JonathanInTheClouds/Orbital.git
   cd Orbital
   ```

2. Open the project in Xcode:
   ```bash
   open Orbital.xcodeproj
   ```

3. Select a simulator or connected iPhone as the run destination.

4. Build and run with `Cmd+R`.

> **Note:** A physical device is recommended for testing SSH connections to real servers.

## Running Tests

Run the unit test target locally with:

```bash
./Scripts/test.sh
```

GitHub Actions also runs the same unit test command on every pull request and on pushes to `main`.

---

## Architecture

Orbital follows a layered architecture built around SwiftUI, SwiftData, and a small set of shared environment services.

```
Models       — SwiftData entities (Server, MetricSnapshot, Script, ScriptRun)
Services     — SSH session management, libssh transport, command pooling, metrics polling, Keychain, biometrics
Views        — SwiftUI screens organized by feature (Servers, Terminals, Containers, Settings, Keys)
Utilities    — Shared helpers for key encoding and UI preference storage
Resources    — xterm.js web terminal assets (HTML, JS, CSS)
```

---

## Technology Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI |
| Persistence | SwiftData |
| SSH | libssh (vendored via LibsshVendor) |
| Terminal rendering | xterm.js 6.0.0 (WKWebView) |
| Security | iOS Keychain + LocalAuthentication |
| Key generation | Swift Crypto (ED25519) |
| Concurrency | Swift async/await, Actors |
| Logging | OSLog |

---

## Project Structure

```
Orbital/
├── OrbitalApp.swift
├── Models/
│   ├── Server.swift
│   ├── MetricSnapshot.swift
│   ├── Script.swift
│   └── ScriptRun.swift
├── Services/
│   ├── SSHService.swift
│   ├── LibsshBridge.swift
│   ├── SSHCommandPool.swift
│   ├── MetricsPollingService.swift
│   ├── KeychainService.swift
│   └── BiometricService.swift
├── Views/
│   ├── RootTabView.swift
│   ├── Servers/      # server list, editor, details, metrics, per-server containers
│   ├── Terminals/    # session list, new session flow, terminal renderer
│   ├── Containers/   # global container list and detail actions
│   ├── Settings/     # known hosts, credential vault, SSH key settings
│   └── Keys/         # deploy-key authorization flow
├── Utilities/
│   ├── CardStylePreferenceStore.swift
│   └── SSHPublicKeyEncoder.swift
└── Resources/
    ├── terminal.html
    ├── xterm.mjs
    ├── addon-fit.mjs
    └── xterm.css
```

---

## License

*License TBD.*
