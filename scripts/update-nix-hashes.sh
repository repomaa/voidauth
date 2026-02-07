#!/usr/bin/env bash
# Script to automatically update npm dependency hashes in nix/package.nix
# This script can be run locally or in CI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NIX_FILE="${REPO_ROOT}/nix/package.nix"

echo "=== Updating Nix npm dependency hashes ==="
echo ""

# Check if prefetch-npm-deps is available
if ! command -v prefetch-npm-deps &> /dev/null; then
    echo "Error: prefetch-npm-deps not found"
    echo ""
    echo "If you have Nix installed with flakes, run:"
    echo "  nix shell nixpkgs#prefetch-npm-deps"
    echo ""
    echo "Or install Nix: https://nixos.org/download.html"
    exit 1
fi

# Check if we're in a git repo
if [ ! -d "${REPO_ROOT}/.git" ]; then
    echo "Error: Not a git repository"
    exit 1
fi

# Check if there are uncommitted changes to package-lock files
if [ -n "$(git -C "${REPO_ROOT}" status --porcelain package-lock.json frontend/package-lock.json 2>/dev/null)" ]; then
    echo "Warning: Uncommitted changes detected in package-lock.json files"
    echo "This script should be run after package-lock.json changes are committed"
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Step 1: Calculating hash for root package-lock.json..."
ROOT_HASH=$(prefetch-npm-deps "${REPO_ROOT}/package-lock.json")
echo "  New hash: ${ROOT_HASH}"
echo ""

echo "Step 2: Calculating hash for frontend/package-lock.json..."
FRONTEND_HASH=$(prefetch-npm-deps "${REPO_ROOT}/frontend/package-lock.json")
echo "  New hash: ${FRONTEND_HASH}"
echo ""

# Read current hashes to check if update is needed
current_root_hash=$(grep -oP 'npmDepsHash = "\Ksha256-[^"]+' "${NIX_FILE}" || true)
current_frontend_hash=$(grep -oP 'hash = "\Ksha256-[^"]+' "${NIX_FILE}" | head -1 || true)

echo "Current hashes:"
echo "  Root:     ${current_root_hash:-not found}"
echo "  Frontend: ${current_frontend_hash:-not found}"
echo ""

# Check if hashes need updating
if [ "${current_root_hash}" = "${ROOT_HASH}" ] && [ "${current_frontend_hash}" = "${FRONTEND_HASH}" ]; then
    echo "=== Hashes are already up to date! No changes needed. ==="
    exit 0
fi

echo "Step 3: Updating ${NIX_FILE}..."

# Update the npmDepsHash (root) - this is the one on line 53
sed -i "s|npmDepsHash = \"[^\"]*|npmDepsHash = \"${ROOT_HASH}|" "${NIX_FILE}"

# Update the frontendNpmDeps hash - this is on line 45
# The frontend one is in the frontendNpmDeps block
sed -i '/frontendNpmDeps = fetchNpmDeps {/,/};/ s|hash = "[^"]*|hash = "'"${FRONTEND_HASH}|" "${NIX_FILE}"

echo "  ✓ Updated npmDepsHash (root)"
echo "  ✓ Updated frontendNpmDeps hash"
echo ""

# Verify the changes
echo "Step 4: Verifying changes..."
new_root_hash=$(grep -oP 'npmDepsHash = "\Ksha256-[^"]+' "${NIX_FILE}")
new_frontend_hash=$(grep -oP 'hash = "\Ksha256-[^"]+' "${NIX_FILE}" | head -1)

echo "  New root hash:     ${new_root_hash}"
echo "  New frontend hash: ${new_frontend_hash}"
echo ""

if [ "${new_root_hash}" != "${ROOT_HASH}" ] || [ "${new_frontend_hash}" != "${FRONTEND_HASH}" ]; then
    echo "Error: Failed to update hashes correctly"
    exit 1
fi

echo "=== Successfully updated npm dependency hashes! ==="
echo ""
echo "Next steps:"
echo "  1. Review the changes: git diff nix/package.nix"
echo "  2. Commit: git add nix/package.nix && git commit -m 'chore: update npm dependency hashes'"
echo "  3. Push and create a PR"
echo ""
echo "Or if running in CI, the changes will be committed automatically."
