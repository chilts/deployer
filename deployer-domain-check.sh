#!/usr/bin/env bash
set -euo pipefail

# deployer-domain-check.sh
# Validates that custom domain certificate files can be decrypted

echo "=== Custom Domain Certificate Check ==="
echo

# Check we're in a directory with deployer/
if [[ ! -d "deployer" ]]; then
    echo "Error: No 'deployer/' directory found. Are you in a webapp directory?"
    exit 1
fi

if [[ ! -d "deployer/domains" ]]; then
    echo "Error: No 'deployer/domains/' directory found."
    echo "Run deployer-domain-setup.sh <domain> to add a custom domain."
    exit 1
fi

if [[ ! -f "deployer/domains/key.age" ]]; then
    echo "Error: No 'deployer/domains/key.age' found."
    echo "Run deployer-domain-setup.sh <domain> to set up the age identity."
    exit 1
fi

echo "Found: deployer/domains/key.age"

# Determine which domains to check
DOMAINS=()
if [[ $# -gt 0 ]]; then
    # Specific domains from arguments
    for DOMAIN in "$@"; do
        if [[ ! -d "deployer/domains/$DOMAIN" ]]; then
            echo "Error: No directory 'deployer/domains/$DOMAIN/' found."
            exit 1
        fi
        DOMAINS+=("$DOMAIN")
    done
else
    # All domains
    for DIR in deployer/domains/*/; do
        if [[ -d "$DIR" ]]; then
            DOMAIN=$(basename "$DIR")
            DOMAINS+=("$DOMAIN")
        fi
    done
fi

if [[ ${#DOMAINS[@]} -eq 0 ]]; then
    echo "No custom domains found in deployer/domains/."
    exit 1
fi

echo "Domains to check: ${DOMAINS[*]}"
echo

# Decrypt identity to temp file (one passphrase prompt)
TEMP_DIR=$(mktemp -d)
TEMP_IDENTITY="$TEMP_DIR/identity.age"
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "Decrypting age identity (passphrase required)..."
if ! age --decrypt --output "$TEMP_IDENTITY" deployer/domains/key.age; then
    echo
    echo "Error: Failed to decrypt deployer/domains/key.age"
    exit 1
fi
echo "OK: deployer/domains/key.age decrypted successfully"
echo

# Check each domain
FAILED=0
for DOMAIN in "${DOMAINS[@]}"; do
    echo "--- $DOMAIN ---"

    if [[ ! -f "deployer/domains/$DOMAIN/cert.pem" ]]; then
        echo "  Missing: deployer/domains/$DOMAIN/cert.pem"
        FAILED=1
        continue
    fi
    echo "  Found: cert.pem"

    if [[ ! -f "deployer/domains/$DOMAIN/cert.key.age" ]]; then
        echo "  Missing: deployer/domains/$DOMAIN/cert.key.age"
        FAILED=1
        continue
    fi
    echo "  Found: cert.key.age"

    if ! age --decrypt --identity "$TEMP_IDENTITY" --output /dev/null "deployer/domains/$DOMAIN/cert.key.age"; then
        echo "  Error: Failed to decrypt cert.key.age"
        FAILED=1
        continue
    fi
    echo "  OK: cert.key.age decrypted successfully"
    echo
done

if [[ $FAILED -eq 1 ]]; then
    echo "=== Some checks failed ==="
    exit 1
fi

echo "=== All checks passed ==="
