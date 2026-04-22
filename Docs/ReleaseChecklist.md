# Release Checklist

Use this checklist before the first TestFlight or App Store submission.

## App Store Setup

- Choose the final app bundle identifier and update the app, test, and extension targets.
- Confirm Apple Developer Team signing works for the app and Live Activity extension.
- Decide export compliance for SSH/libssh encryption use and set `ITSAppUsesNonExemptEncryption` accordingly.
- Prepare App Store name, subtitle, description, keywords, support URL, privacy policy URL, and screenshots.

## Build Validation

- Run `./Scripts/test.sh`.
- Run `./Scripts/lab-e2e all` with the local SSH lab.
- Archive a Release build in Xcode and validate the archive.
- Install a TestFlight build on a physical device and test at least one real SSH target.

## Product Checks

- Verify credential creation, editing, deletion, and vault unlock behavior.
- Verify known-host first trust and mismatch handling.
- Verify terminal input, resize, reconnect, and close flows.
- Verify metrics polling, container actions, and Live Activity lifecycle.

## Legal And Metadata

- Select and add the project license before public source release.
- Review `THIRD_PARTY_NOTICES.md` against the final dependency bundle.
- Confirm privacy manifest and App Store privacy answers match actual app behavior.
