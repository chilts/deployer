#!/usr/bin/env bash
set -euo pipefail

# deployer-origin-cert-setup.sh
# Sets up Cloudflare Origin Certificate files for deployer.pl

echo "=== Cloudflare Origin Certificate Setup ==="
echo

# Check we're in a directory with deployer/
if [[ ! -d "deployer" ]]; then
    echo "Error: No 'deployer/' directory found. Are you in a webapp directory?"
    exit 1
fi

# Check for existing files
for file in deployer/key.age deployer/apex.pem deployer/apex.key.age; do
    if [[ -f "$file" ]]; then
        echo "Error: $file already exists. Remove it first if you want to regenerate."
        exit 1
    fi
done

# Create temp directory that we'll clean up on exit
TEMP_DIR=$(mktemp -d)
TEMP_IDENTITY="$TEMP_DIR/identity.age"
TEMP_PRIVATE_KEY="$TEMP_DIR/private.key"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Step 1: Generate age identity
echo "Step 1: Generating age identity..."
age-keygen -o "$TEMP_IDENTITY" 2>&1

# Extract public key for encrypting the private key later
PUBLIC_KEY=$(grep "public key:" "$TEMP_IDENTITY" | sed 's/.*public key: //')
echo "Public key: $PUBLIC_KEY"
echo

# Step 2: Encrypt the identity with a passphrase
echo "Step 2: Encrypting the age identity with a passphrase..."
echo "You will be prompted to enter a passphrase (twice)."
echo
age --encrypt --passphrase --armor --output deployer/key.age "$TEMP_IDENTITY"
echo
echo "Created deployer/key.age"
echo

# Step 3: Get the Origin Certificate
echo "Step 3: Paste your Cloudflare Origin Certificate below."
echo "(Starts with -----BEGIN CERTIFICATE-----)"
echo "Press Ctrl+D on a new line when done."
echo
cat > deployer/apex.pem
echo
echo "Created deployer/apex.pem"
echo

# Step 4: Get the private key and encrypt it
echo "Step 4: Paste your Cloudflare Private Key below."
echo "(Starts with -----BEGIN PRIVATE KEY-----)"
echo "Press Ctrl+D on a new line when done."
echo
cat > "$TEMP_PRIVATE_KEY"
echo

# Encrypt the private key with the public key
age --encrypt --recipient "$PUBLIC_KEY" --armor --output deployer/apex.key.age "$TEMP_PRIVATE_KEY"
echo "Created deployer/apex.key.age"
echo

# Ensure deployer/nginx exists
if [[ ! -f "deployer/nginx" ]]; then
    touch deployer/nginx
    echo "Created deployer/nginx (enables nginx configuration)"
fi

echo
echo "=== Setup Complete ==="
echo
echo "Files created:"
echo "  - deployer/key.age       (passphrase-protected age identity)"
echo "  - deployer/apex.pem      (Origin Certificate)"
echo "  - deployer/apex.key.age  (encrypted private key)"
echo
echo "Remember to:"
echo "  1. Add these files to git (they're safe - private key is encrypted)"
echo "  2. Set Cloudflare SSL mode to 'Full (strict)'"
echo "  3. Store your passphrase securely - you'll need it during deployment"
