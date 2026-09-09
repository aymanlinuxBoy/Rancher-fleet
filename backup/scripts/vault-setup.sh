#!/bin/bash
# Vault AppRole Setup Script
# This script sets up Vault AppRole authentication for downstream cluster
# Run this ONCE after Vault is deployed on the upstream cluster

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
VAULT_POD_NAME="${VAULT_POD_NAME:-vault-0}"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"
VAULT_ADDR="${VAULT_ADDR:-http://vault.vault.svc.cluster.local:8200}"
APPROLE_NAME="${APPROLE_NAME:-downstream-cluster}"
DOWNSTREAM_NAMESPACE="${DOWNSTREAM_NAMESPACE:-external-secrets-system}"

echo -e "${GREEN}========================================${NC}"
echo "Setting up Vault AppRole for downstream cluster"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if Vault pod is running
echo -e "${YELLOW}1. Checking Vault pod status...${NC}"
if ! kubectl -n $VAULT_NAMESPACE get pod $VAULT_POD_NAME &>/dev/null; then
    echo -e "${RED}ERROR: Vault pod not found in namespace $VAULT_NAMESPACE${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Vault pod found${NC}"
echo ""

# Enable AppRole auth method
echo -e "${YELLOW}2. Enabling AppRole auth method...${NC}"
if kubectl -n $VAULT_NAMESPACE exec $VAULT_POD_NAME -- vault auth list | grep -q "approle/"; then
    echo -e "${GREEN}✓ AppRole already enabled${NC}"
else
    kubectl -n $VAULT_NAMESPACE exec $VAULT_POD_NAME -- vault auth enable approle
    echo -e "${GREEN}✓ AppRole enabled${NC}"
fi
echo ""

# Create policy
echo -e "${YELLOW}3. Creating downstream policy...${NC}"
kubectl -n $VAULT_NAMESPACE exec $VAULT_POD_NAME -- vault policy write downstream-policy - <<'EOF'
# Policy for downstream cluster to read secrets
path "secret/data/downstream/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/downstream/*" {
  capabilities = ["read", "list"]
}

# Allow token self-renewal
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOF
echo -e "${GREEN}✓ Policy created${NC}"
echo ""

# Create AppRole
echo -e "${YELLOW}4. Creating AppRole: $APPROLE_NAME...${NC}"
kubectl -n $VAULT_NAMESPACE exec $VAULT_POD_NAME -- vault write auth/approle/role/$APPROLE_NAME \
  token_ttl=1h \
  token_max_ttl=24h \
  policies="downstream-policy" \
  bind_secret_id=true \
  secret_id_ttl=24h
echo -e "${GREEN}✓ AppRole created${NC}"
echo ""

# Get Role ID
echo -e "${YELLOW}5. Retrieving Role ID...${NC}"
ROLE_ID=$(kubectl -n $VAULT_NAMESPACE exec $VAULT_POD_NAME -- vault read -field=role_id auth/approle/role/$APPROLE_NAME/role-id)
echo -e "${GREEN}✓ Role ID: $ROLE_ID${NC}"
echo ""

# Generate Secret ID
echo -e "${YELLOW}6. Generating Secret ID...${NC}"
SECRET_ID=$(kubectl -n $VAULT_NAMESPACE exec $VAULT_POD_NAME -- vault write -field=secret_id -f auth/approle/role/$APPROLE_NAME/secret-id)
echo -e "${GREEN}✓ Secret ID: $SECRET_ID${NC}"
echo ""

# Create the secret in downstream cluster
echo -e "${YELLOW}7. Creating AppRole credentials secret in downstream cluster...${NC}"
kubectl -n $DOWNSTREAM_NAMESPACE create secret generic vault-approle-creds \
  --from-literal=role-id=$ROLE_ID \
  --from-literal=secret-id=$SECRET_ID \
  --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Secret created in downstream cluster${NC}"
echo ""

# Verify the setup
echo -e "${YELLOW}8. Verifying AppRole setup...${NC}"
kubectl -n $VAULT_NAMESPACE exec $VAULT_POD_NAME -- vault read auth/approle/role/$APPROLE_NAME
echo -e "${GREEN}✓ Verification complete${NC}"
echo ""

# Save to file
echo -e "${YELLOW}9. Saving credentials to vault-credentials.txt...${NC}"
cat > vault-credentials.txt <<EOF
===========================================
Vault AppRole Credentials
===========================================
Created: $(date)
AppRole Name: $APPROLE_NAME

Role ID:
$ROLE_ID

Secret ID:
$SECRET_ID

Vault Address (upstream cluster):
$VAULT_ADDR

Vault Service Address (cross-cluster):
http://vault.vault.svc.cluster.local:8200

Next Steps:
1. Deploy ClusterSecretStore to downstream cluster
2. Create ExternalSecret manifests in downstream cluster

IMPORTANT: Keep these credentials secure!
===========================================
EOF
echo -e "${GREEN}✓ Credentials saved to vault-credentials.txt${NC}"
echo ""

echo -e "${GREEN}========================================${NC}"
echo "✅ Vault AppRole Setup Complete!"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo "1. Review vault-credentials.txt"
echo "2. Apply ClusterSecretStore to downstream cluster:"
echo "   kubectl apply -f manifests/clustersecretstore.yaml"
echo "3. Create ExternalSecret manifests for your apps"
echo ""
