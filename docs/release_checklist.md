# Release Checklist

- Update `pubspec.yaml` version and Android build number.
- Update `version.json` version, message, and URL.
- Build the release APK.
- Create a GitHub Release tag matching the version, for example `v1.3.4`.
- Upload the APK to the GitHub Release.
- Confirm `version.json` is reachable from the URL used by the app.
- Open an installed old app version and verify the update prompt appears.
- Verify the update link opens the GitHub latest release page.
