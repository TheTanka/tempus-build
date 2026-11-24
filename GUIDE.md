# Setup guide: automatic Tempus builds on GitHub + Obtainium

What you end up with:

- GitHub Actions checks upstream every 6 hours.
- On a new stable release it builds, signs and publishes `vX.Y.Z-tanka` in your repo.
- Obtainium on your phone picks up that release and updates the app.

Your keystore lives in KeePassXC and as an encrypted GitHub secret, and nowhere else.

Work through the sections in order. Section 1 matters most: some of those things cannot be undone after the first push or the first release.

---

## 1. Privacy checklist (before the first commit)

### 1.1 Commit email and name

Every commit carries an author name and email, and both are public forever once pushed.

1. GitHub, then Settings, then Emails:
   - Enable **Keep my email addresses private**
   - Enable **Block command line pushes that expose my email**
   - Copy your noreply address shown there (`<id>+<user>@users.noreply.github.com`)
2. In the repo (local config, so it does not change your other projects):
   ```
   git config user.name "tanka"
   git config user.email "<id>+<user>@users.noreply.github.com"
   ```
3. Before every first push of a new repo, check what you are about to publish:
   ```
   git log --format='%an <%ae> | %cn <%ce>'
   ```

### 1.2 Signing certificate identity (the easy one to miss)

The name you put into the keystore certificate is embedded in **every APK** and anyone can read it with `apksigner verify --print-certs`, Obtainium, AppVerifier and so on. The workflow also prints it in the release notes. `keytool` asks interactively for your first/last name, organisation, city, state and country. **Do not answer those.** Use `-dname "CN=tanka"` as shown in section 2.

You cannot change the certificate later without breaking updates: every phone would have to uninstall and reinstall. Get it right before the first release.

If you already have a keystore, check what it exposes:

```
keytool -list -v -keystore old.p12 | grep -E 'Owner|Issuer'
```

If that shows your real name or town, make a new key.

### 1.3 Files in the repo

- `.gitignore` and `.dockerignore` already exclude `*.p12 *.jks *.keystore *.pass keys/ out/`. Never rename your keystore to something that is not covered by them.
- Check what is tracked before pushing:
  ```
  git status --ignored
  git ls-files
  ```
- `logo.svg`: Inkscape can store absolute paths such as `/home/<you>/...` in `inkscape:export-filename` or `sodipodi:docname`. Check:
  ```
  grep -nE 'export-filename|docname|/home/|/Users/|C:\\' logo.svg
  ```
  No output means clean. Your current logo also contains a hidden, embedded PNG layer (the tracing source). It is not used for the icon, but it is published with the repo. Delete that layer in Inkscape if you do not want it public.

### 1.4 Workflow and logs

- The workflow never prints secrets, and GitHub also redacts secret values in logs. Do not add `set -x` or `echo` lines around secrets.
- The workflow has no `pull_request` trigger, so strangers cannot run code with your secrets. GitHub also never passes secrets to workflows triggered from forks.
- Third-party code is minimal: `actions/checkout` (pinned to a commit hash), the preinstalled `gh` CLI, and Docker.

---

## 2. Create the signing key

Work in a RAM-backed directory that only you can read, so the keystore never touches your disk in plain form:

```
mkdir -m 700 "$XDG_RUNTIME_DIR/tempus-key"
cd "$XDG_RUNTIME_DIR/tempus-key"
```

1. In KeePassXC, create a new entry **Tempus signing key** first and let the generator make the password: 32 characters, letters and digits only, which avoids quoting trouble.
2. Generate the key. Leave out `-storepass`, so the password is prompted for and does not end up in your shell history. Paste it from KeePassXC when asked:
   ```
   keytool -genkeypair \
     -keystore tempus.p12 -storetype PKCS12 \
     -alias tanka -keyalg RSA -keysize 4096 -validity 10000 \
     -dname "CN=tanka"
   ```
   PKCS12 uses the same password for the store and the key, so you only need `KS_PASS` later. `KEY_PASS` stays unset.
3. Check it and note the fingerprint:
   ```
   keytool -list -v -keystore tempus.p12 | grep -E 'Alias|Owner|SHA256'
   ```
   `Owner` must show only `CN=tanka`.

---

## 3. Store it in KeePassXC

In the **Tempus signing key** entry:

| Field | Content |
|---|---|
| Username | `tanka` (the alias) |
| Password | the keystore password |
| URL | `https://github.com/<user>/tempus-build` |
| Notes | the SHA-256 fingerprint, `CN=tanka`, creation date, and the keytool command from section 2 |
| Advanced, Attachments | add `tempus.p12` |

Then **test the restore before you rely on it**:

1. Save the attachment back out to another tmpfs folder.
2. Run `keytool -list -keystore <restored file>` with the password from the entry.
3. Compare the fingerprint.

**Backups.** The `.kdbx` is encrypted, so copies of it are safe to keep around:

- Keep at least 2 copies on different devices, one of them offline (for example a USB stick in a drawer).
- After adding the key, save the database and refresh those copies.
- Your master password (and key file, if you use one) must be recoverable without the database itself.

What each failure means:

| Situation | Consequence |
|---|---|
| Key **lost** | No more updates to the installed app. You must uninstall (losing app data) and install a build signed with a new key. |
| Key **leaked** | Someone else can build an "update" your phone accepts. Make a new key, replace the secrets, then uninstall and reinstall the app. |

When done, delete the loose copy (it is in RAM anyway and gone on reboot):

