# Runbook: branch protection, ios-* tag ruleset and Dependabot

This runbook is for the owner. It covers the settings in #25 (branch protection on `main`, Dependabot alerts and security updates) and README Owner setup step 4 (the `ios-*` tag ruleset, for #100 and #31). No bot can change these settings: the Cursor GitHub app has `administration: read` only.

Two ruleset files hold the agreed settings:

- `.github/rulesets/main.json`: targets the default branch. Requires a pull request before merging, with 0 required approvals and no code owner review. Dismisses stale approvals when new commits are pushed and requires approval of the most recent push (#217). Requires the status check `CI passed` (the `gate` job in `.github/workflows/ci.yml`, from GitHub Actions) and nothing else. Blocks force pushes and deletion. The Repository admin role is on the bypass list, mode Always.
- `.github/rulesets/ios-tags.json`: targets `refs/tags/ios-*`. Restricts creations, updates and deletions. The Repository admin role is on the bypass list, mode Always.

Require approval of the most recent reviewable push means the latest push to a PR must be approved by someone other than the person who pushed it, even with 0 required approvals. The bots push as `rohanthomas1202`, so their PRs need a GitHub approval from `Agent-Kate-QA` or `Agent-Jules-UX`, and Dependabot PRs need one too. With stale approvals dismissed, a push after an approval needs a new one. Logins with the admin role, including the bots, can still merge past it through the bypass.

The CI job **Repo settings files** fails if `main.json` stops requiring the gate job's name, so renaming the gate breaks CI instead of blocking every merge.

## Steps, in order

1. **Dependabot alerts.** Settings > Advanced Security (called Code security on some accounts) > Dependabot alerts > Enable.
2. **Dependabot security updates.** Same page > Dependabot security updates > Enable. GitHub needs alerts on first.
3. **Download the two files** from `main`: open `.github/rulesets/main.json` and `.github/rulesets/ios-tags.json` on GitHub and use Download raw file, or take them from a checkout of `main`.
4. **Import the `main` ruleset.** Settings > Rules > Rulesets > New ruleset > Import a ruleset, pick `main.json`. Before you click Create, check that:
   - Enforcement status is Active and the target is the default branch.
   - Bypass list has Repository admin, set to Always.
   - Require a pull request before merging is on, with Required approvals 0 and Require review from Code Owners off.
   - Dismiss stale pull request approvals when new commits are pushed is on, and Require approval of the most recent reviewable push is on.
   - Require status checks to pass lists only `CI passed`, source GitHub Actions. Require branches to be up to date is off.
   - Block force pushes and Restrict deletions are on.
5. **Import the `ios-*` tag ruleset.** Same steps with `ios-tags.json`. Check that the target is `refs/tags/ios-*` (shown as `ios-*`), Restrict creations, Restrict updates and Restrict deletions are on, and the bypass list has Repository admin set to Always.
6. **Run the check** from a checkout of `main`, signed in to `gh` as the owner:

   ```bash
   .github/scripts/repo-settings-check.sh
   ```

   Every line should read `pass` and it should exit 0. Post the output on #25 so Kate can verify. Anyone with read access can run it; without admin access the Dependabot lines read `can't read`, and if GitHub doesn't return the bypass list the bypass lines read `can't read` too.

If you edit a ruleset in the UI later, export it (the ruleset's menu > Export ruleset) and update the file in a PR, so the files and the live settings match.

### What the check reads

`repo-settings-check.sh` makes only GET requests through `gh api`: `rules/branches/main` (active rules on `main`), `rulesets` and each `rulesets/{id}` (targets, rules and bypass list), the repository (for the admin permission), `vulnerability-alerts` and `automated-security-fixes`. It changes nothing. It checks rulesets only, not classic branch protection rules.

### What these rulesets don't stop

The admin bypass is set to Always because tags are not pushed through pull requests, and on a personal-account repository the bypass list takes roles, not users. The bots sign in as the owner's account, so they get the same bypass: they can push to `main` directly and create, move or delete `ios-*` tags until #147 is settled. The rulesets stop every login without the admin role.

## Optional, owner decides

These are review settings from #25. None of them is in `main.json`. Each can be turned on later in the `main` ruleset, and then exported back to the file. As of 2026-10-25, the collaborators are `rohanthomas1202` (admin), `Agent-Kate-QA` (write) and `Agent-Jules-UX` (write).

- **1 approving review.** The bots open their PRs from `rohanthomas1202`, and GitHub doesn't count an author's approval of their own PR, so each merge would wait for a GitHub approval from `Agent-Kate-QA` or `Agent-Jules-UX`. Dependabot PRs and the owner's own PRs would wait for an approval too. Either reviewer's approval satisfies it, so it can't require both Kate and Jules on UI PRs. Logins with the admin role can still merge past it through the bypass, and that includes the bots.
- **Require review from Code Owners.** `.github/CODEOWNERS` lists `@Agent-Kate-QA` on every path, so every PR would wait for Kate's approval. On UI paths one approval from any listed owner is enough, so it would not require Jules. On `supabase/migrations/` the owner is also listed, but the owner can't approve PRs opened from the owner's own account, so Kate's approval is the one that counts. The bypass applies here too.
- **Reviewer accounts' write access.** GitHub counts an approval toward these rules only from an account with write access, and code owners need write access to be requested. Both reviewer accounts have write access today, so the two settings above would apply as soon as they are on. Write access also lets those accounts push branches and merge PRs that meet the rules.
- **Require branches to be up to date before merging.** #25 recommends it. It would make every open PR re-merge `main` and rerun CI after each merge to `main`, which slows the bots when several PRs are open.
