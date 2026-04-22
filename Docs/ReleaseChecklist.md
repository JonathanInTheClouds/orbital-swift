# Release Checklist

Use this checklist before the first TestFlight or App Store submission.

## App Store Setup

- Choose the final app bundle identifier and update the app, test, and extension targets.
- Confirm Apple Developer Team signing works for the app and Live Activity extension.
- Complete App Store Connect's export compliance questionnaire for SSH/libssh encryption use before setting `ITSAppUsesNonExemptEncryption`.
- Prepare App Store name, subtitle, description, keywords, support URL, privacy policy URL, and screenshots.
- Publish the privacy policy and add its public URL to App Store Connect.

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

- Keep the project license current if the source distribution strategy changes.
- Review `THIRD_PARTY_NOTICES.md` against the final dependency bundle.
- Confirm privacy manifest and App Store privacy answers match actual app behavior.
