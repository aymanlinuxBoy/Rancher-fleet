# Troubleshooting Guide

## Bundle Deployment Issues

### Bundle stuck in "WaitApplyServer" or "NotReady"

**Symptoms:** Bundle shows `Status: WaitApplyServer` for extended period

**Diagnosis:**
```bash
# Check bundle status
kubectl -n fleet-default describe bundle <bundle-name>

# Check bundle deployment status
kubectl -n fleet-default get bundledeployments

# Check Fleet controller logs
kubectl -n fleet-system logs -l app=fleet-controller -f
```

**Common Causes & Fixes:**

1. **Dependency not deployed yet**
   ```bash
   # Check if dependencies are ready
   kubectl get bundle -n fleet-default
   
   # Example: nginx-ingress requires cert-manager
   # Ensure cert-manager is ready first
   kubectl -n cert-manager get pods
   ```

2. **Resource limits exceeded**
   ```bash
   # Check node capacity
   kubectl top nodes
   kubectl top pods --all-namespaces --sort-by=memory
   
   # Solution: Add more nodes or reduce resource requests in values.yaml
   ```

3. **Namespace not created**
   ```bash
   # Check if namespace exists
   kubectl get ns <namespace>
   
   # Solution: Ensure Fleet has RBAC to create namespaces
   kubectl -n fleet-system get clusterrole fleet-default
   ```

4. **Helm chart not found**
   ```bash
   # Check Helm repo connectivity
   kubectl -n fleet-default logs <bundle-deployment-pod>
   
   # Solution: Check chart repo URLs in fleet.yaml
   # Verify internet access or air-gapped registry
   ```

---

## Pod Issues

### Pod stuck in "Pending" state

**Symptoms:** Pod doesn't start after 5+ minutes

**Diagnosis:**
```bash
# Check pod status
kubectl describe pod <pod-name> -n <namespace>

# Look at Events section - usually shows the issue
```

**Common Causes & Fixes:**

1. **PVC (Persistent Volume Claim) not bound**
   ```bash
   # Check PVC status
   kubectl get pvc -n <namespace>
   
   # If "Pending":
   kubectl describe pvc <pvc-name> -n <namespace>
   
   # Solution: Ensure storage class exists
   kubectl get storageclass
   
   # For Longhorn, wait for it to deploy
   kubectl -n longhorn-system get pods
   ```

2. **Insufficient CPU/Memory**
   ```bash
   # Check node resources
   kubectl describe node <node-name>
   
   # Check current usage
   kubectl top nodes
   
   # Solution: Either
   # - Reduce resource requests in values.yaml
   # - Add more nodes
   # - Evict less critical pods
   ```

3. **Image pull errors**
   ```bash
   # Check pod events
   kubectl describe pod <pod-name> -n <namespace>
   
   # If "ImagePullBackOff":
   # - Check image registry accessibility
   # - Verify imagePullSecrets if using private registry
   # - Check internet connectivity
   ```

4. **Node not ready**
   ```bash
   # Check node status
   kubectl get nodes
   
   # If not ready:
   kubectl describe node <node-name>
   
   # Solution:
   # - Check node logs: journalctl -u kubelet -f
   # - Restart kubelet: systemctl restart kubelet
   # - Add node taints/tolerations if needed
   ```

---

## Networking & Ingress Issues

### Ingress not accessible (404 / Connection refused)

**Symptoms:** Ingress created but `curl` returns 404 or connection refused

**Diagnosis:**
```bash
# Check ingress creation
kubectl get ingress -n <namespace>

# Check ingress controller
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx

# Check if external IP assigned
kubectl get svc ingress-nginx-controller -n ingress-nginx
# Should show EXTERNAL-IP (from MetalLB)

# Test from inside cluster
kubectl run -it --image=curlimages/curl test -- \
  curl -v http://<ingress-host>
```

**Common Causes & Fixes:**

1. **No external IP (MetalLB not working)**
   ```bash
   # Check MetalLB speaker logs
   kubectl -n metallb-system logs -l app=metallb,component=speaker
   
   # Check MetalLB config
   kubectl -n metallb-system get configmap metallb -o yaml
   
   # Verify IP pool range matches your network
   ```

