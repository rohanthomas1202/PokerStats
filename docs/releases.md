# Release log

Trevor - Release & Compliance keeps one row per iOS upload. Triggers and secrets
are documented in the README Releases section.

| Date (America/Chicago) | Tag | Commit | Build number | Path | Notes |
| --- | --- | --- | --- | --- | --- |
| | | | | | |

## Closing a sprint

1. Confirm the sprint-closing commit is on `main` and "CI passed" is green.
2. Tag and push:

```bash
git tag ios-sprint-N <commit-on-main>
git push origin ios-sprint-N
```

3. Watch Actions > iOS release. Record the build number, commit and "What to Test"
   notes in the table above after the run finishes.
4. App Store path (`ios-vX.Y`): same steps with an `ios-v*` tag. CI uploads only;
   the owner submits for review in App Store Connect.
