# ToDo.md

## Bugs

### Critical

- [x] **Nginx config naming mismatch** - In the nginx config generation block (CertBot path), the existence check looks for `$name.conf` but the config is saved as `$apex.conf`. This causes the check to always fail if directory name differs from apex domain.

- [x] **PNG/JPG minification variable interpolation** - In the minify block, the curl commands use `\@filename.png` instead of `\@$filename.png`, causing the variable to not be interpolated. Minification of images will fail silently.

### High

- [x] **Supervisor log directory mismatch** - The log directory creation creates `/var/log/$name/` but the supervisor config references `/var/log/supervisor/$name/`. Supervisor logs may fail to write.

- [x] **Command injection via APEX variable** - The `$apex` variable from `deployer/env` is interpolated into shell commands in the SSL and nginx blocks without shell quoting. A malicious APEX value could execute arbitrary commands.

- [x] **Command injection via minify filenames** - Filenames from `deployer/minify` are passed to curl commands unquoted. Filenames with shell metacharacters could execute arbitrary commands.

### Medium

- [x] **WWW variable coercion** - Using `($env->{WWW}+0)` for boolean coercion means strings like "yes" or "true" coerce to 0 instead of 1, unexpectedly disabling www redirect.

- [x] **Port validation missing** - The PORT environment variable is never validated as numeric. Non-numeric values will cause nginx config syntax errors.

- [x] **safe_name incomplete sanitization** - The safe_name regex only converts dots to dashes. Other problematic characters (spaces, quotes, slashes) are not sanitized and could break cron/supervisor filenames.

---

## Security Issues

### Critical

- [ ] **Environment variables logged to stdout** - In the env loading section, all environment variables including secrets (DATABASE_URL, API keys) are printed with `msg(" - $k=$v")`. These appear in terminal history and logs.

- [x] **DATABASE_URL in world-readable cron file** - The pg-dump cron job contains the full DATABASE_URL in `/etc/cron.d/deployer-pg-dump--*` which is world-readable by default (644 permissions).

- [ ] **Secrets in world-readable supervisor config** - All environment variables including secrets are written to `/etc/supervisor/conf.d/$name.conf` with default world-readable permissions.

### High

- [ ] **Decrypted SSL key on disk** - The age decryption block writes the decrypted private key to `deployer/apex.key` before copying to `/etc/ssl/private/`. If script fails before cleanup, the unencrypted key remains exposed.

- [ ] **Package names not validated** - In the package check block, package names from `deployer/packages` are passed to dpkg-query without validation. Malicious package names could execute commands.

- [ ] **Path traversal in dirs** - The `read_file_and_sub_env()` function doesn't validate paths from `deployer/dirs`. Directory traversal sequences could create directories outside intended locations.

- [ ] **Temp files may be world-readable** - File::Temp creates files with umask-determined permissions. Before writing secrets, temp files may be readable by other users.

### Medium

- [ ] **Source code sent to external services** - The minify block sends CSS/JS source to cssminifier.com and javascript-minifier.com. These third parties could log application source code.

- [ ] **No HTTPS certificate verification** - The curl calls for minification don't specify certificate verification options. MITM attacks could inject malicious code.

---

## Additional Ideas for Existing Features

### Git Operations

- [ ] **Git rebase safety** - Check for uncommitted changes before running `git fetch` and `git rebase`. Currently risks losing local work.

- [ ] **Better git error handling** - If rebase fails, provide instructions for recovery instead of leaving repository in REBASING state.

### Environment Variables

- [ ] **Mask secrets in output** - Don't log full values for sensitive variables (DATABASE_URL, *_KEY, *_SECRET, *_PASSWORD, *_TOKEN).

- [ ] **Validate required variables early** - Validate APEX/PORT/WWW/CMD format before proceeding with deployment.

- [x] **PORT validation** - Ensure PORT is numeric and in valid range (1-65535).

- [x] **WWW validation** - Ensure WWW is explicitly 0 or 1, reject other values.

### Minification

- [ ] **Local minification option** - Support local tools (terser, csso, pngcrush) as alternative to internet-dependent external services.

- [ ] **Minification error handling** - Verify curl returns success and output is valid before overwriting original with minified version.

- [ ] **Configurable minification** - Allow disabling minification or selecting which file types to minify.

### Nginx Configuration

- [ ] **Nginx syntax validation** - Run `nginx -t` before applying config to catch errors early.

- [ ] **Verify nginx reload** - Check that `systemctl reload nginx` succeeds before continuing.

- [ ] **Configurable client_max_body_size** - Allow setting from deployer/env instead of hardcoded 25M.

- [ ] **WebSocket support** - Add proper proxy headers for WebSocket connections (Upgrade, Connection headers).

- [ ] **HTTP/2 support** - Enable HTTP/2 for HTTPS connections.

- [ ] **Custom nginx directives** - Support `deployer/nginx-extra` file for additional nginx config directives.

### Supervisor Configuration

- [ ] **Configurable supervisor settings** - Allow customizing from deployer/env:
  - `SUPERVISOR_START_RETRIES` (default: 3)
  - `SUPERVISOR_LOG_MAXBYTES` (default: 50MB)
  - `SUPERVISOR_LOG_BACKUPS` (default: 20)