2. **DNS not resolving**
   ```bash
   # Test DNS resolution
   nslookup prometheus.yourdomain.local
   
   # If not resolving:
   # - Update /etc/hosts for local testing:
   echo "<metallb-ip> prometheus.yourdomain.local" >> /etc/hosts
   
   # - Or setup proper DNS records
   # - Or use IP directly: http://<metallb-ip>
   ```

3. **Ingress controller not picking up ingress**
   ```bash
   # Check nginx ingress logs
   kubectl -n ingress-nginx logs -l app=ingress-nginx
   
   # Verify ingressClassName
   kubectl get ingress <ingress-name> -n <namespace> -o yaml
   # Should have: ingressClassName: nginx
   
   # Verify ingress controller is managing that class
   kubectl get ingressclass
   ```

4. **Wrong backend service**
   ```bash
   # Check ingress rules
   kubectl describe ingress <ingress-name> -n <namespace>
   
   # Verify backend service exists
   kubectl get svc <backend-service> -n <namespace>
   
   # Test backend directly
   kubectl port-forward svc/<backend-service> 8080:80 -n <namespace>
   curl http://localhost:8080
   ```

---

## Vault Specific Issues

### Vault pod won't start

**Symptoms:** `vault-0` stuck in Pending or CrashLoopBackOff

**Diagnosis:**
```bash
# Check pod logs
kubectl logs -n vault vault-0

# Check pod events
kubectl describe pod vault-0 -n vault

# Check PVC
kubectl get pvc -n vault
kubectl describe pvc -n vault
```

**Common Causes:**

1. **Storage class issue**
   ```bash
   # Check storage class
   kubectl get storageclass
   
   # If longhorn doesn't exist:
   # - Wait for Longhorn bundle to deploy
   # - Or change storageClass to "local-path"
   ```

2. **Port already in use**
   ```bash
   # Check if port 8200 is available
   netstat -tulpn | grep 8200
   
   # Solution: Change service port in values.yaml
   ```

### Can't authenticate to Vault

**Symptoms:** `vault login` fails with "permission denied"

**Diagnosis:**
```bash
# Check Vault is initialized
kubectl -n vault exec vault-0 -- vault status

# Check auth methods
kubectl -n vault exec vault-0 -- vault auth list

# For dev mode, token should be: root-token-poc
kubectl -n vault exec vault-0 -- vault login root-token-poc
```

---

## External Secrets Issues

### ExternalSecret shows "Failed to sync"

**Symptoms:** ExternalSecret created but secret not appearing

**Diagnosis:**
```bash
# Check ExternalSecret status
kubectl describe externalsecret <name> -n <namespace>

# Check ESO logs
kubectl -n external-secrets-system logs -l app=external-secrets

# Verify ClusterSecretStore
kubectl get clustersecretstore
kubectl describe clustersecretstore vault-backend
```

**Common Causes & Fixes:**

1. **ClusterSecretStore not found**
   ```bash
   # Apply ClusterSecretStore
   kubectl apply -f manifests/clustersecretstore.yaml
   
   # Verify
   kubectl get clustersecretstore vault-backend
   ```

2. **Vault connectivity issue**
   ```bash
   # Test from ESO pod
   kubectl -n external-secrets-system exec -it \
     $(kubectl -n external-secrets-system get pod -l app=external-secrets -o jsonpath='{.items[0].metadata.name}') \
     -- curl -v http://vault.vault.svc.cluster.local:8200/v1/sys/health
   
   # If fails: check network policies, DNS, firewall
   ```

3. **AppRole credentials invalid**
   ```bash
   # Check if secret exists
   kubectl -n external-secrets-system get secret vault-approle-creds
   
   # Check contents
   kubectl -n external-secrets-system get secret vault-approle-creds -o yaml
   
   # Regenerate credentials
   cd scripts
   ./vault-setup.sh
   ```

4. **Vault path doesn't exist**
   ```bash
   # List secrets in Vault
   kubectl -n vault exec vault-0 -- vault kv list secret/downstream
   
   # If path missing, create it:
   kubectl -n vault exec vault-0 -- vault kv put secret/downstream/test value=test
   
   # Then update ExternalSecret to point to existing path
   ```

