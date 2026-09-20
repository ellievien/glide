# Contributing to Glide

Glide is a closed fork of [LocalSend](https://github.com/localsend/localsend), developed by
Neverheard Studio. This document covers day-to-day dev setup; see [NOTICE](NOTICE) for attribution
details and [AGENTS.md](AGENTS.md) for the full repository guide (layout, commands, architecture).

## Getting Started

If you're interested in contributing code to Glide, you'll need to follow these steps:

## Run

Install [fvm](https://fvm.app) and use it to install the Flutter version pinned in [.fvmrc](.fvmrc),
then start the app by typing the following commands:

```shell
cd app
fvm flutter pub get
fvm dart run build_runner build -d
fvm flutter run
```

## Contributing Guidelines

Before you submit a pull request, please ensure that you have followed these guidelines:

- Code should be well-documented and formatted according to the [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style).
- All changes should be covered by tests.
- Commits should be well-written and descriptive, with a clear summary of the changes made and any relevant context.
- Pull requests should target the `main` branch and include a clear summary of the changes made.

## Bug Reports and Feature Requests

If you encounter a bug or have a feature request, please submit an issue to this repository's issue
tracker. Please be sure to provide a clear description of the problem or feature request, along
with any relevant context or steps to reproduce the issue.

## Security Issues

If you discover a security issue in Glide, please do not submit an issue to the public issue
tracker. Instead, please email us directly at
<!-- TODO(Neverheard Studio): replace with a real security contact address --> [hello@neverheard.studio](mailto:hello@neverheard.studio)
so that we can address the issue as quickly and effectively as possible.

## Notes

Useful notes.

### Compile production APK

You will need the signing keys to generate an APK.

Either generate one or use the debug signing options:

```groovy
// File: android/app/build.gradle
buildTypes {
  release {
    signingConfig signingConfigs.debug // using debug signing
  }
}
```

### Bump Flutter

Suppose we want to update flutter to `3.41.9`:

1. Update flutter from fvm: `fvm use 3.41.9`
2. Update flutter from submodule:
   1. `git submodule update --init`
   2. `cd support/submodules/flutter`
   3. `git fetch`
   4. `git checkout 3.41.9`
   5. `cd ../../..`
   6. `git add support/submodules/flutter`
3. Update flutter constraints:
   1. In CI: `.github/workflows/ci.yml`
   2. In pubspec: `pubspec.yaml`

### Release

Make sure to set up the self-hosted runner to compile arm64 linux binaries.

To set up the runner, follow the following instructions:

Install Flutter

```bash
sudo apt install git
git clone https://github.com/flutter/flutter.git $HOME/flutter
nano $HOME/.bashrc
```

Add the following to the end of the file:

```bash
export PATH="$PATH:$HOME/flutter/bin"
```

Restart the terminal.

```bash
flutter doctor
```

Next, follow the instructions to set up the GitHub runner.

Start the "Release Draft" workflow from this repository's Actions tab.

Finally, compile binaries not yet supported by the pipeline.
