# Releasing Revive

Every installed copy of Revive checks `appcast.xml` on the `main` branch at launch and every hour
(Sparkle). Publishing a version is one command; the setup below is done once, by the maintainer.

## One-time setup

### 1. Release signing certificate

Releases are signed with a self-signed certificate named **Revive Release**. Its job is to keep the
app's identity stable: macOS then keeps Full Disk Access and other permissions across updates, and
the privileged helper accepts only apps signed with the same certificate.

```bash
# Creates the certificate in the login keychain (key never leaves it).
cat > /tmp/revive-cert.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Revive Release
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
openssl req -x509 -newkey rsa:3072 -nodes -keyout /tmp/k.pem -out /tmp/c.pem -days 3650 -config /tmp/revive-cert.cnf
openssl pkcs12 -export -inkey /tmp/k.pem -in /tmp/c.pem -name "Revive Release" -out /tmp/id.p12 -passout pass:temp
security import /tmp/id.p12 -k ~/Library/Keychains/login.keychain-db -P temp -T /usr/bin/codesign
rm /tmp/k.pem /tmp/c.pem /tmp/id.p12 /tmp/revive-cert.cnf
```

The first signing shows a keychain prompt: choose **Always Allow**.

### 2. Sparkle update key

Updates are accepted only when signed with the EdDSA key whose public half is `SUPublicEDKey` in
`project.yml`. The private half lives in the maintainer's keychain:

```bash
build/sparkle/bin/generate_keys --account io.github.mbielle.Revive
```

(`scripts/release.sh` downloads Sparkle's tools into `build/sparkle` the first time.)

### 3. Back up both keys

**If either key is lost, installed copies can no longer update.** Keep a copy somewhere safe and offline:

- *Revive Release*: Keychain Access › My Certificates › right-click › Export… (`.p12`, with a password)
- *Sparkle key*: `build/sparkle/bin/generate_keys --account io.github.mbielle.Revive -x revive-sparkle-key.txt`

Never commit these files.

## Publishing a version

1. Write the release notes in a Markdown file, e.g. `notes.md` (headings, `- ` bullets, `**bold**`).
2. With a clean working tree on `main`:

```bash
scripts/release.sh 0.4.1 notes.md
```

The script bumps the version and build number, builds and signs the DMG, signs it for Sparkle,
adds it to `appcast.xml`, commits, tags, pushes and creates the GitHub release. Installed copies
offer the update within an hour, or right away with **Revive › Check for Updates…**.

## Testing an update locally

```bash
LOCAL=1 DOWNLOAD_BASE=http://localhost:8765 scripts/release.sh 0.4.1
LOCAL=1 DOWNLOAD_BASE=http://localhost:8765 scripts/release.sh 0.4.2 notes.md
```

Nothing is committed or published. Serve `appcast.xml` and both DMGs with
`python3 -m http.server 8765`, install the 0.4.1 app, point its `SUFeedURL` at
`http://localhost:8765/appcast.xml` (and allow local networking in `NSAppTransportSecurity`),
re-sign it with `codesign -f -s "Revive Release" --preserve-metadata=identifier,entitlements,requirements,flags,runtime`,
then use **Check for Updates…**. Reset `project.yml` and delete `appcast.xml` afterwards.

## Later: Developer ID

With an Apple Developer ID, `DEVELOPER_ID=… NOTARY_PROFILE=… scripts/make-dmg.sh` signs and
notarizes the DMG, so the first launch no longer needs "Open Anyway". Switching certificates
changes the app's identity once: users grant Full Disk Access again after that update.
