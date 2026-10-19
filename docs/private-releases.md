# Private security release staging

This flow uses the existing **private** `php-darwin-private` R2 bucket. Bucket
creation and public-access settings are managed outside workflows. Upload sources
once to `uploads/php-X.Y.Z.tar.xz` or `uploads/php-X.Y.Z.tar.gz`; Darwin and Builder
can consume the same upload. The archive's version header must match its filename.

## Stage PHP Builder

Run **Stage private PHP Builder** (`stage-private.yml`) on `main` with:

- `php-version`: a configured minor, for example `8.4`.
- `source-file`: the exact upload filename. May be omitted if exactly one matches.
- `source-sha256`: optional independently supplied checksum.
- `containers`: supported containers to build; defaults to the normal full matrix.

The build ID is `RUN_ID-ATTEMPT`. Everything is stored under
`php-builder/uploads/BUILD_ID/`:

- `inputs/`: immutable source and the installer used by compatibility tests.
- `plan.json`: exact source hash/version, repository revision, php-build revision,
  platforms, SAPI, package and test matrices.
- `packages/`: intermediate SAPI archives and final NTS/ZTS archives, including
  release/debug-symbol variants in both XZ and Zstandard formats.
- `results/` and `logs/`: private build and compatibility-test evidence.
- `ready.json`: signed approval binding every required package and test result.
- `workflow.json`: run/job metadata saved before deletion from GitHub.

PHP sources are read from authenticated R2 and verified again immediately before
each SAPI build. The private definition extracts that local archive directly;
it does not query php.net or fall back to a public PHP source. Normal dependency,
extension and packaging paths remain in use. Each final package is installed and
tested in its distro container, plus matching Ubuntu hosted runners, for both
release and debug-symbol variants. Uploaded bytes are downloaded and verified.

## Feed PHP Ubuntu

In `shivammathur/php-ubuntu`, run **Stage private PHP Ubuntu** with the same
`php-version`, this `builder-build-id`, and the desired Ubuntu `containers`.
Every selected platform must already be present in Builder's signed approval.
Ubuntu verifies that approval, downloads the exact matching private packages and
installer, and produces its own signed staging set under
`php-ubuntu/builds/RUN_ID-ATTEMPT/`. Public Builder release assets are not needed.

## Publish after announcement

Run **Release PHP Builder from private R2** (`release-private.yml`) on `main` with
`php-version`, `build-id`, exact `release-version`, and the official
`source-sha256` for the staged compression format. It validates the signature,
complete test matrix, package hashes and the exact announced php.net source, then
publishes the tested archives and installer through the normal release script.
It does not compile PHP. PHP Ubuntu has a separate equivalent promotion workflow.

Promotion rejects branch staging and changed candidates. Start a new staging run
when source bytes change. Publication shares a lock with normal publishing and
checks actual archive versions to prevent older queued builds replacing a newer
security release. No public release is created during staging.

## Privacy and operation

There are no Actions artifact uploads. Child output and step summaries, including failures, go to
private R2 logs. Child environment/path/state/output files stay private; only the
plan publishes its validated job matrices. GitHub still shows run existence, job names, timing, status and
dispatch inputs while the run exists; never put credentials in inputs. This does
not make a public Actions run secret. Runner/bootstrap failures or forced kills
can prevent log upload. Downloaded inputs and captured logs use the job temporary
directory, removed after a successful log transfer. Compilation and installation
also write into `/tmp` and system paths, so use disposable containers/runners that
are destroyed when jobs end.

Once these workflows are merged to the default branch, `cleanup-private.yml`
archives completed staging runs and deletes them automatically. It can also be
dispatched with `build-id` to retry cleanup. R2 objects remain available after run
deletion; downstream builds and publication use R2 evidence exclusively.
Use **Re-run all jobs** before deletion, or start a fresh run after deletion;
failed-job-only reruns cannot reuse an earlier attempt's immutable plan.

Required repository secrets:

- `PRIVATE_R2_ENDPOINT`, `PRIVATE_R2_ACCESS_KEY_ID`, `PRIVATE_R2_SECRET_ACCESS_KEY`:
  credentials scoped to the existing private bucket.
- `PRIVATE_RELEASE_SIGNING_KEY`: 32 random bytes encoded as 64 lowercase hex
  characters, retained for the lifetime of staged releases.

PHP Ubuntu additionally receives Builder's signing key as
`PHP_BUILDER_PRIVATE_SIGNING_KEY` to verify the handoff. Ordinary public publishing
credentials remain separate. Never commit credentials or upload them as artifacts.

The shared Python protocol files are mirrored in both repositories; changes to
the storage/approval contract must be applied and tested in both. Run
`python3 -m unittest discover -s tests/private -v` and `actionlint` locally.

## Branch trial before integration

For a development trial, set the repository Actions variable
`PRIVATE_TEST_PHP_VERSION` to the minor and push a commit containing
`[private-stage]` to `feature/private-r2-releases`. Ordinary pushes do not stage
private sources. Source archives are selected from authenticated R2; never put
private source contents, candidate filenames or hashes in the commit. Ubuntu
also needs `PRIVATE_TEST_BUILDER_BUILD_ID` set to the signed Builder run-attempt.
The full configured matrix is used. All intermediate handoffs use private R2,
including SAPI archives, final packages, and the Builder-to-Ubuntu handoff.
No GitHub Actions artifacts or Actions caches are used by private staging.

Until the cleanup workflow is on the default branch, archive and delete completed
trial runs with the repository's private cleanup script from a trusted local
checkout. Verify R2 evidence before deleting the run. Branch trial approvals are
for validation only and remain ineligible for production promotion.
