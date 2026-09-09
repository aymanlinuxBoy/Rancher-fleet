# Vault Setup Guide - Cross-Cluster Secrets

This guide walks through setting up HashiCorp Vault on the upstream cluster and configuring External Secrets on the downstream cluster for secret synchronization.

## Architecture

```
Upstream Cluster (Rancher)
├── Vault (dev mode)
│   ├── K/V v2 Engine: secret/
│   ├── AppRole Auth: downstream-cluster
│   └── Policy: downstream-policy

Downstream Cluster (Workload)
├── External Secrets Operator
├── ClusterSecretStore (→ upstream Vault)
└── ExternalSecrets (fetch & sync)
```

## Prerequisites

- ✅ Both clusters deployed and registered in Rancher
- ✅ Vault bundle deployed to upstream cluster
- ✅ External Secrets Operator bundle deployed to downstream cluster
- ✅ MetalLB and Nginx Ingress Controller deployed (for communication)

## Step 1: Verify Vault Deployment

### Check Vault pod

```bash
# On upstream cluster
kubectl get pod -n vault

# Expected output:
# NAME    READY   STATUS    RESTARTS   AGE
# vault-0   1/1     Running   0          5m
```

### Access Vault UI (dev mode)

```bash
# Port-forward
kubectl -n vault port-forward svc/vault 8200:8200 &

# Open browser
open http://localhost:8200

# Login with token: root-token-poc (from fleet.yaml)
```

## Step 2: Setup AppRole Authentication

### Run setup script

```bash
cd fleet-base-apps/scripts
chmod +x vault-setup.sh

# Run with default settings
./vault-setup.sh

# Or customize
export VAULT_POD_NAME=vault-0
export VAULT_NAMESPACE=vault
export APPROLE_NAME=downstream-cluster
export DOWNSTREAM_NAMESPACE=external-secrets-system
./vault-setup.sh
```

### Script output

The script will:
1. Enable AppRole auth method
2. Create a policy named `downstream-policy`
3. Create an AppRole named `downstream-cluster`
4. Generate Role ID and Secret ID
5. Create K8s Secret in downstream cluster
6. Save credentials to `vault-credentials.txt`

**Keep vault-credentials.txt safe!** It contains sensitive credentials.

### Manual setup (if not using script)

```bash
# 1. Enable AppRole
kubectl -n vault exec vault-0 -- vault auth enable approle

# 2. Create policy
kubectl -n vault exec vault-0 -- vault policy write downstream-policy - <<'EOF'
path "secret/data/downstream/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/downstream/*" {
  capabilities = ["read", "list"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOF

# 3. Create AppRole
kubectl -n vault exec vault-0 -- vault write auth/approle/role/downstream-cluster \
  token_ttl=1h \
  token_max_ttl=24h \
  policies="downstream-policy" \
  bind_secret_id=true \
  secret_id_ttl=24h

# 4. Get Role ID
kubectl -n vault exec vault-0 -- vault read -field=role_id auth/approle/role/downstream-cluster/role-id

# 5. Generate Secret ID
kubectl -n vault exec vault-0 -- vault write -field=secret_id -f auth/approle/role/downstream-cluster/secret-id

# 6. Create secret in downstream cluster
kubectl -n external-secrets-system create secret generic vault-approle-creds \
  --from-literal=role-id=<ROLE_ID> \
  --from-literal=secret-id=<SECRET_ID>
```

## Step 3: Create Test Secret in Vault

```bash
# On upstream cluster, create a test secret
kubectl -n vault exec vault-0 -- vault kv put secret/downstream/db-creds \
  username=testuser \
  password=testpass123

# Verify it was created
kubectl -n vault exec vault-0 -- vault kv get secret/downstream/db-creds
```

## Step 4: Deploy ClusterSecretStore to Downstream

```bash
# Switch to downstream cluster context
kubectl config use-context <downstream-context>

# Apply ClusterSecretStore
kubectl apply -f manifests/clustersecretstore.yaml

# Verify
kubectl get clustersecretstore vault-backend
```

## Step 5: Create ExternalSecret for Testing

```bash
# Apply test ExternalSecret
kubectl apply -f manifests/externalsecret-examples.yaml

# Or create a simple test:
kubectl apply -f - <<'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: vault-test
  namespace: default
spec:
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore

  target:
    name: vault-test-secret
    creationPolicy: Owner

  data:
    - secretKey: username
      remoteRef:
        key: downstream/db-creds
        property: username
    - secretKey: password
      remoteRef:
        key: downstream/db-creds
        property: password

  refreshInterval: 1h
EOF
```

## Step 6: Verify Sync

```bash
# Check ExternalSecret status
kubectl describe externalsecret vault-test

# Should show:
# Status:
#   Conditions:
#   - Type: Ready
#     Status: True

# Verify the K8s secret was created
kubectl get secret vault-test-secret

# Read the synced data
kubectl get secret vault-test-secret -o jsonpath='{.data.username}' | base64 -d
# Expected output: testuser
```

## Using Synced Secrets in Pods

### Mount as file

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-secrets
spec:
  containers:
  - name: app
    image: myapp:latest
    volumeMounts:
    - name: secrets
      mountPath: /etc/secrets
      readOnly: true
  volumes:
  - name: secrets
    secret:
      secretName: vault-test-secret