- [ ] **Remove NODE_ENV hardcode** - Either remove hardcoded `NODE_ENV=production` or make it configurable.

- [ ] **Multi-process support** - Support running multiple processes from single deployer/supervisor file.

- [ ] **Verify supervisor reload** - Check that `supervisorctl reread` and `supervisorctl update` succeed.

### SSL/Certificates

- [ ] **Secure age decryption** - Use pipe or process substitution instead of writing decrypted key to disk.

- [ ] **Set permissions on temp file before writing SSL key** - Ensure temp file is not world-readable.

- [ ] **Certificate expiration monitoring** - Add helper script to check certificate expiry dates.

- [ ] **CertBot automation** - Create `deployer-certbot-renew.sh` helper for certificate renewal.

### PostgreSQL Backups

- [ ] **Backup compression** - Compress backups with gzip (produces `.sql.gz` files).

- [ ] **Backup rotation** - Create `deployer-backup-cleanup.sh` to remove backups older than N days.

- [ ] **Backup verification** - Verify pg_dump succeeded before considering backup complete.

- [ ] **Configurable backup time** - Allow setting cron time from deployer/env instead of hardcoded 1am.

- [ ] **Backup notifications** - Optional email/webhook notification on backup success/failure.

### Cron Jobs

- [ ] **Set explicit permissions** - chmod 640 on cron files to prevent world-readable secrets.

- [ ] **Cron syntax validation** - Validate cron file syntax before installing.

### Error Handling

- [ ] **Cleanup on failure** - Remove partial configs (nginx, supervisor, cron) if deployment fails mid-way.

- [ ] **Timeout protection** - Add timeouts to IPC::Run3 commands to prevent hanging.

- [ ] **Better error messages** - Include which step failed and recovery suggestions.

---

## New Features

### Deployment Lifecycle

- [ ] **Pre-deployment hooks** - Run `deployer/pre-deploy` script before git operations.

- [ ] **Post-deployment hooks** - Run `deployer/post-deploy` script after successful deployment.

- [ ] **Health checks** - Run `deployer/health-check` script and verify app responds before considering deployment complete.

- [ ] **Rollback capability** - Create `deployer-rollback.sh` to quickly revert to previous git state and configs.

- [ ] **Deployment audit log** - Write deployment history to log file with timestamp, user, git SHA.

### Database

- [ ] **Database migrations** - Run `deployer/migrate` script after code update but before service restart.

- [ ] **Migration verification** - Check migration succeeded before proceeding with deployment.

### Service Management

- [ ] **Systemd support** - Alternative to supervisor using systemd service files.

- [ ] **Zero-downtime restart** - Use supervisor's `restart` with proper signal handling for graceful shutdown.

- [ ] **Multiple service support** - Support multiple supervisor programs from `deployer/supervisor.d/` directory.

### Static Files

- [x] **Static file serving** - Generate nginx location blocks for static files with caching headers.

- [ ] **Asset versioning** - Support content-hash based asset filenames for cache busting.

### Monitoring

- [ ] **Application health endpoint** - Configure nginx to proxy `/health` endpoint.

- [ ] **Service status check** - Add `deployer-status.sh` to check if all services are running.

- [ ] **Log viewing helper** - Add `deployer-logs.sh` to tail application logs.

### Configuration

- [ ] **Dry-run mode** - Show what would be done without making changes.

- [ ] **Verbose mode** - More detailed output for debugging deployment issues.

- [ ] **Config validation** - Validate all deployer/* files before starting deployment.

### Helper Scripts

- [ ] **deployer-backup-cleanup.sh** - Rotate/compress old database backups.

- [ ] **deployer-health-check.sh** - Verify services after deployment.

- [ ] **deployer-rollback.sh** - Quick rollback to previous git state.

- [ ] **deployer-certificate-renew.sh** - CertBot automation helper.

- [ ] **deployer-logs.sh** - Centralized log viewing.

- [ ] **deployer-validate-config.sh** - Pre-deployment configuration validation.

- [ ] **deployer-secrets-encrypt.sh** - Helper to encrypt new secrets with age.

- [ ] **deployer-status.sh** - Show status of deployed application.

---

## Deferred

Items too complex for current scope or represent significant architectural changes:

- [ ] **Docker/container support** - Would require fundamental redesign; deployer assumes bare-metal/VM.

- [ ] **Multi-server orchestration** - Coordinated deployments across server fleet; out of scope for single-server tool.

- [ ] **Blue-green deployments** - Requires load balancer and multiple instances; architectural change.

- [ ] **Full secrets manager integration** - HashiCorp Vault or similar; current age-based approach is sufficient for most cases.

- [ ] **Kubernetes integration** - Different deployment paradigm entirely.

- [ ] **CI/CD pipeline integration** - Hooks for GitHub Actions, GitLab CI, etc.; can be done by caller.

- [ ] **Multiple nginx upstreams** - Load balancing between multiple app instances; use external LB.

- [ ] **CDN integration** - Static asset CDN deployment; handle separately from app deployment.
