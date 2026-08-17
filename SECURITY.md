# Security policy

Seeko coordinates local Flutter scroll state and does not provide a network,
authentication, storage, or code-loading layer. Security reports are still
important when a defect can expose application data, cross an ownership
boundary, cause unsafe resource consumption, or compromise release artifacts.

## Supported versions

| Version | Supported |
| --- | --- |
| Latest published stable release | Yes |
| Older stable releases | Case by case until a newer security release is available |
| Unreleased development snapshots | Best effort; not a stable support contract |

## Report a vulnerability privately

Use the hosting repository's **Security → Report a vulnerability** private
reporting flow. Do not open a public issue, discussion, or pull request that
contains exploit details.

Include:

- Affected Seeko and Flutter/Dart versions.
- Platform, build mode, and relevant scrollable/driver configuration.
- Minimal reproduction or proof of concept.
- Expected and observed impact.
- Whether the issue affects confidentiality, integrity, availability, package
  publishing, CI credentials, or supply-chain artifacts.
- Any known workaround that does not disclose the vulnerability publicly.

If private vulnerability reporting is temporarily unavailable, contact the
maintainer through the private package-owner channel shown by the package host
and request a secure reporting channel before sending technical details.

## Response process

Maintainers will:

1. Acknowledge a complete report as soon as practical.
2. Reproduce and classify the issue without exposing reporter data.
3. Coordinate a fix, regression test, affected-version range, and release plan.
4. Request a CVE or ecosystem advisory when the impact warrants it.
5. Publish an advisory after a fixed release is available, crediting the
   reporter when requested and appropriate.

Response times depend on severity and maintainer availability. Acknowledgement
is not confirmation that a report is a vulnerability.

## Disclosure expectations

Please allow maintainers reasonable time to investigate and release a fix
before public disclosure. Avoid accessing data that is not yours, degrading a
third-party application, or using destructive test cases.

## Release and supply-chain security

- GitHub Actions must use minimum permissions and immutable action commit SHAs.
- pub.dev publishing uses trusted publishing/OIDC rather than a long-lived token.
- Release tags must match `pubspec.yaml` and pass the required quality gates.
- Generated archives must exclude local configuration, Cockpit artifacts,
  credentials, build output, and internal workspace instructions.
- A secret or dependency scan finding is investigated before release; it is not
  suppressed solely to make CI pass.

