#!/usr/bin/env bash
set -euo pipefail

# deployer-domain-setup.sh
# Sets up Cloudflare Origin Certificate files for a custom domain

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <domain>"
    echo
    echo "Example: $0 example.com"
    exit 1
fi

DOMAIN="$1"

# Validate domain name
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\.\-]*[a-zA-Z0-9])?$ ]] || [[ "$DOMAIN" == *..* ]]; then
    echo "Error: Invalid domain name '$DOMAIN'."
    echo "Only alphanumeric characters, hyphens, and dots are allowed."
    exit 1
fi

echo "=== Custom Domain Certificate Setup ==="
echo "Domain: $DOMAIN"
echo

# Check we're in a directory with deployer/
if [[ ! -d "deployer" ]]; then
    echo "Error: No 'deployer/' directory found. Are you in a webapp directory?"
    exit 1
fi

# Create deployer/domains/ if it doesn't exist
mkdir -p "deployer/domains"

# Check if domain already exists
if [[ -d "deployer/domains/$DOMAIN" ]]; then
    echo "Error: deployer/domains/$DOMAIN/ already exists."
    echo "Remove it first if you want to regenerate:"
    echo "  rm -rf deployer/domains/$DOMAIN"
    exit 1
fi

# Create temp directory that we'll clean up on exit
TEMP_DIR=$(mktemp -d)
TEMP_IDENTITY="$TEMP_DIR/identity.age"
TEMP_PRIVATE_KEY="$TEMP_DIR/private.key"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Step 1: Handle age identity
if [[ ! -f "deployer/domains/key.age" ]]; then
    echo "Step 1: Generating age identity for custom domains..."
    echo "(This identity will be shared across all custom domains)"
    echo
    age-keygen -o "$TEMP_IDENTITY" 2>&1

    # Extract public key for encrypting the private key later
    PUBLIC_KEY=$(grep "public key:" "$TEMP_IDENTITY" | sed 's/.*public key: //')
    echo "Public key: $PUBLIC_KEY"
    echo

    echo "Step 2: Encrypting the age identity with a passphrase..."
    echo "You will be prompted to enter a passphrase (twice)."
    echo
    age --encrypt --passphrase --armor --output deployer/domains/key.age "$TEMP_IDENTITY"
    echo
    echo "Created deployer/domains/key.age"
    echo
else
    echo "Step 1: Using existing age identity (deployer/domains/key.age)"
    echo "Decrypting to extract public key (passphrase required)..."
    echo
    age --decrypt --output "$TEMP_IDENTITY" deployer/domains/key.age
    PUBLIC_KEY=$(grep "public key:" "$TEMP_IDENTITY" | sed 's/.*public key: //')
    echo "Public key: $PUBLIC_KEY"
    echo
fi

# Create domain directory
mkdir -p "deployer/domains/$DOMAIN"

# Step 3: Get the Origin Certificate
echo "Step 3: Paste your Cloudflare Origin Certificate below."
echo "(Starts with -----BEGIN CERTIFICATE-----)"
echo "Press Ctrl+D on a new line when done."
echo
cat > "deployer/domains/$DOMAIN/cert.pem"
echo
echo "Created deployer/domains/$DOMAIN/cert.pem"
echo

# Step 4: Get the private key and encrypt it
echo "Step 4: Paste your Cloudflare Private Key below."
echo "(Starts with -----BEGIN PRIVATE KEY-----)"
echo "Press Ctrl+D on a new line when done."
echo
cat > "$TEMP_PRIVATE_KEY"
echo

# Encrypt the private key with the public key
age --encrypt --recipient "$PUBLIC_KEY" --armor --output "deployer/domains/$DOMAIN/cert.key.age" "$TEMP_PRIVATE_KEY"
echo "Created deployer/domains/$DOMAIN/cert.key.age"
echo

echo
echo "=== Setup Complete ==="
echo
echo "Files created:"
echo "  - deployer/domains/key.age              (shared passphrase-protected age identity)"
echo "  - deployer/domains/$DOMAIN/cert.pem     (Origin Certificate)"
echo "  - deployer/domains/$DOMAIN/cert.key.age (encrypted private key)"
echo
echo "Next steps:"
echo "  1. Add these files to git (they're safe - private key is encrypted)"
echo "  2. Set Cloudflare SSL mode to 'Full (strict)' for this domain"
echo "  3. Point the domain's DNS to this server (via Cloudflare)"
echo "  4. Run: ~/bin/deployer-domains.pl $DOMAIN"
echo "  5. Store your passphrase securely - you'll need it during deployment"
