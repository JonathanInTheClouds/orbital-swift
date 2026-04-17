# Orbital

**SSH client and server manager for iPhone.**

Orbital lets you manage remote Linux and macOS servers from your iPhone — monitor system metrics, control Docker and Podman containers, open interactive terminals, and store credentials securely in the iOS Keychain.

![Platform](https://img.shields.io/badge/platform-iOS%2026.4%2B-blue) ![Swift](https://img.shields.io/badge/swift-5.0-orange) ![Xcode](https://img.shields.io/badge/xcode-16%2B-blue)

---

## Features

- **SSH Terminal** — Full interactive shell sessions rendered via xterm.js with Ctrl, Tab, and arrow key support
- **Server Monitoring** — Real-time CPU, memory, disk, network, and load average metrics with configurable polling intervals
- **Container Management** — View, start, stop, restart, pause, and remove Docker/Podman containers
- **SSH Key Management** — Generate ED25519 keys, import private keys, and deploy public keys to servers
- **Credential Vault** — Passwords and SSH private keys stored securely in the iOS Keychain
- **Known Hosts** — Host key fingerprint tracking and verification
- **Connection Pooling** — Persistent SSH connections shared across terminal sessions and metrics polling
- **Script Runner** — Store and execute reusable shell scripts on remote servers *(coming soon)*

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

---

## Architecture

Orbital follows a layered architecture using SwiftUI + SwiftData with `@Observable` services.

```
Models       — SwiftData entities (Server, MetricSnapshot, Script, ScriptRun)
Services     — SSH session management, metrics polling, Keychain, biometrics
Views        — SwiftUI screens organized by feature (Servers, Terminals, Containers, Settings)
Utilities    — Shared helpers (Keychain encoding, card style preferences)
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
| Security | iOS Keychain (Security framework) |
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
│   ├── Servers/
│   ├── Terminals/
│   ├── Containers/
│   └── Settings/
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
