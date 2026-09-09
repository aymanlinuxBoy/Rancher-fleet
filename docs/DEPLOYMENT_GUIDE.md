# Fleet Base Apps - Deployment Guide

## Prerequisites

- ✅ Upstream cluster (Rancher host) with 3 nodes
- ✅ Downstream cluster (workload) with 3 nodes, registered in Rancher
- ✅ Both clusters have internet access (or air-gapped registries configured)
- ✅ `kubectl` configured to access both clusters
- ✅ Git repository created (GitHub, GitLab, Gitea, etc.)

## Step 1: Setup Git Repository

### Option A: Use GitHub/GitLab

```bash
# Clone this repo or create a new one
git clone https://github.com/your-org/fleet-base-apps.git
cd fleet-base-apps

# Update domain names
sed -i 's/yourdomain.local/your-actual-domain/g' bundles/*/fleet.yaml

# Push to your repository
git add .
git commit -m "Initial Fleet bundles"
git push origin main
```

### Option B: Use Self-Hosted Gitea

```bash
# Create Gitea repository in your Rancher UI or use Gitea API
# Then clone and push like GitHub above
```

## Step 2: Add Git Repo to Rancher Fleet

### Via Rancher UI:

1. Go to **Continuous Delivery** → **Git Repos**
2. Click **Add Repo**
3. Configure:
   - **Name**: `fleet-base-apps`
   - **Repository URL**: `https://github.com/your-org/fleet-base-apps` (or Gitea URL)
   - **Branch**: `main`
   - **Paths**: Leave empty or specify `bundles/`
   - **Git Authentication**: Add credentials if private repo
4. Click **Create**

### Via kubectl (GitRepo manifest):

```bash
kubectl apply -f - <<EOF
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: fleet-base-apps
  namespace: fleet-default
spec:
  repo: https://github.com/your-org/fleet-base-apps
  branch: main
  paths:
    - bundles
EOF
```

## Step 3: Monitor Bundle Deployment

```bash
# Watch bundles being deployed
kubectl -n fleet-default get bundles -w

# Watch bundle deployments
kubectl -n fleet-default get bundledeployments -w

# Check deployment status
kubectl -n fleet-default describe bundle cert-manager
```

## Step 4: Deployment Order & Verification

Deploy in this order to ensure dependencies are met:

### Tier 1: Core Infrastructure (All Clusters)

```bash
# 1. Cert Manager (required by others)
kubectl -n fleet-default get bundle cert-manager
# Wait for: Status = Active

# 2. MetalLB (bare-metal load balancer)
kubectl -n fleet-default get bundle metallb
# Check: kubectl get svc -n metallb-system

# 3. Nginx Ingress Controller
kubectl -n fleet-default get bundle nginx-ingress-controller
# Verify: kubectl get svc -n ingress-nginx (should have EXTERNAL-IP)
```

### Tier 2: Storage & Monitoring (All Clusters)

```bash
# 4. Longhorn (persistent storage)
kubectl -n fleet-default get bundle longhorn
# Verify: kubectl get storageclass (should show longhorn)

# 5. Prometheus + Grafana
kubectl -n fleet-default get bundle prometheus-grafana
# Verify: kubectl get pods -n monitoring
```

### Tier 3: Logging (All Clusters)

```bash
# 6. Fluent Bit
kubectl -n fleet-default get bundle fluent-bit
# Verify: kubectl get daemonset -n logging
```

### Tier 4: Secrets Management

```bash
# UPSTREAM ONLY:
# 7. Vault
kubectl -n fleet-default get bundle vault
# Verify: kubectl get pods -n vault

# DOWNSTREAM ONLY:
# 8. External Secrets Operator
kubectl -n fleet-default get bundle external-secrets-operator
# Verify: kubectl get pods -n external-secrets-system
```

## Step 5: Access Applications

### Prometheus
```bash
# Port-forward for testing
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090

# Or via ingress:
# https://prometheus.yourdomain.local
```

### Grafana
```bash
# Port-forward for testing
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80

# Or via ingress:
# https://grafana.yourdomain.local
# Default credentials: admin / changeme (change in values.yaml!)
```

### Vault (Upstream Only)
```bash
# Port-forward for testing
kubectl -n vault port-forward svc/vault 8200:8200

# Or via ingress:
# http://vault.yourdomain.local (or https if TLS configured)
# Dev mode token: root-token-poc (from fleet.yaml values)
```

