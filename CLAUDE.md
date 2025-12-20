# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Deployer is a Perl script (`deployer.pl`) that automates server deployment for web applications. It handles git updates, supervisor configuration, nginx setup, SSL certificates (via CertBot or Cloudflare Origin Certificates), cron jobs, and environment variable management.

## Commands

Deploy the script to servers:
```bash
make deploy
```

Run the deployer on a target project (from within that project's directory):
```bash
~/bin/deployer.pl
```

## Architecture

The deployer is a single Perl script that runs in a target project directory and configures that project for production deployment. It requires:
- A `deployer/` directory in the target project containing configuration files
- sudo access on the target server
- Perl dependencies: `Modern::Perl`, `Config::Simple`, `File::Slurp`, `IPC::Run3`, `JSON::Any`

### Deployment Flow

1. Git fetch and rebase
2. Read configuration from `deployer/env` (key-value pairs, `?` values prompt for input)
3. Check/install packages from `deployer/packages`
4. Run `make` if Makefile exists
5. Minify assets listed in `deployer/minify`
6. Create directories from `deployer/dirs`
7. Setup cron from `deployer/cron.d`
8. Create supervisor config from `deployer/supervisor`
9. Handle SSL: Cloudflare Origin Cert (if `apex.pem`, `apex.key.age`, `key.age` exist) or CertBot
10. Generate nginx config and restart

### Required Environment Variables

Projects must define in `deployer/env`:
- `APEX` - domain name
- `PORT` - application port
- `WWW` - whether to add www redirect (0 or 1)
- `CMD` - command to run the application

### SSL Certificate Handling

For Cloudflare Origin Certificates, the project needs:
- `deployer/key.age` - age-encrypted private key
- `deployer/apex.key.age` - encrypted SSL private key
- `deployer/apex.pem` - SSL certificate

The script uses `age` for encryption/decryption of SSL keys.

### Helper Script

`deployer-pg-dump.sh` provides PostgreSQL database backups:
```bash
deployer-pg-dump.sh <backup-dir> <database-url>
```
