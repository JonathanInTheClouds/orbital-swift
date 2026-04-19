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
- **Live Activities** — Server health metrics surfaced on the Lock Screen and Dynamic Island via ActivityKit
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

## Linux Test Lab

Orbital includes a local Compose-based SSH lab for Linux distro regression checks. The lab stands up disposable Ubuntu, Debian, Fedora, and Alpine targets that Orbital can connect to like normal servers.

Start the lab:

```bash
./Scripts/lab-up
```

Run smoke checks against the live targets:

```bash
./Scripts/lab-smoke
./Scripts/lab-smoke --verbose
```

Run live simulator UI automation against the lab:

```bash
./Scripts/ui-test-lab ubuntu
./Scripts/ui-test-lab alpine
./Scripts/ui-test-lab all
```

Run the whole lab flow in one command:

```bash
./Scripts/lab-e2e
LAB_TEARDOWN=always ./Scripts/lab-e2e alpine
```

Tear it down:

```bash
./Scripts/lab-down
```

The smoke script verifies Orbital's current Linux assumptions end-to-end over SSH: `uname -s`, the Linux metrics command, and presence of `CPU`, `LOAD`, `UPTIME`, `MEM`, and `DISK` tokens in the payload.

> **Note:** The lab is for Linux coverage only. Containers are useful for shell and parser compatibility, but they are not a substitute for a real macOS target or a VM when validating Darwin-specific behavior.

---

## Architecture

Orbital follows a layered architecture built around SwiftUI, SwiftData, and a small set of shared environment services.

```
Models       — SwiftData entities (Server, MetricSnapshot, Script, ScriptRun)
Services     — SSH session management, libssh transport, command pooling, metrics polling, Keychain, biometrics, Live Activity coordination
Views        — SwiftUI screens organized by feature (Servers, Terminals, Containers, Settings, Keys)
Utilities    — Shared helpers for key encoding, container shell execution, and UI preference storage
Resources    — xterm.js web terminal assets (HTML, JS, CSS)
Extensions   — OrbitalLiveActivityExtension (Lock Screen / Dynamic Island widgets)
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
│   ├── BiometricService.swift
│   ├── LocalNetworkAuthorizationRequester.swift
│   └── LiveActivities/   # ActivityKit coordinator and support for server health Live Activities
├── Views/
│   ├── RootTabView.swift
│   ├── Servers/      # server list, editor, details, metrics, per-server containers
│   ├── Terminals/    # session list, new session flow, terminal renderer
│   ├── Containers/   # global container list and detail actions
│   ├── Settings/     # known hosts, credential vault, SSH key settings
│   └── Keys/         # deploy-key authorization flow
├── Utilities/
│   ├── CardStylePreferenceStore.swift
│   ├── ContainerRuntimeShell.swift
│   └── SSHPublicKeyEncoder.swift
└── Resources/
    ├── terminal.html
    ├── xterm.mjs
    ├── addon-fit.mjs
    └── xterm.css
OrbitalLiveActivityExtension/   # Widget extension for Lock Screen / Dynamic Island
SharedLiveActivity/              # Shared ActivityKit attributes between app and extension
```

---

## License

*License TBD.*