### Longhorn UI
```bash
# Port-forward for testing
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80

# Or via ingress:
# http://longhorn-ui.yourdomain.local
```

## Step 6: Configure Vault for Cross-Cluster Secrets (Optional)

See [VAULT_SETUP.md](./VAULT_SETUP.md) for detailed instructions.

Quick summary:
```bash
# On upstream cluster
cd fleet-base-apps/scripts
chmod +x vault-setup.sh
./vault-setup.sh

# This outputs Role ID and Secret ID
# Use these to configure External Secrets on downstream cluster
```

## Troubleshooting Deployments

### Bundle stuck in "WaitApplyServer" state

```bash
# Check what's preventing deployment
kubectl -n fleet-default describe bundle <bundle-name>

# Often due to missing dependencies (e.g., StorageClass)
# Check if previous tier deployed successfully
```

### App pod not starting

```bash
# Check pod status
kubectl get pods -n <namespace>

# View logs
kubectl logs -n <namespace> -l app=<app-name>

# Check resource availability
kubectl top nodes
kubectl describe node <node-name>
```

### Ingress not resolving

```bash
# Check ingress status
kubectl get ingress -n <namespace>

# Verify DNS
nslookup prometheus.yourdomain.local
# Should resolve to MetalLB external IP

# Verify ingress controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app=ingress-nginx
```

### MetalLB IPs not assigned to LoadBalancer services

```bash
# Check MetalLB configuration
kubectl get configmap -n metallb-system metallb -o yaml

# Check speaker logs
kubectl logs -n metallb-system -l app=metallb,component=speaker

# Verify IP pool range
# Edit: bundles/metallb/fleet.yaml
# Adjust address-pools to match your network
```

## Customization

### Change domain names

```bash
# Replace all domain references
sed -i 's/yourdomain.local/your-domain.com/g' bundles/*/fleet.yaml

# Git commit and push
git add .
git commit -m "Update domain configuration"
git push origin main

# Fleet will auto-sync within minutes
```

### Change resource limits

Edit individual bundle files:
```yaml
# bundles/prometheus-grafana/fleet.yaml
spec:
  helm:
    values:
      prometheus:
        prometheusSpec:
          resources:
            limits:
              memory: 2Gi  # Increase if needed
```

### Change storage class

```yaml
# bundles/longhorn/fleet.yaml
spec:
  helm:
    values:
      persistence:
        storageClass: longhorn  # or local-path, etc.
```

### Add more bundles

1. Create new directory: `bundles/my-app/`
2. Add `fleet.yaml` with Helm configuration
3. Commit and push
4. Fleet automatically picks it up

## Security Considerations

### Production Recommendations

1. **Vault**: Switch from dev mode to HA mode
   - Uncomment `ha:` section in `bundles/vault/fleet.yaml`
   - Use proper TLS certificates
   - Configure persistent storage with Longhorn

2. **Grafana**: Change default password
   - Edit `bundles/prometheus-grafana/fleet.yaml`
   - Set `adminPassword: <secure-password>`

3. **Git Repository**: Use SSH keys or tokens
   - Create K8s secret with SSH private key
   - Reference in GitRepo spec

4. **Network Policies**: Restrict traffic
   - Add NetworkPolicy manifests to bundles
   - Limit pod-to-pod communication

5. **RBAC**: Configure least-privilege access
   - Review ServiceAccount and RBAC in each bundle
   - Limit to required permissions only

## Backup Considerations

### Critical Data

- **Vault data**: Backup encryption keys and state
- **Prometheus data**: Long-term storage planning
- **Grafana dashboards**: Export as JSON
- **Longhorn volumes**: Snapshot and backup policy

```bash
# Backup Vault state (dev mode only)
kubectl -n vault exec vault-0 -- vault operator raft snapshot save /tmp/raft.snap

# Backup Longhorn volumes
# Use Longhorn UI or kubectl API to create snapshots
```

## Next Steps

1. ✅ Deploy all base apps
2. ✅ Verify connectivity and access
3. ➡️ [Configure Vault for secrets](./VAULT_SETUP.md)
4. ➡️ Deploy your applications
5. ➡️ Setup monitoring dashboards
6. ➡️ Configure backup policies

