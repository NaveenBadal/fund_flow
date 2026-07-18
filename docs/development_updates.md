# GitHub development updates

> Operational history only. Current product and interface direction is locked
> in `docs/design_system.md` v2.0.

Fund Flow development builds use the version sequence
`0.0.1-dev.<github-run-number>`. The installed Android application ID is
`com.naveen.expense_manager.expense_manager.dev`, so it remains separate from a
future production installation.

## One-time signing setup

Generate one permanent development key locally. Never commit this file or its
passwords.

```sh
keytool -genkeypair \
  -keystore fund-flow-development.jks \
  -alias fund-flow-development \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000
```

Encode the keystore:

```sh
base64 < fund-flow-development.jks | tr -d '\n'
```

Add these GitHub repository Actions secrets:

- `DEV_KEYSTORE_BASE64`: encoded keystore contents
- `DEV_KEYSTORE_PASSWORD`: keystore password
- `DEV_KEY_ALIAS`: `fund-flow-development`
- `DEV_KEY_PASSWORD`: key password

Keep an offline backup of the keystore and passwords. Losing this key means
existing development installations cannot receive another in-place update.

## Publishing

Every push to `main`, or a manual run of `Publish Development Update`, performs
analysis and tests, creates a signed development APK, generates `update.json`
with its SHA-256 digest, and publishes both files in a GitHub prerelease.

The first build must be installed manually. Later builds can be installed from
Settings → Development channel or from the update banner on Today.

Android requires the user to enable “Install unknown apps” for Fund Flow Dev
and approve each installation. The operating system also rejects an APK whose
application ID or signing certificate does not match the installed build.

## Repository visibility

The app reads the unauthenticated GitHub Releases API. The repository and its
release assets must therefore be public. Do not embed a GitHub access token in
the app. For a private source repository, publish APKs to a separate public
binary-release repository or place the update manifest behind an authenticated
service designed for applications.

## Production boundary

GitHub updating is compiled only when the development flavor is built with:

```sh
flutter build apk \
  --release \
  --flavor development \
  --dart-define=ENABLE_GITHUB_UPDATES=true
```

Production builds should use the `production` flavor without that Dart define
and use the app store's update mechanism.
