# Third-Party Notices

Orbital includes or links against the following third-party components. Review this file before each release to ensure it matches the shipped app bundle.

## libssh

- Source: `Vendor/libssh-0.12.0`
- Binary framework: `Vendor/Build/LibsshVendor.xcframework`
- License: LGPL-2.1, with additional license material in `Vendor/libssh-0.12.0/BSD` and related upstream files.
- Full license text: `Vendor/libssh-0.12.0/COPYING`

## Mbed TLS

- Source: `Vendor/mbedtls-3.6.5`
- License: Apache-2.0 OR GPL-2.0-or-later
- Full license text: `Vendor/mbedtls-3.6.5/LICENSE`

## xterm.js

- Runtime assets: `Orbital/Resources/xterm.mjs`, `Orbital/Resources/addon-fit.mjs`, `Orbital/Resources/xterm.css`
- Upstream source snapshot: `xterm.js-6.0.0`
- License: MIT
- Full license text: `xterm.js-6.0.0/LICENSE`

## Swift Package Dependencies

The Xcode package resolution file currently pins these Apple Swift packages:

- swift-asn1
- swift-atomics
- swift-collections
- swift-crypto
- swift-nio
- swift-nio-ssh
- swift-system

Pinned versions and revisions are recorded in `Orbital.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
