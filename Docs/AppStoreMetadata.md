# App Store Metadata Draft

This is a working draft for App Store Connect. Review every field before submission.

## App Information

- Name: Orbital
- Subtitle: SSH server manager
- Bundle ID: `dev.jonathanintheclouds.Orbital`
- Category: Developer Tools
- Secondary Category: Utilities
- Age Rating: 4+
- Copyright: 2026 Jonathan Dowdell

## Promotional Text

Manage SSH servers, terminals, metrics, containers, keys, and credentials from your iPhone.

## Description

Orbital is an SSH client and server manager for iPhone. It brings saved server profiles, interactive terminal sessions, live server metrics, container controls, SSH key management, known-host verification, and a local credential vault into one native SwiftUI app.

Connect to Linux or macOS hosts over SSH, open terminal sessions, monitor CPU, memory, disk, network, uptime, and load, and inspect Docker or Podman containers from the same server profile. Orbital stores passwords and private keys in the iOS Keychain, supports biometric unlock for reviewing vault entries, and tracks host key fingerprints to help detect unexpected server identity changes.

For server monitoring, Orbital can poll metrics over SSH and surface selected server health through Live Activities on the Lock Screen and Dynamic Island.

Key features:

- Saved SSH server profiles
- Interactive xterm.js terminal sessions
- CPU, memory, disk, network, uptime, and load metrics
- Docker and Podman container views and actions
- ED25519 key generation, import, and deploy workflows
- iOS Keychain credential storage
- Biometric unlock for Credential Vault review
- Known-host fingerprint tracking and mismatch detection
- Live Activities for server health

Orbital connects only to servers you configure. It does not include ads, tracking, analytics, or an account service.

## Keywords

ssh,terminal,server,linux,devops,docker,podman,sysadmin,monitoring,keychain

## Support URL

TODO: Add support URL.

Suggested options:

- A public support page for Orbital
- A GitHub issues URL if the repository becomes public
- A dedicated contact page

## Privacy Policy URL

TODO: Add privacy policy URL.

Draft policy: `Docs/PrivacyPolicy.md`

The published policy should match the App Privacy notes below and explain that server profiles, credentials, and metrics are stored locally unless the user connects to their own servers.

## Screenshot Checklist

Prepare screenshots for all required App Store device sizes.

Recommended scenes:

- Servers list with populated status cards
- Server detail or metrics dashboard
- Terminal session
- Container list or container detail
- Credential Vault locked and unlocked states
- Known Hosts settings
- Live Activity or Dynamic Island preview, if practical

Avoid screenshots that reveal real hostnames, IP addresses, usernames, private keys, passwords, or production metrics.

## App Privacy Draft

Based on the current codebase, Orbital does not appear to collect data from users for the developer. It stores app data locally on the device and connects to user-configured servers.

Use these answers as a draft only. Verify against the final build, privacy policy, and any future services before submission.

### Tracking

- Does this app use data to track users? No

Rationale: No ad SDK, analytics SDK, tracking SDK, or third-party tracking integration is present.

### Data Collection

Recommended answer:

- Data collected from this app: None

Rationale: Server profiles, credentials, known-host fingerprints, metric snapshots, and preferences are stored locally using SwiftData, Keychain, and UserDefaults. The app connects to servers chosen by the user, but the developer does not receive that data through an Orbital service.

### Data Stored Locally

Explain in the privacy policy that Orbital stores the following on device:

- Server profile names, hosts, ports, usernames, tags, notes, and preferences
- Passwords and private keys in the iOS Keychain
- Known-host fingerprints in the iOS Keychain
- Server metric snapshots in the app's local storage
- Live Activity preference state in UserDefaults

### Permissions And Purpose Strings

Current permission use:

- Local Network: used to prompt local network authorization and connect to nearby/user-configured servers.
- Face ID: used to unlock the Credential Vault for reviewing saved credential entries.
- Pasteboard: used only when the user taps paste/import/copy actions for SSH keys.

### Encryption Export Compliance

Orbital uses SSH/libssh encryption. Complete App Store Connect's export compliance questionnaire before setting `ITSAppUsesNonExemptEncryption` in `Orbital-Info.plist`.
