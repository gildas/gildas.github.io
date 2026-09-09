# GPG Tutorial: Creating, Configuring, and Managing GPG Keys

This guide covers:
1. Installing GPG
2. Creating a key
3. Configuring Git (CLI) to sign commits
4. Configuring VSCode
5. Adding your key to Bitbucket
6. Changing a key's expiration date
7. Moving your key to another computer
8. Publishing your key to the OpenPGP keyserver

---

## 1. Install GPG

**macOS**
```bash
brew install gnupg
```

**Linux (Debian/Ubuntu)**
```bash
sudo apt update && sudo apt install gnupg
```

**Windows**
Install [Gpg4win](https://gpg4win.org/), or via `winget`:
```powershell
winget install GnuPG.Gpg4win
```

Check it's installed:
```bash
gpg --version
```

---

## 2. Create a GPG key

Run the guided key generator:
```bash
gpg --full-generate-key
```

You'll be prompted for:
- **Key type**: choose `RSA and RSA` (default) or `ECC (Curve 25519)` if you want a smaller/modern key.
- **Key size**: `4096` if RSA.
- **Expiration**: e.g. `1y` (recommended — you can extend it later, see §6). Avoid "does not expire" for signing keys used with services like GitHub/Bitbucket.
- **Name / Email**: use the **same email as your Git commit author email** and your Bitbucket account email — this is what lets Bitbucket/GitHub match the signature to your account.
- **Passphrase**: set a strong one; you'll be asked for it whenever the key signs something.

### List your keys
```bash
gpg --list-secret-keys --keyid-format=long
```

Example output:
```
sec   rsa4096/3AA5C34371567BD2 2026-01-01 [SC] [expires: 2027-01-01]
      Key fingerprint = XXXX XXXX XXXX XXXX XXXX  XXXX XXXX XXXX XXXX XXXX
uid                 [ultimate] Your Name <you@example.com>
ssb   rsa4096/42B317FD4BA89E7A 2026-01-01 [E] [expires: 2027-01-01]
```

The string after `rsa4096/` on the `sec` line (`3AA5C34371567BD2`) is your **key ID** — you'll use it below. `[SC]` means it can Sign and Certify; `[E]` (subkey) is for Encryption.

---

## 3. Configure Git (CLI) to sign commits

Tell Git which key to use and turn signing on:

```bash
git config --global user.signingkey 3AA5C34371567BD2
git config --global commit.gpgsign true
git config --global tag.gpgsign true
```

Make sure Git can find `gpg` (mostly relevant on Windows):
```bash
git config --global gpg.program gpg
# On Windows with Gpg4win, this is often:
# git config --global gpg.program "C:\Program Files (x86)\GnuPG\bin\gpg.exe"
```

Test it:
```bash
git commit -S -m "test signed commit"
```

If it succeeds without prompting for a passphrase every single time, `gpg-agent` is caching it correctly (default behavior).

### Export your public key (needed for Bitbucket/GitHub)
```bash
gpg --armor --export 3AA5C34371567BD2 > public-key.asc
```
Or print it directly to copy/paste:
```bash
gpg --armor --export you@example.com
```

---

## 4. Configure VSCode

VSCode uses your system Git config, so once `commit.gpgsign` is set globally (step 3), VSCode's Source Control panel will sign commits automatically — no extra setting is *required*. A few things to check:

1. **Enable commit signing in settings** (optional explicit toggle, defaults to following Git config):
   Open `settings.json` (`Ctrl/Cmd+Shift+P` → "Preferences: Open User Settings (JSON)") and add:
   ```json
   {
     "git.enableCommitSigning": true
   }
   ```

2. **GPG must be on your PATH.** VSCode's integrated terminal and Git integration both call the same `gpg` binary Git uses. If VSCode can't find it on Windows, set the full path via the `gpg.program` git config shown above (VSCode respects `.gitconfig`).

3. **Passphrase prompts**: On Linux/macOS, `gpg-agent` normally pops up a pinentry dialog. If it doesn't appear (common in some VSCode/Windows setups), configure a graphical pinentry program:
   ```bash
   echo "pinentry-program /usr/bin/pinentry-gtk-2" >> ~/.gnupg/gpg-agent.conf
   gpgconf --kill gpg-agent
   ```
   (Use `pinentry-mac` on macOS, or the Gpg4win pinentry on Windows.)

4. **Verify**: make a commit through the VSCode UI, then run `git log --show-signature -1` in a terminal to confirm it's signed.

---

## 5. Add your key to Bitbucket

1. Export your public key (see end of §3):
   ```bash
   gpg --armor --export you@example.com
   ```
2. Copy the entire output, including the `-----BEGIN PGP PUBLIC KEY BLOCK-----` / `-----END-----` lines.
3. In Bitbucket: click your avatar (bottom-left) → **Personal settings** → **GPG keys** (under "Security" in the sidebar).
4. Click **Add key**, paste the exported key, and save.
5. Push a signed commit and open it in Bitbucket — it should show a **"Verified"** badge next to the commit.

> Note: Bitbucket matches the key by the email in the UID, so that email must be one of the verified emails on your Bitbucket account.

---

## 6. Modify the expiration date of an existing key

You don't need to create a new key just because it's expiring — you can extend (or shorten) it in place.

```bash
gpg --edit-key 3AA5C34371567BD2
```

Inside the interactive `gpg>` prompt:
```
gpg> expire
```
You'll be asked for a new validity period (e.g. `1y`, `2y`, `0` for no expiration). Confirm, then:
```
gpg> save
```

If your key has a separate **encryption subkey**, its expiration is set independently. To change it, select the subkey first:
```
gpg> key 1
gpg> expire
gpg> save
```
(`key 1` selects the first subkey; running `key 1` again deselects it. Repeat for additional subkeys with `key 2`, etc.)

After changing the expiration, **re-publish/re-upload the updated public key** anywhere you previously shared it (Bitbucket, GitHub, keyservers — see §8), otherwise those services still see the old expiration date.

---

## 7. Move/copy your key to another computer

Your **secret key** never touches a server — you move it directly between machines.

### On the original computer — export both keys
```bash
# Public key
gpg --armor --export you@example.com > public-key.asc

# Secret key (contains your private key material — handle like a password)
gpg --armor --export-secret-keys you@example.com > private-key.asc

# Also export ownertrust so trust settings carry over
gpg --export-ownertrust > ownertrust.txt
```

Transfer `public-key.asc`, `private-key.asc`, and `ownertrust.txt` to the new machine **over a secure channel** — e.g. a USB drive, `scp` over SSH, or an encrypted archive. Never email the secret key file or upload it anywhere public.

### On the new computer — import
```bash
gpg --import public-key.asc
gpg --import private-key.asc
gpg --import-ownertrust ownertrust.txt
```

You'll be prompted for the original passphrase during import. Verify it's there:
```bash
gpg --list-secret-keys --keyid-format=long
```

### Clean up
Securely delete the exported private key file from both machines once done, e.g.:
```bash
shred -u private-key.asc      # Linux
# or just delete it and empty the trash/recycle bin securely
```

Finally, repeat the Git config steps from §3 on the new machine (`user.signingkey`, `commit.gpgsign`).

---

## 8. Publish your public key to OpenPGP (keys.openpgp.org)

The modern OpenPGP keyserver only publishes **User IDs with verified email addresses**, so there's a confirmation step.

### Option A: via `gpg` directly
```bash
gpg --keyserver hkps://keys.openpgp.org --send-keys 3AA5C34371567BD2
```
Then go to [keys.openpgp.org](https://keys.openpgp.org), search your key by fingerprint, and use the **"send verification email"** flow if prompted — or:

### Option B: via the website (recommended, handles email verification cleanly)
```bash
gpg --armor --export you@example.com > public-key.asc
```
1. Go to **https://keys.openpgp.org/upload**
2. Upload `public-key.asc` (or paste its contents).
3. The site will list which UIDs (emails) were found and email each one a verification link.
4. Click the link in your inbox to make that email address searchable/published.

Until verified, the key is uploaded but not discoverable by email search (only by fingerprint).

### Verify it's published
```bash
gpg --keyserver hkps://keys.openpgp.org --search-keys you@example.com
```

### Fetching your key on another machine from the keyserver
```bash
gpg --keyserver hkps://keys.openpgp.org --recv-keys 3AA5C34371567BD2
```
Note: this only retrieves the **public** key — it does not substitute for the secure private-key transfer in §7.

---

## Quick reference

| Task | Command |
|---|---|
| Generate key | `gpg --full-generate-key` |
| List keys | `gpg --list-secret-keys --keyid-format=long` |
| Export public key | `gpg --armor --export <email>` |
| Export secret key | `gpg --armor --export-secret-keys <email>` |
| Change expiration | `gpg --edit-key <keyid>` → `expire` → `save` |
| Sign commits (git) | `git config --global commit.gpgsign true` |
| Set signing key (git) | `git config --global user.signingkey <keyid>` |
| Upload to keyserver | `gpg --keyserver hkps://keys.openpgp.org --send-keys <keyid>` |
| Fetch from keyserver | `gpg --keyserver hkps://keys.openpgp.org --recv-keys <keyid>` |
