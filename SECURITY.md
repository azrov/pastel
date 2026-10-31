# Security

## Reporting a problem

Please report security problems privately, through GitHub's **Report a vulnerability** button on the *Security* tab of the repository, not in a public issue. Tell us what is affected, how to reproduce it and what an attacker could do. We answer within a week and publish a fixed version as soon as possible; you are credited in the release notes unless you prefer not to be.

## Supported versions

| Version | Security fixes |
|---|---|
| 1.x (latest) | yes |
| older than 1.0 | no: please upgrade (`pastel upgrade` helps) |

## What Pastel protects against

The web server and database layer were reviewed for 0.7; what they protect against and what is left to the network in front of them is in [docs/security.md](docs/security.md#what-the-web-server-and-the-database-layer-protect-against).
