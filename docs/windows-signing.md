# Windows code signing

Why `Gen2Recomped.exe` shows **"Windows protected your PC"**, what actually
removes it, and how to wire each option into `.github/workflows/release.yml`.

This is about the **.exe and the .msix**. For the MSIX-specific trust step
players do today (importing a `.cer`), see [msix-signing.md](msix-signing.md) —
that file solves *installability*; this one solves *the scary warning*.

---

## What SmartScreen is actually judging

Microsoft Defender SmartScreen looks at two things when a file is downloaded
and run:

1. **File reputation** — has *this exact file hash* been downloaded and run
   cleanly by enough people?
2. **Publisher reputation** — is it signed, and does *that signing identity*
   have a clean history?

An unsigned build has neither. Every release is a brand-new hash, so file
reputation resets to zero on every version you ship — which is why the warning
never goes away no matter how many downloads `0.7.4` got.

Signing is what gives you the second signal, and it is the only one that
**carries across releases**. That is the whole point: reputation attaches to
the certificate, not the file, so `0.8.0` inherits what `0.7.9` earned.

Three things worth knowing before you spend money:

- **EV certificates no longer bypass SmartScreen.** They used to grant instant
  reputation; Microsoft removed that in 2024. An EV cert now builds reputation
  on exactly the same curve as a cheaper OV one, so paying the EV premium
  *solely* to skip the warning buys nothing.
- **Self-signed does not help at all here.** Windows treats a signature it
  cannot chain to a trusted root as equivalent to no signature. Your existing
  `gen2recomped-signing.pfx` makes the MSIX *installable* after a manual
  `.cer` import; it does nothing for SmartScreen on the .exe.
- **Nothing is instant except the Store.** Even correctly signed, expect a few
  weeks and a few hundred clean installs before warnings stop. The certificate
  starts the clock; it doesn't skip it.

---

## The four options

| Route | Cost | Warning gone | Notes |
|---|---|---|---|
| **Azure Artifact Signing** (was Trusted Signing) | ~$9.99/mo | after reputation builds | Microsoft's own service; certs are short-lived and issued per-signature. Individual devs: **US and Canada only**. |
| **OV certificate** from a CA | $150–300/yr | after reputation builds | Key must live on a hardware token or cloud HSM (CA/B rule since 2023), so CI signing needs a cloud signing service on top. |
| **EV certificate** | $400+/yr | after reputation builds | Same SmartScreen behaviour as OV since 2024. Only worth it if an enterprise procurement process demands EV. |
| **Microsoft Store** | free | **immediately** | Microsoft signs the submission with its own cert. Zero warnings, ever — but it's a Store listing with Store certification. |

**Recommendation for this repo:** Azure Artifact Signing for the direct
download, and — if you want a *warning-free* path to point people at —
the Store listing alongside it rather than instead of it. You already build an
MSIX, which is the format the Store wants.

---

## Option 1 — Azure Artifact Signing (recommended)

Formerly "Azure Trusted Signing", formerly "Azure Code Signing". Same service,
three names.

### Eligibility

- **Organisation:** must be 3+ years old (or go through extra validation).
- **Individual:** open to individual developers, currently **US and Canada
  only**. If you're outside that, skip to Option 2.

### One-time setup

1. **Create the resources** in the Azure portal:
   - a subscription (pay-as-you-go is fine)
   - a **Trusted Signing / Artifact Signing account** — pick a region and the
     **Basic** tier (~$9.99/month, 5,000 signatures)
   - an **Identity Validation** request under that account. This is the slow
     part: Microsoft verifies who you are. Individual validation is usually a
     few business days; organisation validation can take longer.
   - once validation is approved, a **Certificate Profile** of type
     `PublicTrust`

2. **Create a service principal** for CI and give it the signing role:

   ```bash
   az ad sp create-for-rbac --name "gen2recomped-signing" \
     --role "Trusted Signing Certificate Profile Signer" \
     --scopes "/subscriptions/<SUB_ID>/resourceGroups/<RG>/providers/Microsoft.CodeSigning/codeSigningAccounts/<ACCOUNT>"
   ```

   Keep the `appId`, `password` and `tenant` it prints.

3. **Store them as repository secrets** (Settings → Secrets and variables →
   Actions):

   | Secret | Value |
   |---|---|
   | `AZURE_CLIENT_ID` | the `appId` |
   | `AZURE_CLIENT_SECRET` | the `password` |
   | `AZURE_TENANT_ID` | the `tenant` |
   | `SIGNING_ENDPOINT` | e.g. `https://eus.codesigning.azure.net` |
   | `SIGNING_ACCOUNT` | your account name |
   | `SIGNING_PROFILE` | your certificate profile name |

### Wiring it into the release workflow