```
rm -r "$XDG_RUNTIME_DIR/tempus-key"
```

Do that only **after** section 4.3, because you need the file there once.

---

## 4. GitHub repository

### 4.1 Create and push

1. Create a **public** repo, e.g. `tempus-build`, with no README or license (you already have files).
2. Push:
   ```
   git init -b main
   git add .
   git status            # check nothing secret is staged
   git commit -m "chore: initial commit"
   git remote add origin git@github.com:<user>/tempus-build.git
   git push -u origin main
   ```

### 4.2 Repository settings

Settings, then Actions, then General:

- **Actions permissions:** Allow all actions (or "Allow GitHub actions" only; the workflow needs nothing else).
- **Workflow permissions:** Read repository contents. The workflow requests `contents: write` and `actions: write` for itself, so the default can stay restrictive.
- Leave **Allow GitHub Actions to create and approve pull requests** off.

### 4.3 Secrets

Use the `gh` CLI, so nothing passes through your clipboard history or shell history. Run this from the tmpfs folder in section 2:

```
base64 -w0 tempus.p12 | gh secret set KEYSTORE_B64 --repo <user>/tempus-build
gh secret set KS_PASS --repo <user>/tempus-build
```

The second command prompts; paste the password from KeePassXC. Alternatively use the web UI: Settings, then Secrets and variables, then Actions, then New repository secret.

| Secret | Required | Value |
|---|---|---|
| `KEYSTORE_B64` | yes | base64 of the keystore. A 4096-bit PKCS12 is a few KB; GitHub allows 48 KB. |
| `KS_PASS` | yes | keystore password |
| `KEY_PASS` | no | only for JKS keystores with a different key password |
| `KEY_ALIAS` | no | only if the keystore holds several keys |

Now delete the tmpfs folder (end of section 3).

---

## 5. First run

1. Actions, then **build**, then **Run workflow**.
2. The first build takes a while: there is no cache, so it downloads the Android SDK and all Gradle dependencies.
3. When green, open Releases. You should see `v4.32.0-tanka` with:
   - `tempus-degoogled-4.32.0-universal.apk` and one APK per ABI
   - `SHA256SUMS`
   - `icon-preview.png`
4. Compare the SHA-256 in the release notes with the fingerprint in your KeePassXC entry. Both are formatted differently (colons, case), but the hex digits must match.

From now on the schedule runs every 6 hours and only builds when upstream has a new stable tag.

---

## 6. Obtainium

1. Add App, then URL `https://github.com/<user>/tempus-build`.
2. **Filter APKs by regular expression:** `universal` (or `arm64-v8a` for a smaller download on modern phones). Without a filter Obtainium asks which APK to install every time.
3. Install. It installs as a separate app next to any F-Droid Tempus (package `com.eddyizm.degoogled.tempus.tanka`).

**Version detection.** The release tag is `v4.32.0-tanka` while the app reports `4.32.0`. Obtainium strips extra parts like a `v` prefix or a suffix when that leaves a normal version, and disables version detection when the formats do not match. If the app page shows a version-detection warning or keeps offering the same update, set **Trim version string** to:

```
\d+\.\d+\.\d+
```

**Rate limit.** Obtainium uses the GitHub API. With only a few GitHub apps you are fine; with dozens, add a GitHub personal access token (no scopes needed for public repos) in Obtainium's settings.

---

## 7. Maintenance

| Task | How |
|---|---|
| Rebuild the same upstream version (e.g. new logo) | Actions, then build, then Run workflow with **rebuild** ticked, which creates `-tanka.2`. Obtainium sees the same app version, so install it manually from the Obtainium app page. |
| Build fails | GitHub emails you. Typical causes: upstream changed the `applicationId` line the patch looks for, a new SDK, or Gradle memory. The log says which step failed. Nothing is published on failure. |
| Schedule stopped | Should not happen: each scheduled run re-enables the workflow, which resets GitHub's 60-day inactivity timer. If it does stop, Actions, then build, then Enable workflow. |
| Local build | Save the attachment from KeePassXC to a tmpfs folder, then run `KEYSTORE=$XDG_RUNTIME_DIR/tempus-key/tempus.p12 KS_PASS_FILE=... ./build.sh` |
| Change logo or icon background | Replace `logo.svg` or change `ICON_BG` in the Dockerfile, commit, then do a manual run with rebuild. |

### Key rotation (only if leaked)

1. Generate a new key (section 2) and store it (section 3).
2. Replace `KEYSTORE_B64` and `KS_PASS`.
3. Run with rebuild.
4. On the phone: uninstall, then install again via Obtainium. App data is lost; export your settings first if Tempus offers it.

---

## Sources

- GitHub: [Blocking command line pushes that expose your email](https://docs.github.com/en/account-and-profile/how-tos/email-preferences/blocking-command-line-pushes-that-expose-your-personal-email-address)
- GitHub: [Secrets reference (48 KB limit, fork behaviour)](https://docs.github.com/en/actions/reference/security/secrets)
- GitHub: [Disabling and enabling a workflow (60-day rule)](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/disable-and-enable-workflows)
- [liskin/gh-workflow-keepalive](https://github.com/liskin/gh-workflow-keepalive) (the API re-enable approach used here)
- Obtainium wiki: [How apps are tracked](https://hamster45105.github.io/Obtainium-Wiki/app_tracking), [App sources](https://imranr98.github.io/Obtainium-Wiki/sources)
