#!/usr/bin/env bash
set -euo pipefail

# deployer-setup.sh
# Interactive setup script for deployer.pl
# Creates the deployer/ directory with configuration files for a webapp

echo "=== Deployer Setup ==="
echo
echo "This will create a deployer/ directory for use with deployer.pl"
echo "Core config (APEX, PORT, WWW, CMD) will be prompted by deployer.pl at deploy time."
echo

# Helper function: prompt yes/no with default
prompt_yes_no() {
    local prompt="$1"
    local default="$2"
    local response

    if [[ "$default" == "y" ]]; then
        read -r -p "$prompt [Y/n]: " response
        response=${response:-y}
    else
        read -r -p "$prompt [y/N]: " response
        response=${response:-n}
    fi

    [[ "$response" =~ ^[Yy] ]]
}

# Helper function: read multiline input until empty line
read_multiline() {
    local lines=()
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && break
        lines+=("$line")
    done
    printf '%s\n' "${lines[@]}"
}

# Check if deployer/ already exists
if [[ -d "deployer" ]]; then
    echo "Warning: deployer/ directory already exists."
    if ! prompt_yes_no "Continue anyway?" "n"; then
        echo "Aborted."
        exit 0
    fi
    echo
else
    mkdir deployer
    echo "Created deployer/ directory"
    echo
fi

# Initialize arrays to track what we create
ENV_VARS=()
MARKER_FILES=()
CONTENT_FILES=()

# Core config (always added with ? for deploy-time prompts)
ENV_VARS+=("APEX=?")
ENV_VARS+=("PORT=?")
ENV_VARS+=("WWW=?")
ENV_VARS+=("CMD=?")

echo "Features"
echo "--------"

# Supervisor
if prompt_yes_no "Enable supervisor?" "y"; then
    MARKER_FILES+=("supervisor")
fi

# Nginx
if prompt_yes_no "Enable nginx?" "y"; then
    MARKER_FILES+=("nginx")

    # Static files (only if nginx enabled)
    if prompt_yes_no "Enable static file serving?" "n"; then
        read -r -p "  Static directory name [static]: " static_dir
        static_dir=${static_dir:-static}
        CONTENT_FILES+=("nginx-static:$static_dir")
    fi
fi

# PostgreSQL backup
if prompt_yes_no "Enable PostgreSQL backups?" "n"; then
    MARKER_FILES+=("pg-dump")
    ENV_VARS+=("DATABASE_URL=?")
    ENV_VARS+=("DEPLOYER_BACKUP_DIR=?")
    echo "  DATABASE_URL and DEPLOYER_BACKUP_DIR will be prompted at deploy time"
fi

# SSL options
if prompt_yes_no "Use Cloudflare Origin Certificate?" "n"; then
    echo "  Running deployer-origin-cert-setup.sh..."
    echo
    # Find the script in the same directory as this script, or in PATH
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    if [[ -x "$SCRIPT_DIR/deployer-origin-cert-setup.sh" ]]; then
        "$SCRIPT_DIR/deployer-origin-cert-setup.sh"
    elif command -v deployer-origin-cert-setup.sh &>/dev/null; then
        deployer-origin-cert-setup.sh
    else
        echo "  Error: deployer-origin-cert-setup.sh not found"
        echo "  You can run it manually later"
    fi
    echo
elif prompt_yes_no "Use CertBot for SSL?" "n"; then
    MARKER_FILES+=("certbot")
fi

# Packages
if prompt_yes_no "Install packages?" "n"; then
    echo "  Example packages:"
    echo "    nginx"
    echo "    supervisor"
    echo "    redis-server"
    echo "    postgresql"
    echo "  Enter packages (one per line, empty line to finish):"
    packages=""
    while IFS= read -r -p "  > " line; do
        [[ -z "$line" ]] && break
        packages+="$line"$'\n'
    done
    if [[ -n "$packages" ]]; then
        CONTENT_FILES+=("packages:${packages%$'\n'}")
    fi
fi

# Directories
if prompt_yes_no "Create directories?" "n"; then
    echo "  Example directories:"
    echo '    /var/cache/$NAME/'
    echo '    /var/log/$NAME/'
    echo '    /var/log/supervisor/$NAME/'
    echo '    /home/chilts/Data/Backup/database/$NAME/'
    echo "  Enter directories (one per line, empty line to finish):"
    dirs=""
    while IFS= read -r -p "  > " line; do
        [[ -z "$line" ]] && break
        dirs+="$line"$'\n'
    done
    if [[ -n "$dirs" ]]; then
        CONTENT_FILES+=("dirs:${dirs%$'\n'}")
    fi
fi

echo
echo "Additional Environment Variables"
echo "---------------------------------"

# SESSION_SECRET
if prompt_yes_no "Add SESSION_SECRET?" "y"; then
    ENV_VARS+=("SESSION_SECRET=?")
fi

# Custom environment variables
if prompt_yes_no "Add custom environment variables?" "n"; then
    echo "  Enter variables as KEY=VALUE or KEY=? (empty line to finish):"
    while IFS= read -r -p "  > " line; do
        [[ -z "$line" ]] && break
        ENV_VARS+=("$line")
    done
fi

echo

# Write the env file
{
    for var in "${ENV_VARS[@]}"; do
        echo "$var"
    done
} > deployer/env
echo "Created deployer/env"

# Write marker files (empty files)
for file in "${MARKER_FILES[@]}"; do
    touch "deployer/$file"
    echo "Created deployer/$file"
done

# Write content files
for entry in "${CONTENT_FILES[@]}"; do
    file="${entry%%:*}"
    content="${entry#*:}"
    echo "$content" > "deployer/$file"
    echo "Created deployer/$file"
done

# Update .gitignore
GITIGNORE_LINE="/deployer/ENV_*"
if [[ -f ".gitignore" ]]; then
    if ! grep -qF "$GITIGNORE_LINE" .gitignore; then
        echo "" >> .gitignore
        echo "$GITIGNORE_LINE" >> .gitignore
        echo "Updated .gitignore with: $GITIGNORE_LINE"
    else
        echo ".gitignore already contains: $GITIGNORE_LINE"
    fi
else
    echo "$GITIGNORE_LINE" > .gitignore
    echo "Created .gitignore with: $GITIGNORE_LINE"
fi

echo
echo "=== Setup Complete ==="
echo
echo "Next steps:"
echo "  1. Review deployer/env"
echo "  2. Commit the deployer/ directory to git"
echo "  3. Run ~/bin/deployer.pl to deploy"