**Order matters.** `scripts/build.sh` builds the .exe by concatenating the
payload onto LÖVE's binary:

```sh
cat "$love_dir/love.exe" "$LOVE_FILE" > "$out_dir/$APP_NAME.exe"
```

Authenticode requires its signature to be the last thing in the file, so:

- ✅ **fuse, then sign** — the signature goes after the fused `game.love`
- ❌ **sign, then fuse** — appending `game.love` after the certificate table
  invalidates the signature immediately

One caveat to test once and then forget: LÖVE finds the fused archive by
scanning backwards from EOF for the zip end-of-central-directory record, and
the signature now sits between EOF and that record. Authenticode signatures run
4–10 KB and the scan window is 64 KB, so this works — but **run the signed
.exe once** the first time you set this up rather than assuming.

Because the `windows` job now runs on Linux, the cleanest tool is
[jsign](https://ebourg.github.io/jsign/), which speaks Azure Artifact Signing
natively and needs nothing but a JRE:

```yaml
      - name: Sign the Windows executable
        if: ${{ secrets.AZURE_CLIENT_ID != '' }}
        env:
          AZURE_CLIENT_ID:     ${{ secrets.AZURE_CLIENT_ID }}
          AZURE_CLIENT_SECRET: ${{ secrets.AZURE_CLIENT_SECRET }}
          AZURE_TENANT_ID:     ${{ secrets.AZURE_TENANT_ID }}
        run: |
          set -euo pipefail
          curl -fL -o /tmp/jsign.jar \
            https://github.com/ebourg/jsign/releases/download/6.0/jsign-6.0.jar

          # Sign the FUSED exe, in place, inside build.sh's work dir --
          # before the zip is assembled.
          java -jar /tmp/jsign.jar \
            --storetype TRUSTEDSIGNING \
            --keystore "${{ secrets.SIGNING_ENDPOINT }}" \
            --storepass "$(az account get-access-token --resource https://codesigning.azure.net --query accessToken -o tsv)" \
            --alias "${{ secrets.SIGNING_ACCOUNT }}/${{ secrets.SIGNING_PROFILE }}" \
            --tsaurl http://timestamp.acs.microsoft.com \
            --name "Gen2Recomped" \
            --url "https://github.com/${{ github.repository }}" \
            .bazinga/work/Gen2Recomped-win64/Gen2Recomped.exe
```

That step has to land **between** `Build Windows (win64)` and
`Stage the Windows archive` — which means splitting the build step so the zip
is created after signing, or re-zipping. The simplest shape is to let
`build.sh win` run as it does, sign the extracted exe, and rebuild the zip:

```yaml
      - name: Re-zip with the signed executable
        run: |
          set -euo pipefail
          rm -f dist/win/Gen2Recomped-win64.zip
          (cd .bazinga/work && zip -q -9 -r ../../dist/win/Gen2Recomped-win64.zip Gen2Recomped-win64)
```

The MSIX job then picks the signed exe up for free, because it repacks
`windows-raw`.

**Always pass `--tsaurl`.** A timestamped signature stays valid after the
certificate expires. Artifact Signing certificates are deliberately short-lived
(days), so without a timestamp every release would stop verifying almost
immediately.

### Signing the MSIX with the same identity

Replace the `-CertPath`/`-MakeCert` path in `scripts/build_msix.ps1` with the
official action on a Windows runner:

```yaml
      - uses: azure/trusted-signing-action@v0
        with:
          azure-tenant-id:     ${{ secrets.AZURE_TENANT_ID }}
          azure-client-id:     ${{ secrets.AZURE_CLIENT_ID }}
          azure-client-secret: ${{ secrets.AZURE_CLIENT_SECRET }}
          endpoint:            ${{ secrets.SIGNING_ENDPOINT }}
          trusted-signing-account-name: ${{ secrets.SIGNING_ACCOUNT }}
          certificate-profile-name:     ${{ secrets.SIGNING_PROFILE }}
          files-folder: dist/msix
          files-folder-filter: msix
          file-digest: SHA256
          timestamp-rfc3161: http://timestamp.acs.microsoft.com
          timestamp-digest: SHA256
```

The MSIX manifest's `Identity/@Publisher` must match the certificate's subject
**character for character** — so the `-Publisher` default of `CN=Gen2Recomped`
has to change to whatever Azure issues you (something like
`CN=UNDERdecodedHD, O=..., C=US`). `build_msix.ps1` already checks this and
fails loudly with both values printed, which is the failure you want.

Once the MSIX is signed this way, **players no longer import a `.cer` at all** —
it chains to a root Windows already trusts. That removes the single ugliest
step in the current install instructions.

---

## Option 2 — OV certificate from a commercial CA

Use this if you're outside the US/Canada, or you want a certificate you own
outright rather than a monthly service.

1. Buy an **OV code signing** certificate — Sectigo, SSL.com, DigiCert and
   Certera all sell them, $150–300/year. Buying through a reseller
   (SSLs.com, CodeSignStore) is usually cheaper than direct.
2. Complete validation: business registration documents, or for a sole trader,
   government ID plus a verifiable phone listing. Expect several days.
3. **You cannot get a `.pfx`.** Since June 2023 the CA/Browser Forum requires
   the private key to be generated on and never leave FIPS 140-2 Level 2
   hardware. You will be shipped either:
   - a **USB hardware token** (YubiKey / SafeNet eToken) — cannot be used from
     GitHub-hosted CI at all, only from a machine you physically own, or
   - a **cloud HSM signing service** — SSL.com eSigner, DigiCert KeyLocker,
     or the CA's equivalent. This is the one to ask for if you want CI signing.
4. Sign from CI through that service. `jsign` covers most of them:

   ```bash
   # SSL.com eSigner
   java -jar jsign.jar --storetype ESIGNER \
     --storepass "$ESIGNER_USER|$ESIGNER_PASS" \
     --keystore https://cs.ssl.com \
     --alias "$ESIGNER_CREDENTIAL_ID" \
     --tsaurl http://ts.ssl.com \
     Gen2Recomped.exe

   # DigiCert KeyLocker
   java -jar jsign.jar --storetype DIGICERTONE \
     --storepass "$SM_API_KEY|/path/to/cert.p12|$SM_CLIENT_CERT_PASSWORD" \
     --alias "$SM_CERT_ALIAS" \
     --tsaurl http://timestamp.digicert.com \
     Gen2Recomped.exe
   ```

   Same fuse-then-sign ordering rule as above.

A third-party option worth knowing: **[SignPath](https://signpath.io)** offers
free code signing (certificate included) to OSS projects that meet their
criteria, with a GitHub Actions integration. Gen2Recomped is a public repo with
a real release pipeline, so it is a plausible fit and costs nothing to ask.

---

## Option 3 — EV certificate

Everything in Option 2, but $400+/year and a mandatory hardware token or cloud
HSM.

**Do not buy this to get rid of SmartScreen warnings.** The instant-reputation
behaviour that justified the price was removed in 2024; an EV-signed .exe now
sits in exactly the same reputation queue as an OV-signed one. Buy EV only if
something outside your control (an enterprise allowlist, a distribution
partner) specifically requires it.

---

## Option 4 — Microsoft Store

The only route with **no warning on day one**, because Microsoft signs the
submission with its own certificate and Store installs bypass SmartScreen
download checks entirely.

You already build the hard part. To submit:

1. Register a Partner Center developer account (one-off ~$19 individual /
   ~$99 company).
2. Reserve the app name; Partner Center gives you an identity block:
   `PackageName`, `Publisher` (a `CN=` GUID-ish string), `PublisherDisplayName`.
3. Rebuild the MSIX with **no signing flags at all** — no `-MakeCert`, no
   `-CertPath`:

   ```powershell
   ./scripts/build_msix.ps1 -Source dist/win/Gen2Recomped-win64 `
     -Version $v -OutFile dist/msix/Gen2Recomped-$v.msix `
     -PackageName "<from Partner Center>" `
     -Publisher "<from Partner Center>" `
     -PublisherDisplayName "<from Partner Center>"
   ```

   The Store signs it during ingestion. A package you signed yourself is
   rejected.
4. Upload, fill in the listing, submit for certification (a few days for a
   first submission).

Worth doing **alongside** the direct download, not instead of it — the Store
gives you a link you can point cautious players at, while the GitHub release
stays the fast path.

---

## What none of this fixes

The release ships `.zip` files. A zip has no signature of its own, so the
browser's own download check (Chrome's "this file isn't commonly downloaded",
Edge's equivalent) judges it by hash alone and will keep flagging fresh
releases regardless of what's inside.

If that specific warning matters, the fix is to ship a **signed installer**
(`.msi`, or an Inno Setup / NSIS `.exe`) as the primary Windows download and
demote the zip to the portable option. A signed single-file installer is the
shape browsers and SmartScreen are both built around; a zip of a directory is
not.

---

## Checklist

- [ ] Pick a route (Artifact Signing unless you're outside US/CA)
- [ ] Complete identity validation — this is the long pole, start it first
- [ ] Add the secrets to the repo
- [ ] Sign **after** the `cat love.exe game.love` fuse, never before
- [ ] Always pass a timestamp URL
- [ ] Run the signed .exe once to confirm LÖVE still finds the fused archive
- [ ] Update `Identity/@Publisher` in the MSIX to match the new certificate
- [ ] Drop the `.cer` import step from the player-facing install docs
- [ ] Expect a few weeks of residual warnings while reputation accrues
