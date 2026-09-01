# Changelog

All notable changes to the Livebuy Flutter SDK (distributed via this mirror repository) will be
documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Distribution.** The SDK ships as three source packages (`livebuy_flutter` /
> `livebuy_flutter_ui` / `livebuy_flutter_reference_ui`) as three subdirectories of this single git
> repository (`https://github.com/ariesweng/livebuy-flutter-sdk.git`), consumed via pub's `git`
> dependency `path:` mechanism. The published tag's version is read from each package's
> `pubspec.yaml` `version:` field at release time; the channel itself is version-agnostic — the
> entries below will be populated once the first release is cut.

## [Unreleased]

### Added

- Initial mirror repository structure: three subdirectories (`livebuy_flutter` /
  `livebuy_flutter_ui` / `livebuy_flutter_reference_ui`), each synced verbatim from the monorepo's
  `flutter/` / `flutter-ui/` / `flutter-reference-ui/` at release time.
