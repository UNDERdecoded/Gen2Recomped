# MSIX signing

Windows will not install an MSIX whose signature it cannot verify. There is no
way around that, and nothing in the package itself can fix it — the trust has
to come from the certificate.

There are two ways to satisfy it, and this repo supports both.

## The problem with `-MakeCert`

`scripts/build_msix.ps1 -MakeCert` calls `New-SelfSignedCertificate` at build
time, so **every run mints a brand-new certificate**. Trust in Windows is per
certificate, by thumbprint. That means:

- a player who installed 0.1.1 must import a *different* `.cer` for 0.1.2
- and again for 0.1.3, and every release after that

That is not a workflow anyone will follow, and it teaches players to click
through certificate warnings, which is worse than shipping no MSIX at all. Use
`-MakeCert` for a local package you are inspecting yourself, and nothing else.

## The fix: one long-lived certificate

Generate one certificate, keep it as a repository secret, and sign every
release with it. Players import the `.cer` **once**, and every future release
installs with no further steps.

### 1. Generate it (once, on Windows)

No elevation needed — this writes to your own user store.

```powershell
$cert = New-SelfSignedCertificate `
  -Type Custom `
  -Subject "CN=Gen2Recomped" `
  -KeyUsage DigitalSignature `
  -FriendlyName "Gen2Recomped release signing" `
  -CertStoreLocation "Cert:\CurrentUser\My" `
  -NotAfter (Get-Date).AddYears(10) `
  -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")

$cert.Thumbprint
```

`-Subject` must equal the manifest's `Identity/@Publisher` **character for
character**. That is `CN=Gen2Recomped`, the `-Publisher` default in
`scripts/build_msix.ps1`. A mismatch produces a package that signs cleanly and
then refuses to install; the script now checks for this before signing and
fails with both values printed.

The two `-TextExtension` entries are the Code Signing EKU
(`1.3.6.1.5.5.7.3.3`) and an empty Basic Constraints, marking it an end-entity
certificate rather than a CA. Both are required.

Ten years is deliberate. Releases are timestamped (see below), so packages
signed today keep validating after that date — but you cannot sign *new*
releases with an expired certificate, and the build fails outright if you try.

### 2. Export it

```powershell
$pw = Read-Host -AsSecureString "PFX password"
Export-PfxCertificate -Cert $cert -FilePath .\gen2recomped-signing.pfx -Password $pw
```

**Back this file up somewhere outside the repo, and do not commit it.** The
`.pfx` holds the private key. Lose it and every player has to trust a new
certificate all over again; leak it and anyone can sign packages that claim to
be you.

### 3. Store it as repository secrets

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes(".\gen2recomped-signing.pfx")) | Set-Clipboard
```

Then in the repo → **Settings → Secrets and variables → Actions**:

| Secret | Value |
|--|--|
| `MSIX_PFX_BASE64` | the base64 string now on your clipboard |
| `MSIX_PFX_PASSWORD` | the password you typed in step 2 |

Or with the CLI:

```powershell
gh secret set MSIX_PFX_BASE64 --body (Get-Clipboard)
gh secret set MSIX_PFX_PASSWORD
```

That is the whole setup. `.github/workflows/release.yml` picks the secrets up
automatically; when they are absent it falls back to `-MakeCert` and prints a
CI warning, so a fork still produces an installable package.

## What players do

Every release ships two files:

```
Gen2Recomped-<ver>-windows.msix
Gen2Recomped-<ver>-windows.cer
```

Once per machine, in an **elevated** PowerShell:

```powershell
Import-Certificate -FilePath .\Gen2Recomped-<ver>-windows.cer `
  -CertStoreLocation Cert:\LocalMachine\TrustedPeople

Add-AppxPackage .\Gen2Recomped-<ver>-windows.msix
```

Two details that are the entire difficulty of this error:

- **`LocalMachine`, not `CurrentUser`.** App Installer only consults the
  machine store. A certificate in the user store is invisible to it and yields
  `0x800B010A` — "the publisher certificate could not be verified" — which
  looks exactly like having imported nothing.
- **`TrustedPeople`, not `Trusted Root Certification Authorities`.** This is an
  end-entity certificate, not a CA. Putting it in the root store makes the
  machine trust it for *everything*, not just this app.

Once the certificate is in place, later releases install with just
`Add-AppxPackage` — same certificate, already trusted.

## Timestamping

`build_msix.ps1` signs with an RFC3161 timestamp (`-TimestampUrl`, default
`http://timestamp.digicert.com`). A timestamped signature records *when* the
signing happened, so it stays valid after the certificate expires.

Without one, the day the certificate lapses is the day every release ever
published stops installing simultaneously. If the timestamp server is
unreachable the build falls back to an untimestamped signature and warns
loudly rather than failing the release.

## If you outgrow this

A self-signed certificate always costs the player one manual trust step. Two
ways to remove it entirely:

- **Azure Trusted Signing** — chains to a root Windows already trusts, so
  packages install with no trust step at all. Needs an Azure subscription.
- **Microsoft Store** — do *not* pass `-MakeCert` or `-CertPath`. Reserve the
  name in Partner Center, then rebuild with `-PackageName`, `-Publisher` and
  `-PublisherDisplayName` copied verbatim from the app's identity page; the
  Store signs the submission itself.
