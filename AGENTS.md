# Repository instructions

## Before committing or updating a pull request

- Run `./Tools/regenerate-projects.sh` after the final file additions, removals,
  or renames. Always regenerate **both** Xcode projects, even for tooling-only
  changes: both generators include the entire `Tools/` directory, including tests.
- Review and stage generated changes in `EarStudioCompanion.xcodeproj` and
  `EarStudioiOS.xcodeproj` alongside the source changes. Do not hand-edit generated
  project files or schemes; edit the generators or `.xcconfig` files instead.
- Run `./Tools/regenerate-projects.sh --check` after staging and before committing.
  It regenerates both projects and fails if either differs from the index.
- Run the relevant tests described in `CONTRIBUTING.md`. Passing tooling tests
  alone does not cover CI's generated-project consistency checks.
