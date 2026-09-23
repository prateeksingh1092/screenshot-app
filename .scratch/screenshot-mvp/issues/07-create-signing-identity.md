# 07: Create the Personal Team signing identity

**What to build:** a stable Xcode Personal Team signing identity under Prateek's Apple ID, created when ticket 8 first needs a signed build (decision 42).

**Blocked by:** 03

**Status:** resolved

- [x] Prateek signs in to Xcode with his Apple ID and creates the Personal Team certificate himself.
- [x] No passwords or secrets are written to any file in the repository.
- [x] The certificate's name and expiry are noted (not its private key).

## Comments

### 2026-09-22 — verified by the coordinator

- Prateek signed in to Xcode with his Apple ID and created an Apple Development certificate for his Personal Team.
- The certificate at first showed as not valid, because the keychain lacked Apple's WWDR G3 intermediate. Prateek installed `AppleWWDRCAG3.cer` from apple.com/certificateauthority into the login keychain, without changing trust settings.
- `security find-identity -v -p codesigning`: 1 valid identity, "Apple Development: <Apple ID redacted> (DP3ZVUC5Y6)".
- Team ID (certificate OU): `9M43Q952NK`. Issued by WWDR CA G3; valid 2026-09-23 to 2027-09-23 (UTC). Free Personal Team; no paid program.
- No password, private key, or email address is recorded.
