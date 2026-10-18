# Release log

Trevor - Release & Compliance keeps one row per iOS upload. Triggers and secrets
are documented in the README Releases section.

| Date (America/Chicago) | Tag | Commit | Build number | Path | Notes |
| --- | --- | --- | --- | --- | --- |
| | | | | | |

## Closing a sprint

1. Confirm the owner setup in the README Releases section is done (environments,
   their branch and tag limits, the `app-store` reviewer, then secrets, then
   `APP_STORE_UPLOAD_ENABLED`). Do not push a release tag before it is.
2. Confirm the sprint-closing commit is on `main` and "CI passed" is green.
3. Tag and push:

```bash
git tag ios-sprint-N <commit-on-main>
git push origin ios-sprint-N
```

4. Watch Actions > iOS release. Record the build number, commit and "What to Test"
   notes in the table above after the run finishes.
5. App Store path (`ios-vX.Y`): same steps with an `ios-v*` tag. CI uploads only;
   the owner submits for review in App Store Connect.