# Inside container:
# cat /etc/secrets/username  # testuser
# cat /etc/secrets/password  # testpass123
```

### Use as environment variables

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-env
spec:
  containers:
  - name: app
    image: myapp:latest
    env:
    - name: DB_USER
      valueFrom:
        secretKeyRef:
          name: vault-test-secret
          key: username
    - name: DB_PASS
      valueFrom:
        secretKeyRef:
          name: vault-test-secret
          key: password
```

## Creating Application Secrets

### Database credentials

```bash
# In Vault (upstream cluster)
kubectl -n vault exec vault-0 -- vault kv put secret/downstream/myapp/db \
  host=postgres.default.svc.cluster.local \
  port=5432 \
  user=appuser \
  password=app_secure_password
```

```yaml
# ExternalSecret (downstream cluster)
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-db
  namespace: default
spec:
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore

  target:
    name: myapp-db-secret

  data:
    - secretKey: host
      remoteRef:
        key: downstream/myapp/db
        property: host
    - secretKey: port
      remoteRef:
        key: downstream/myapp/db
        property: port
    - secretKey: user
      remoteRef:
        key: downstream/myapp/db
        property: user
    - secretKey: password
      remoteRef:
        key: downstream/myapp/db
        property: password
```

### API Keys

```bash
# In Vault
kubectl -n vault exec vault-0 -- vault kv put secret/downstream/myapp/api \
  key=sk_live_1234567890abcdef \
  secret=sk_secret_fedcba0987654321
```

```yaml
# ExternalSecret
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-api
  namespace: default
spec:
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore

  target:
    name: myapp-api-secret

  data:
    - secretKey: api-key
      remoteRef:
        key: downstream/myapp/api
        property: key
    - secretKey: api-secret
      remoteRef:
        key: downstream/myapp/api
        property: secret
```

## Troubleshooting

### ExternalSecret shows "Failed to sync"

```bash
# Check ExternalSecret logs
kubectl describe externalsecret myapp-db

# Check External Secrets Operator logs
kubectl logs -n external-secrets-system -l app=external-secrets

# Common issues:
# 1. ClusterSecretStore not found
# 2. Vault credentials invalid
# 3. Vault path doesn't exist
# 4. Network connectivity issue
```

### Can't reach Vault from downstream cluster

```bash
# Test connectivity
kubectl run -it --image=curlimages/curl test-curl -- \
  curl -v http://vault.vault.svc.cluster.local:8200/v1/sys/health

# If fails:
# - Check network policies
# - Verify Vault service DNS resolution
# - Check if Vault is listening on port 8200
```

### AppRole authentication fails

```bash
# Regenerate Secret ID
kubectl -n vault exec vault-0 -- vault write -f \
  auth/approle/role/downstream-cluster/secret-id

# Update the K8s secret on downstream
kubectl -n external-secrets-system create secret generic vault-approle-creds \
  --from-literal=role-id=<ROLE_ID> \
  --from-literal=secret-id=<NEW_SECRET_ID> \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart External Secrets pods to pick up new secret
kubectl rollout restart deployment -n external-secrets-system external-secrets-operator
```

### Secret path not found

```bash
# List all secrets in Vault
kubectl -n vault exec vault-0 -- vault kv list secret/downstream

# If path doesn't exist, create it:
kubectl -n vault exec vault-0 -- vault kv put secret/downstream/mypath key=value
```

## Production Considerations

### 1. Switch Vault from Dev Mode to HA

Edit `bundles/vault/fleet.yaml`:

```yaml
server:
  dev:
    enabled: false  # Disable dev mode
  
  ha:
    enabled: true
    replicas: 3
    raft:
      enabled: true

  dataStorage:
    storageClass: longhorn
    size: 50Gi
```

### 2. Use TLS Certificates

```yaml
server:
  ingress:
    enabled: true
    tls:
      - secretName: vault-tls
        hosts:
          - vault.yourdomain.local
```

Cert Manager will auto-issue certificates.

### 3. Backup Encryption Keys

```bash
# Initialize Vault with proper setup
# Store unseal keys securely (not in git!)
# Use external secret storage or HSM
```

### 4. Rotate Secrets Regularly

```bash
# Create a CronJob to rotate secrets
kubectl apply -f - <<'EOF'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: vault-secret-rotator
  namespace: vault
spec:
  schedule: "0 0 * * 0"  # Weekly
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: rotator
            image: vault:latest
            command: ["/bin/sh", "-c"]
            args:
              - |
                vault login -token-only -method=approle \
                  -path=auth/approle \
                  role_id=$ROLE_ID \
                  secret_id=$SECRET_ID
                # Add rotation logic here
          restartPolicy: OnFailure
EOF
```

### 5. Enable Audit Logging

```bash
kubectl -n vault exec vault-0 -- vault audit enable file file_path=/vault/logs/audit.log
```

## Reference

- [Vault Documentation](https://www.vaultproject.io/docs)
- [External Secrets Operator](https://external-secrets.io/)
- [Rancher Fleet GitOps](https://fleet.rancher.io/)
