# Release log

Trevor - Release & Compliance keeps one row per iOS upload. Triggers and secrets
are documented in the README Releases section.

| Date (America/Chicago) | Tag | Commit | Build number | Path | Notes |
| --- | --- | --- | --- | --- | --- |
| | | | | | |

## Closing a sprint

1. Confirm every step in the README Owner setup is done, through the dry run.
   Do not push a release tag before it is.
2. Confirm the sprint-closing commit is on `main` and "CI passed" is green.
3. Tag and push:

```bash
git tag ios-sprint-N <commit-on-main>
git push origin ios-sprint-N
```

4. Watch Actions > iOS release. Record the build number, commit and "What to Test"
   notes in the table above after the run finishes.
5. App Store path (`ios-vX.Y`): same steps with an `ios-v*` tag. CI uploads only;
   the owner submits for review in App Store Connect. The `release` lane builds
   with `APP_STORE_SUBMISSION`, so the build fails to compile while
   `AppLinks.supportEmail` is still `[CONTACT_EMAIL]`. Fill in the address
   (#76) first; the gate then stops firing. TestFlight builds are unaffected.