---

## Monitoring Issues

### Prometheus not scraping targets

**Symptoms:** "Up: 0" or missing targets in Prometheus UI

**Diagnosis:**
```bash
# Access Prometheus
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090

# Go to: http://localhost:9090/targets
# Check which targets are down

# Check ServiceMonitor objects
kubectl get servicemonitor -A

# Check Prometheus config
kubectl -n monitoring get prometheus kube-prometheus-stack-prometheus -o yaml
```

**Common Causes:**

1. **Target pod not ready**
   ```bash
   # Verify pod is running
   kubectl get pods -n <namespace> -l <label-selector>
   ```

2. **ServiceMonitor labels don't match**
   ```bash
   # Check ServiceMonitor label selectors
   kubectl describe servicemonitor -n <namespace>
   
   # Ensure Prometheus is configured to find these labels
   ```

### Grafana can't connect to Prometheus

**Symptoms:** Datasource shows "Error" or "No data"

**Diagnosis:**
```bash
# Check Prometheus service
kubectl get svc -n monitoring | grep prometheus

# Test connectivity from Grafana pod
kubectl -n monitoring exec -it \
  $(kubectl -n monitoring get pod -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}') \
  -- curl -v http://kube-prometheus-stack-prometheus:9090
```

**Fix:**
```bash
# Update Grafana datasource URL:
# URL: http://kube-prometheus-stack-prometheus:9090
# (Must use internal K8s DNS, not external IP)
```

---

## Storage Issues

### Longhorn volumes not provisioning

**Symptoms:** PVC stuck in Pending, or volume fails to create

**Diagnosis:**
```bash
# Check Longhorn manager
kubectl -n longhorn-system get pods

# Check manager logs
kubectl -n longhorn-system logs -l app=longhorn-manager

# Check storage class
kubectl get storageclass

# Check if longhorn is set as default
kubectl get storageclass longhorn -o yaml
```

**Common Causes:**

1. **Not enough replicas available**
   ```bash
   # Longhorn needs multiple nodes for replication
   kubectl get nodes
   
   # If only 1 node, change replica count:
   # longhorn.io/number-of-replicas: "1"
   ```

2. **Disk space exhausted**
   ```bash
   # Check disk usage on nodes
   df -h
   
   # Check Longhorn volumes
   kubectl -n longhorn-system get volumes
   ```

---

## Quick Diagnostic Checklist

```bash
# 1. Check cluster health
kubectl get nodes
kubectl get namespaces

# 2. Check bundle status
kubectl -n fleet-default get bundles
kubectl -n fleet-default get bundledeployments

# 3. Check pod status in each namespace
kubectl get pods -n cert-manager
kubectl get pods -n metallb-system
kubectl get pods -n ingress-nginx
kubectl get pods -n longhorn-system
kubectl get pods -n monitoring
kubectl get pods -n logging
kubectl get pods -n vault
kubectl get pods -n external-secrets-system

# 4. Check service endpoints
kubectl get svc -A | grep -E "EXTERNAL-IP|LoadBalancer"

# 5. Check persistent volumes
kubectl get pv
kubectl get pvc -A

# 6. Check ingresses
kubectl get ingress -A

# 7. Review recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# 8. Check Fleet controller
kubectl -n fleet-system logs -l app=fleet-controller --tail=50
```

---

## Getting Help

If issues persist:

1. **Collect logs**
   ```bash
   kubectl logs -n <namespace> -l app=<app-name> > logs.txt
   ```

2. **Export YAML**
   ```bash
   kubectl get <resource> <name> -n <namespace> -o yaml > debug.yaml
   ```

3. **Check Rancher logs**
   - Rancher UI: Logs → View Logs

4. **Consult documentation**
   - [Fleet Docs](https://fleet.rancher.io/)
   - [Vault Docs](https://www.vaultproject.io/docs)
   - [External Secrets Docs](https://external-secrets.io/)
   - [Longhorn Docs](https://longhorn.io/docs/)
