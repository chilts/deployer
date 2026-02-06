#!/usr/bin/env bash
set -euo pipefail

# deployer-origin-cert-check.sh
# Validates that the Cloudflare Origin Certificate files can be decrypted

echo "=== Cloudflare Origin Certificate Check ==="
echo

# Check we're in a directory with deployer/
if [[ ! -d "deployer" ]]; then
    echo "Error: No 'deployer/' directory found. Are you in a webapp directory?"
    exit 1
fi

# Check required files exist
MISSING=0
for file in deployer/key.age deployer/apex.pem deployer/apex.key.age; do
    if [[ ! -f "$file" ]]; then
        echo "Missing: $file"
        MISSING=1
    else
        echo "Found: $file"
    fi
done

if [[ $MISSING -eq 1 ]]; then
    echo
    echo "Error: Missing required files. Run deployer-origin-cert-setup.sh first."
    exit 1
fi

echo

# Decrypt the private key using the passphrase-protected identity (output to /dev/null)
echo "Decrypting private key (passphrase required)..."
if ! age --decrypt --identity deployer/key.age --output /dev/null deployer/apex.key.age; then
    echo
    echo "Error: Failed to decrypt deployer/apex.key.age"
    exit 1
fi
echo "OK: deployer/apex.key.age decrypted successfully"

echo
echo "=== All checks passed ==="
