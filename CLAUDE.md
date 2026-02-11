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
- Perl dependencies: `Modern::Perl`, `File::Slurp`, `IPC::Run3`, `JSON::Any`

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
10. Generate nginx config and restart (if `deployer/nginx` exists)

### Required Environment Variables

Projects must define in `deployer/env`:
- `APEX` - domain name
- `PORT` - application port
- `WWW` - whether to add www redirect (0 or 1)
- `CMD` - command to run the application (must not use `npm`, see below)

### CMD and Signal Forwarding

**Important:** The `CMD` must not use `npm` (e.g., `npm start`). Use a direct command like `node server.js` instead.

**Why:** npm doesn't forward signals to child processes. When supervisor sends SIGTERM to stop or restart the app, npm receives the signal but the node process it spawned keeps running. The orphaned node process gets reparented to PID 1 and continues holding the port, causing `EADDRINUSE` errors on the next restart.

**Examples:**
```bash
# Bad - causes orphaned processes
CMD=npm start

# Good - supervisor can properly manage the process
CMD=node server.js
CMD=node src/index.js
```

The deployer will warn and re-prompt if you enter a CMD containing `npm`.

### Optional Environment Variables

- `NGINX_CLIENT_MAX_BODY_SIZE` - nginx client_max_body_size (default: 25M, e.g., 10M, 100K, 1G)

### SSL Certificate Handling

For Cloudflare Origin Certificates, the project needs:
- `deployer/key.age` - passphrase-protected age identity
- `deployer/apex.key.age` - SSL private key encrypted with the age identity
- `deployer/apex.pem` - SSL certificate (public)

Use `deployer-origin-cert-setup.sh` to create these files interactively. During deployment, the user will be prompted for the passphrase to decrypt the age identity.

### PostgreSQL Database Backups

To enable automatic daily database backups, create an empty `deployer/pg-dump` file:
```bash
touch deployer/pg-dump
```

When this file exists, these additional environment variables are required in `deployer/env`:
- `DATABASE_URL` - PostgreSQL connection string (e.g., `postgres://user@localhost/dbname`)
- `DEPLOYER_BACKUP_DIR` - Base directory for backups (e.g., `/home/chilts/Data/Backup`)

The deployer will:
1. Create the backup directory at `$DEPLOYER_BACKUP_DIR/database/$NAME`
2. Install a cron job at `/etc/cron.d/deployer-pg-dump--$SAFE_NAME` that runs daily at 1am
3. Use `deployer-pg-dump.sh` to perform the backup

### Supervisor Graceful Shutdown

The deployer configures supervisor for graceful shutdown:
- `stopsignal = TERM` - Sends SIGTERM to stop process
- `stopwaitsecs = 30` - Waits 30 seconds before SIGKILL
- `startsecs = 5` - Process must run 5 seconds to be "started"

Applications should handle SIGTERM to finish in-flight requests:
```javascript
// Node.js example
process.on('SIGTERM', () => {
  server.close(() => process.exit(0));
});
```

### Nginx Configuration

To enable nginx configuration, create an empty `deployer/nginx` file:
```bash
touch deployer/nginx
```

The deployer will generate an nginx config at `/etc/nginx/sites-available/$APEX.conf` and symlink it to sites-enabled. The config type depends on SSL setup:
- **CertBot mode** (default): HTTP server with proxy to app
- **Origin Cert mode**: HTTPS server with HTTP redirect

### Static File Serving

When `deployer/nginx` exists, you can also enable static file serving. Create a `deployer/nginx-static` file containing the directory name:

```bash
echo "static" > deployer/nginx-static
```

This configures nginx to:
1. Try serving files from `./static/` at the root URL (e.g., `static/favicon.ico` → `/favicon.ico`)
2. Fall back to proxying to the app if no static file exists
3. Add caching headers (7 day expiry, Cache-Control: public, immutable)
4. Enable gzip compression for text-based assets

### Helper Scripts

`deployer-origin-cert-setup.sh` sets up Cloudflare Origin Certificate files:
```bash
~/bin/deployer-origin-cert-setup.sh
```
Run from within a webapp directory. It generates the age identity, prompts for the certificate and private key, and creates the encrypted files.

`deployer-origin-cert-check.sh` validates the origin certificate files can be decrypted:
```bash
~/bin/deployer-origin-cert-check.sh
```
Run from within a webapp directory to verify the passphrase works and files are valid.

`deployer-pg-dump.sh` provides PostgreSQL database backups:
```bash
deployer-pg-dump.sh <backup-dir> <database-url>
```
