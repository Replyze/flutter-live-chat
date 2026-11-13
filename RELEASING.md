# Releasing replyze_flutter

A tag `vX.Y.Z` runs [`.github/workflows/release.yml`](.github/workflows/release.yml). It checks that the tag matches `pubspec.yaml` and that `CHANGELOG.md` has a dated section for that version, checks the formatting, runs `flutter analyze`, the tests and `dart pub publish --dry-run`, creates the GitHub release with the CHANGELOG section as notes, and then publishes to pub.dev with pub.dev's automated publishing (GitHub's OIDC token, no secret).

Until pub.dev is set up, the publish job is skipped (the run shows a notice) and the GitHub release is still created.

## One-time setup (the owner)

1. **A verified publisher (recommended).** On pub.dev, create the publisher `replyze.chat` (pub.dev → Create publisher; you verify the domain with a DNS TXT record in Google Search Console). Packages under a verified publisher show the domain instead of a person's email.
2. **The first publish is manual.** pub.dev's automated publishing can only be enabled for a package that already exists. From a clean checkout of the tagged commit, with the Flutter SDK and a Google account that can publish for Replyze:
   ```sh
   flutter pub get
   dart pub publish --dry-run
   dart pub publish
   ```
   Then, if you made a publisher: pub.dev → `replyze_flutter` → Admin → Transfer to publisher `replyze.chat`.
3. **Automated publishing.** pub.dev → `replyze_flutter` → Admin → Automated publishing → Enable publishing from GitHub Actions, with repository `Replyze/flutter-live-chat` and tag pattern `v{{version}}`. Also tick "Require GitHub Actions environment" with the environment `pub.dev`, and create that environment in GitHub (Settings → Environments → New environment `pub.dev`; you can add required reviewers there).
4. **Switch the workflow on.** Add the repository variable `PUB_DEV_PUBLISHING` = `true` (Settings → Secrets and variables → Actions → Variables).

The publish job runs when `PUB_DEV_PUBLISHING` is `true`. It uses the `dart-lang/setup-dart` action to get the OIDC token for pub.dev, then Flutter's `dart pub publish --force`. (The reusable workflow `dart-lang/setup-dart/.github/workflows/publish.yml` is not used: it installs only Dart, which can't resolve a Flutter package.) pub.dev never accepts the same version twice, so a failed publish is retried by re-running the job, not by re-tagging.

## Each release

1. On a branch, set `version:` in `pubspec.yaml`.
2. In `CHANGELOG.md`, put the changes under `## [0.2.0] - YYYY-MM-DD` (today's date) and add the link at the bottom: `[0.2.0]: https://github.com/Replyze/flutter-live-chat/releases/tag/v0.2.0`. Check it: `dart tool/changelog_notes.dart 0.2.0 --release`.
3. Open a pull request, wait for CI (it runs `dart pub publish --dry-run` and pana), merge to `main`.
4. Tag the merge commit on `main` as Replyze, never with a personal name or email:
   ```sh
   git checkout main && git pull
   git -c user.name="Replyze" -c user.email="dev@replyze.chat" tag -a v0.2.0 -m "v0.2.0"
   git push origin v0.2.0
   ```
5. Watch the run: `gh run list -R Replyze/flutter-live-chat --workflow release.yml`. Then check [pub.dev/packages/replyze_flutter](https://pub.dev/packages/replyze_flutter) and the [releases page](https://github.com/Replyze/flutter-live-chat/releases).

A version with a hyphen (`0.2.0-beta.1`) is a pre-release on pub.dev and on GitHub.

If the run fails before publishing, fix the problem on `main`, delete the tag (`git push origin :refs/tags/v0.2.0` and `git tag -d v0.2.0`) and tag again. If it fails after publishing, release the fix as the next patch version.

## After the first pub.dev release

In `README.md`, make `flutter pub add replyze_flutter` the install command and keep the git dependency as the way to try unreleased changes.
