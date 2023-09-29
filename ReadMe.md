# Deployer #

A small and simple script to help you install stuff on a server.

It isn't Debian packaging. It isn't Docker. It's really just to help me, a little bit.

## Packages #

```
sudo apt-get install      \
  libmodern-perl-perl     \
  libconfig-simple-perl   \
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
  (c) using the Tailscale Authentication for Nginx mod
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

(Ends)
