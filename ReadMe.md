# Deployer #

A small and simple script to help you install stuff on a server.

It isn't Debian packaging. It isn't Docker. It's really just to help me, a little bit.

## Scripts at a Glance

### Dev (local machine)

| Script | Summary |
|--------|---------|
| `deployer-setup.sh` | Interactive setup to create the `deployer/` config directory for a new project |
| `deployer-origin-cert-setup.sh` | Create age identity + encrypt Cloudflare Origin Cert files for the apex domain |
| `deployer-origin-cert-check.sh` | Verify the apex Origin Cert files decrypt correctly |
| `deployer-domain-setup.sh` | Add a custom domain's Origin Cert files under `deployer/domains/` |
| `deployer-domain-check.sh` | Verify custom domain cert files decrypt correctly (one or all) |

### Server (production)

| Script | Summary |
|--------|---------|
| `deployer.pl` | Main deployment script: git pull, build, configure supervisor/nginx/SSL/cron |
| `deployer-domains.pl` | Install custom domain certs + generate nginx configs (add or `--remove`) |
| `deployer-pg-dump.sh` | Dump a PostgreSQL database to a backup directory (called by cron) |

## Packages #

```
sudo apt-get install      \
  libmodern-perl-perl     \
  libfile-slurp-perl      \
  libipc-run3-perl        \
  libjson-any-perl        \
  jq
```

## Deployer's Plan

Note that most of these steps are optional except 1-4 which are compulsory.

 1. checks it can get `sudo`
 2. git fetch and rebase
 3. setup:
   * creates "safe_name" from current dir name
   * checks to see if `package.json` exists (then `is_node` is `true`)
 4. reads `deployer/settings` for apex/port/www/cmd
 5. reads `deployer/env`
 6. checks for `deployer/ENV_*` files
 7. installs packages from `deployer/packages` (if exists)
 8. runs `npm ci` as needed
 9. makes the project is a `Makefile` exists (if exists)
10. minifies files in `deployer/minify` (if exists)
11. creates dirs in `deployer/dirs` (if exists)
12. copies `deployer/cron.d` to the right place (if exists)
13. creates a supervisor file to run the server (if exists)
14. creates an Nginx file to be able to proxy through:
  (a) for CertBot
  (b) with a Cloudflare Origin Certificate
15. runs CertBot if asked for

Note: deployer.pl will add the following ENV VARS where needed without them
having to be in `deployer/env`:

* APEX (from `deployer/settings`)
* PORT (from `deployer/settings`)
* NODE_ENV=production (if `is_node`)
* then all env vars in `deployer/env`

## Sample Files

deployer/settings:

```
apex: screenshot.gd
port: 43790
www: 1
```

Any line with a `?` value in `deployer/env` will be prompted for:

```
DATA_DIR: ?
GOOGLE_ANALYTICS: ?
```

## Cloudflare Origin Certificate

To enable full SSL encryption between your origin server and Cloudflare's CDN, you can use a Cloudflare Origin Certificate instead of CertBot.

### Required Files

Create these three files in your webapp's `deployer/` directory:

1. **`deployer/apex.pem`** - The Origin Certificate (public certificate) from Cloudflare
2. **`deployer/apex.key.age`** - The private key, encrypted with [age](https://github.com/FiloSottile/age)
3. **`deployer/key.age`** - Your age identity file used to decrypt the private key

Also ensure `deployer/nginx` exists to enable nginx configuration.

### Setup Steps

The easiest way is to use the setup script:

```bash
~/bin/deployer-origin-cert-setup.sh
```

This will:
1. Generate an age identity and encrypt it with a passphrase
2. Prompt you to paste the Origin Certificate
3. Prompt you to paste the private key (encrypted automatically)
4. Create `deployer/nginx` if needed

#### Manual Setup

If you prefer to set things up manually:

1. **Get the Origin Certificate from Cloudflare**:
   - Go to Cloudflare dashboard → SSL/TLS → Origin Server → Create Certificate
   - Choose your hostnames (e.g., `example.com` and `*.example.com`)
   - Select validity period (up to 15 years)
   - Save the certificate as `deployer/apex.pem`
   - Save the private key to a temporary file

2. **Create an age identity**:
   ```bash
   age-keygen -o /tmp/identity.age
   ```

3. **Encrypt the identity with a passphrase**:
   ```bash
   age --encrypt --passphrase --armor -o deployer/key.age /tmp/identity.age
   ```

4. **Encrypt the private key**:
   ```bash
   PUBLIC_KEY=$(grep "public key:" /tmp/identity.age | sed 's/.*public key: //')
   age --encrypt --recipient "$PUBLIC_KEY" --armor -o deployer/apex.key.age private-key.txt
   rm private-key.txt /tmp/identity.age  # delete unencrypted files
   ```

5. **Ensure nginx is enabled**:
   ```bash
   touch deployer/nginx
   ```

### What Deployer Does

When all three certificate files exist, the deployer will:

1. Copy `apex.pem` to `/etc/ssl/$APEX.pem`
2. Decrypt `apex.key.age` using `key.age` as the identity
3. Copy the key to `/etc/ssl/private/$APEX.key` with secure permissions (640, root:ssl-cert)
4. Delete the temporary decrypted key
5. Generate nginx config with:
   - HTTPS on port 443 using the origin certificate
   - HTTP on port 80 redirecting to HTTPS
   - www subdomain redirecting to apex (if WWW=1)

### Checking Custom Domain Certificates

`deployer-domain-check.sh` verifies that the custom domain certificate setup is correct and that the encrypted private keys can be decrypted. Run it from within a webapp directory:

```bash
~/bin/deployer-domain-check.sh              # check all custom domains
~/bin/deployer-domain-check.sh example.com  # check a specific domain
```

It performs the following checks:

1. `deployer/domains/` directory exists
2. `deployer/domains/key.age` (the shared age identity) exists and can be decrypted with your passphrase
3. For each domain, `cert.pem` (the Origin Certificate) exists
4. For each domain, `cert.key.age` (the encrypted private key) exists and can be decrypted using the age identity

The passphrase is only prompted once — the decrypted identity is held in a temp file (automatically cleaned up) and reused across all domains. The decrypted private keys are discarded to `/dev/null` since we only need to verify decryption succeeds.

If any check fails, the script reports which domain(s) had problems and exits with a non-zero status.

### Custom Domain Scripts: Development vs Production

| Script | Where to run | Purpose |
|--------|-------------|---------|
| `deployer-domain-setup.sh` | Development | Creates encrypted cert files and commits them to the repo |
| `deployer-domain-check.sh` | Development | Verifies cert files decrypt correctly before deploying |
| `deployer-domains.pl` | Production (server) | Installs certs, generates nginx configs, restarts nginx |

**Development** (your local machine): Use `deployer-domain-setup.sh` to add a new domain's certificate files, then `deployer-domain-check.sh` to verify they work. Commit the files to git and push.

**Production** (the server): After pulling the new cert files, run `deployer-domains.pl` to install the certificates and configure nginx. This requires sudo access and writes to `/etc/ssl/`, `/etc/nginx/`, etc.

### Cloudflare SSL Mode

In your Cloudflare dashboard, set the SSL/TLS encryption mode to **Full (strict)** to ensure end-to-end encryption with certificate validation.

(Ends)
