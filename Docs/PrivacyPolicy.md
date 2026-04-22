# Orbital Privacy Policy

Effective date: TODO

Orbital is an SSH client and server manager for iPhone. This policy explains how Orbital handles information when you use the app.

## Summary

Orbital is designed as a local-first app. The app does not include ads, analytics SDKs, tracking SDKs, or an Orbital account service. Orbital does not send your server profiles, credentials, terminal sessions, metrics, or container information to the developer.

## Information Stored On Your Device

Orbital stores app data locally on your device, including:

- Server profile names, hosts, ports, usernames, tags, notes, and preferences
- Passwords and private keys stored in the iOS Keychain
- Known-host fingerprints stored in the iOS Keychain
- Server metric snapshots stored in the app's local database
- Live Activity preference state stored in app preferences

This information is used to provide SSH connections, saved server management, terminal sessions, metrics dashboards, container controls, known-host verification, credential management, and Live Activities.

## Credentials

Orbital stores passwords and private keys in the iOS Keychain. The Credential Vault can be unlocked with Face ID or Touch ID, when available, so you can review and manage saved credential entries.

Orbital uses saved credentials only to connect to servers you configure or to perform actions you request.

## Server Connections

Orbital connects to servers you configure using SSH. When you connect to a server, information such as commands, terminal input, server metrics, container information, and authentication material is transmitted between your device and that server as needed to provide the requested functionality.

The developer does not operate a relay service for these connections and does not receive this server data through Orbital.

## Local Network Access

Orbital may request local network permission so it can connect to user-configured servers on your local network and trigger iOS local network authorization when needed.

## Pasteboard

Orbital accesses the pasteboard only when you use actions such as paste, import, or copy for SSH keys.

## Live Activities

Orbital can show selected server health information in Live Activities on the Lock Screen and Dynamic Island. Live Activity content is generated from metrics collected by the app from servers you configure.

## Data Collection

Orbital does not collect personal data for the developer. Orbital does not use third-party analytics, advertising, or tracking services.

## Data Sharing

Orbital does not sell or share your data with advertisers or data brokers.

Data may be sent to servers you configure when you connect to them over SSH or perform server actions. Those servers are controlled by you or by the parties you choose to connect to.

## Data Retention And Deletion

Data stored by Orbital remains on your device until you delete it, uninstall the app, or clear it through app features such as deleting server profiles, deleting credentials, or clearing known-host entries.

## Children's Privacy

Orbital is not directed to children and does not knowingly collect personal information from children.

## Changes To This Policy

This policy may be updated as Orbital changes. The effective date above should be updated when material changes are made.

## Contact

TODO: Add support or privacy contact URL/email.
