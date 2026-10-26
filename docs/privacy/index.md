---
title: PokerStats Privacy Policy
permalink: /privacy/
---

# PokerStats Privacy Policy

**Last updated:** October 18, 2026

PokerStats is an iPhone app for tracking poker sessions. This policy explains what data the app handles, where it is stored, how long it is kept, and how you can delete it. "We" and "us" mean the developer of PokerStats.

## Summary

- If you never sign in, everything you enter stays on your iPhone. Nothing is sent to us.
- Signing in with Apple is optional. It turns on cloud backup. When you are signed in, we store your account details and your backups with Supabase, our hosting provider.
- PokerStats has no ads, no analytics, and no tracking. We do not sell or share your data.
- You can delete your account and all of its cloud data from the app at any time.

## Data stored on your iPhone

Everything you enter is stored in the app's local database on your iPhone:

- Sessions: start and end time, location (text you type), game type, stakes, buy-in, rebuys, add-ons, cash-out, tips or rake, and notes.
- Hand logs: position, preflop action, 3-bet response, postflop result, continuation bet, and notes.
- Mental-state ratings: tilt, energy, and focus.
- Table setup and your default settings (game type, stakes, buy-in, currency).

The PokerStats widgets read this database to show your lifetime stats on the Home Screen. During a session, a Live Activity shows the stakes, location, start time, hand count, and amount invested on the Lock Screen and in the Dynamic Island, where anyone who can see your screen can see them. Widgets and Live Activities run on your iPhone. Their data is not sent to us.

If you sign in, the app also keeps your sign-in tokens, your account user ID, your email address, and your Apple user ID in the iOS Keychain on your iPhone. It also keeps a setting that records whether automatic restore has already run on this iPhone.

## Data we collect if you sign in

Signing in is optional and is only needed for cloud backup.

**Account.** PokerStats uses Sign in with Apple. Apple gives the app a sign-in token that contains your Apple user ID and email address. If you chose Hide My Email, the email is an Apple relay address. Our backend (Supabase) stores:

- your PokerStats account ID,
- your Apple user ID,
- your email address,
- when the account was created and when you last signed in,
- when your last backup was made.

PokerStats does not store your name.

**Backups.** While you are signed in, the app backs up automatically each time you end a session, and when you tap Back Up Now in Settings > Cloud Backup. A backup contains all of your sessions, hand logs, notes, mental-state ratings, table setups, default settings, and the app version. It is compressed and uploaded to a private storage bucket in your account's folder. For each backup we also store a record of its file name, size, format version, session count, hand count, and creation time.

Backups are sent over HTTPS. Access rules limit each account to its own backups, and Supabase encrypts stored data at rest. Backups are not end-to-end encrypted, so as the operator of the service we are technically able to access them. We use backups only to restore your data to you.

**Restoring.** When you sign in on an iPhone that has no PokerStats data, the app restores your most recent backup automatically. This happens at most once per iPhone, and never after you use Delete All Data on that iPhone. You can restore any listed backup yourself from Settings > Cloud Backup.

**Technical data.** Like any online service, Supabase receives your IP address and basic request details when the app talks to it, and keeps them in service logs. If account deletion fails, our server logs your account ID and the failed step so the problem can be fixed. We do not use this data to track you.

## What we do not collect

- No analytics, advertising, or tracking SDKs, and no third-party crash reporting.
- No advertising identifier and no tracking across apps or websites.
- No GPS or device location. The location field is text you type.
- No contacts, photos, health data, or payment information.

If you have turned on sharing with app developers in iOS Settings > Privacy & Security > Analytics & Improvements, Apple may share crash reports and usage statistics with us. Apple controls that sharing.

## How long we keep data

- **On your iPhone:** until you delete it in the app or delete the app.
- **Cloud backups:** the app keeps your 5 most recent backups. When a new backup is made, older ones are deleted. Your backups are kept until you delete your account. Signing out does not delete them.
- **Account data:** until you delete your account.
- **Service logs:** kept by Supabase for a limited period under its own retention rules.

## How to delete your data

**Delete Account** (Settings > Delete Account) deletes your account and all of its cloud data:

1. You confirm with Sign in with Apple again.
2. Our server revokes the app's Sign in with Apple token with Apple.
3. It deletes all of your backup files, your backup records, your profile, and then your account.
4. Once the server confirms, the app removes all PokerStats data from that iPhone (sessions, hands, and settings) and signs you out.

If deletion fails, nothing on your iPhone is removed and you can try again. If Apple disconnected your account but the rest of the deletion failed, the app tells you; sign in again and retry to finish it, or contact us.

**Delete All Data** (Settings > Delete All Data) removes your sessions and hand logs from that iPhone only. It does not delete your cloud backups, and they remain until you delete your account. Automatic restore will not bring the deleted data back on that iPhone, but you can still restore a backup yourself. Because the app keeps your 5 most recent backups, older backups that still contain the deleted data are only removed as newer backups replace them, or when you delete your account.

**Other ways:**

- Deleting the app removes the data stored on your iPhone. It does not delete your account or cloud backups.
- You can stop using Sign in with Apple with PokerStats in iOS Settings > [your name] > Sign-In & Security > Sign in with Apple. This does not delete your cloud data; use Delete Account for that.
- You can ask us to delete your account and data using the contact details below.

## Third parties

We use two service providers. We do not sell your data, share it with advertisers, or use it for advertising.

- **Apple** provides Sign in with Apple, the App Store, widgets, and Live Activities. See [Apple's Privacy Policy](https://www.apple.com/legal/privacy/).
- **Supabase** hosts our authentication, database, file storage, and the account deletion service. See [Supabase's Privacy Policy](https://supabase.com/privacy).

We may disclose data if the law requires it.

## Children

PokerStats is not directed at children under 17, and we do not knowingly collect data from them. If you believe a child has created an account, contact us and we will delete it.

## Changes to this policy

If we change this policy, we will post the new version on this page and update the date at the top.

## Contact

Email: [contact email: owner to confirm]

You can also open an issue at <https://github.com/rohanthomas1202/PokerStats/issues>.
