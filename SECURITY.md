# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | ✅ Yes    |
| < 1.0   | ❌ No     |

## Reporting a Vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

If you discover a security issue, please report it through one of these channels:

1. **GitHub Private Advisory (preferred):**  
   Open a [private security advisory](https://github.com/zr0aces/CUPS-Canon-LBP7110cw/security/advisories/new)
   directly on GitHub. This keeps the report confidential until a fix is ready.

2. **Email:**  
   Contact the maintainer at the email address listed in their GitHub profile.

## What to Include

Please include as much of the following as possible:

- Description of the vulnerability and its impact
- Steps to reproduce the issue
- Affected version(s)
- Suggested fix (if any)

## Response Timeline

- **Acknowledgement:** within 72 hours
- **Status update:** within 7 days
- **Fix and release:** as soon as possible, depending on severity

Reporters will be credited in the `CHANGELOG.md` unless they prefer to remain anonymous.

## Scope

This project is a Docker-based CUPS print server. Security issues in scope include:

- Authentication bypass or privilege escalation in the CUPS configuration
- Container escape or host privilege escalation
- Sensitive data exposure (credentials, print job contents)
- Supply-chain concerns (driver tarball integrity)

Issues in the upstream Canon UFR II driver or Ubuntu base image should be
reported to their respective maintainers.
