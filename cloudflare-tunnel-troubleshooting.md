# Cloudflare Tunnel + Cilium Gateway API + ArgoCD: Setup & Troubleshooting Runbook

## Architecture Overview

```
Browser
  → Cloudflare Edge (TLS termination for public)
    → cloudflared pod (in-cluster, connects outbound to CF edge)
      → cilium-gateway-homelab-gateway Service (ClusterIP, ports 80/443)
        → Cilium Envoy DaemonSet (kube-system, processes Gateway API rules)
          → backend Service (e.g. argocd-server:80)
```

Cloudflare Tunnel works by running `cloudflared` pods inside the cluster that maintain persistent outbound connections to Cloudflare's edge. When a request arrives at `*.daltonbuilds.com`, Cloudflare routes it through the tunnel to the `cloudflared` pod, which then forwards it to the in-cluster Gateway service.

Cilium's Gateway API implementation uses the Envoy DaemonSet in `kube-system` (not standalone pods in the `gateway` namespace) to handle traffic. The `cilium-gateway-*` Service in the `gateway` namespace is a LoadBalancer with a dummy EndpointSlice — Cilium uses eBPF to intercept traffic to the ClusterIP and route it to its Envoy proxies.

---

## Key Concepts

### Cloudflare Remote Tunnel Management vs Local Config

When a tunnel is created via the Cloudflare dashboard (Zero Trust → Networks → Tunnels), it uses **remote management**. This means:

- Cloudflare pushes ingress rules to `cloudflared` pods on connect (logged as `Updated to new configuration version=N`)
- **Remote rules completely override** the local `ingress:` block in the ConfigMap
- The local config file still controls `tunnel`, `credentials-file`, `metrics`, and the **global `originRequest`** block
- The global `originRequest` in the local config provides defaults that remote per-rule settings merge with (remote only overrides keys it explicitly sets)

**Implication:** If you change `ingress` rules in the ConfigMap but the tunnel is remotely managed, those changes have no effect. You must update rules in the Cloudflare dashboard.

### Cilium Gateway API TLS / SNI Behavior

Cilium's Gateway with an HTTPS listener uses Envoy's **TLS filter chain matching based on SNI**. The listener in `gateway.yaml`:

```yaml
listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: "*.daltonbuilds.com"
    tls:
      mode: Terminate
      certificateRefs:
        - name: homelab-gateway-tls
```

Envoy's generated config creates a `filterChainMatch` with `serverNames: ['*.daltonbuilds.com']`. Any TLS connection whose SNI does **not** match `*.daltonbuilds.com` is rejected with a TCP RST (connection reset).

### ArgoCD Helm Chart: `server.insecure`

In the argo-cd Helm chart (v9.x+), the correct values path to disable TLS on argocd-server is:

```yaml
configs:
  params:
    server.insecure: true
```

**Not** `server.insecure: true` at the top level — that maps to nothing and is silently ignored. The key must be a dotted string under `configs.params`, which populates the `argocd-cmd-params-cm` ConfigMap with `server.insecure: "true"`. Without this, argocd-server runs its own TLS and redirects HTTP → HTTPS, causing redirect loops when TLS is terminated upstream.

---

## Common Failure Modes & Solutions

### 1. HTTPRoutes Not Applied (Missing ArgoCD Application)

**Symptom:** `kubectl get httproute -A` returns nothing despite YAML files committed to Git.

**Root Cause:** No ArgoCD `Application` resource exists to manage the directory containing the HTTPRoute manifests. ArgoCD only deploys what it knows about.

**Diagnosis:**
```bash
# Check if routes exist in cluster
kubectl get httproute -A

# List ArgoCD apps — look for one pointing at your routes directory
kubectl get applications -n argocd
```

**Fix:** Create the ArgoCD Application. Note the sync-wave should be after the Gateway is ready:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-ingress
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
spec:
  project: homelab
  source:
    repoURL: https://github.com/YourOrg/your-repo
    path: apps/platform-ingress
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
```

Important: `destination` has no `namespace` because HTTPRoutes live in their respective app namespaces (argocd, kube-system, etc.), not a single namespace.

---

### 2. 502 Bad Gateway — Connection Reset by Peer

**Symptom:** Cloudflare shows 502. Cloudflared logs show:
```
ERR error="Unable to reach the origin service. The service may be down or it may not
be responding to traffic from cloudflared: read tcp 10.42.x.x:NNNNN->10.43.x.x:443:
read: connection reset by peer"
```

**Root Cause:** TLS SNI mismatch. Cloudflared connects to the gateway service via HTTPS using the service hostname (`cilium-gateway-homelab-gateway.gateway.svc.cluster.local`) as the TLS SNI. Envoy's filter chain only matches `*.daltonbuilds.com` → no match → TCP RST.

**Diagnosis:**
```bash
# Confirm the gateway service exists and has an IP
kubectl get svc -n gateway cilium-gateway-homelab-gateway

# Check the CiliumEnvoyConfig to see what SNI Envoy expects
kubectl get ciliumenvoyconfig -n gateway cilium-gateway-homelab-gateway -o yaml \
  | grep -A 5 "serverNames"

# Check cloudflared logs for the specific error
kubectl logs -n cloudflared -l app.kubernetes.io/name=cloudflared --tail=30
```

**Fix:** Set `originServerName` in the Cloudflare dashboard so cloudflared sends a matching SNI:

1. Go to **Zero Trust → Networks → Tunnels → your tunnel → Public Hostnames**
2. For each hostname, click the three-dot menu → Edit
3. Set **Service** to: `https://cilium-gateway-homelab-gateway.gateway.svc.cluster.local`
4. Expand **Additional application settings → TLS**:
   - **Origin Server Name**: `gateway.daltonbuilds.com` (must match the Gateway's `*.daltonbuilds.com` listener)
   - **No TLS Verify**: ON (the cert is for `*.daltonbuilds.com`, not the internal service name)
5. Save

Cloudflared will log `Updated to new configuration version=N` within seconds. Verify:
```bash
kubectl logs -n cloudflared -l app.kubernetes.io/name=cloudflared \
  | grep "Updated to new configuration" | tail -1
```

Confirm the JSON includes `"originServerName":"gateway.daltonbuilds.com"`.

If the pods don't pick up the change, restart them:
```bash
kubectl rollout restart deployment/cloudflared -n cloudflared
```

---

### 3. 502 Bad Gateway — DNS Lookup Failure ("no such host")

**Symptom:** Cloudflared logs show:
```
ERR error="Unable to reach the origin service... dial tcp: lookup gateway.daltonbuilds.com
on 10.43.0.10:53: no such host"
```

**Root Cause:** The **Service URL** in the Cloudflare dashboard was set to `gateway.daltonbuilds.com` (the public hostname) instead of the internal Kubernetes service name. Cloudflared tries to DNS-resolve this via CoreDNS, which doesn't know about external domains.

**Key distinction:** In the Cloudflare dashboard, **Service URL** and **Origin Server Name** are different fields:

| Field | Purpose | Value |
|---|---|---|
| **Service URL** | Where cloudflared connects (must resolve in cluster DNS) | `cilium-gateway-homelab-gateway.gateway.svc.cluster.local` |
| **Origin Server Name** | TLS SNI override (only affects the TLS handshake) | `gateway.daltonbuilds.com` |

**Fix:** Correct the Service URL in the dashboard to the internal service name. Keep Origin Server Name as the public domain.

---

### 4. ERR_TOO_MANY_REDIRECTS (Redirect Loop)

**Symptom:** Browser shows "redirected you too many times" or alternates between redirect error and 502.

**Root Cause:** ArgoCD server is running with TLS enabled (the default) and redirects HTTP → HTTPS. Since TLS is already terminated at the Cilium Gateway, argocd-server receives plain HTTP, redirects to HTTPS, which comes back as HTTP again → infinite loop.

**Diagnosis:**
```bash
# Check if server.insecure is set in the ConfigMap
kubectl get configmap -n argocd argocd-cmd-params-cm -o yaml | grep insecure

# Check if the pod has the env var
kubectl get deployment -n argocd argocd-server -o yaml | grep -A 5 ARGOCD_SERVER_INSECURE
```

**Fix:** Use the correct Helm values path (argo-cd chart v9.x+):

```yaml
# CORRECT
configs:
  params:
    server.insecure: true

# WRONG — does nothing
server:
  insecure: true
```

After syncing, verify the ConfigMap was updated and the pod restarted:
```bash
kubectl get configmap -n argocd argocd-cmd-params-cm -o yaml | grep insecure
# Should show: server.insecure: "true"

kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server
# Should show a recent restart (low AGE)
```

---

### 5. Envoy Listener Has No Virtual Hosts

**Symptom:** Traffic reaches Envoy but returns 404 or RST. The CiliumEnvoyConfig shows an empty route configuration.

**Diagnosis:**
```bash
# Check which listeners have virtual hosts
kubectl get ciliumenvoyconfig -n gateway cilium-gateway-homelab-gateway -o yaml \
  | grep -A 20 "listener-secure"

# Check if routes are attached to the gateway
kubectl describe gateway homelab-gateway -n gateway | grep "Attached Routes"
```

**Root Cause:** HTTPRoutes may be targeting the wrong listener, or there's a Cilium version bug.

**Notes on `sectionName`:**
- Without `sectionName`, HTTPRoutes attach to all matching listeners
- With `sectionName: https`, they only attach to the HTTPS listener (populates `listener-secure`)
- With `sectionName: http`, they should attach to the HTTP listener (populates `listener-insecure`) — but Cilium 1.19.1 has a bug where this doesn't work
- For Cilium 1.19.x, omit `sectionName` so routes attach to both listeners via the HTTPS path

---

## Diagnostic Command Reference

```bash
# === Gateway & Routes ===
kubectl get gateway -A                                    # List all gateways
kubectl describe gateway homelab-gateway -n gateway       # Check listeners, attached routes, conditions
kubectl get httproute -A                                  # List all HTTPRoutes
kubectl describe httproute <name> -n <ns>                 # Check parent status, accepted/resolved

# === Cilium Gateway Internals ===
kubectl get ciliumenvoyconfig -A                          # List Envoy configs managed by Cilium
kubectl get ciliumenvoyconfig -n gateway <name> -o yaml   # Full Envoy listener/route/cluster config
kubectl get svc -n gateway                                # Gateway service (managed by Cilium)
kubectl get endpointslices -n gateway                     # Dummy endpoints (192.192.192.192 is normal)
kubectl get pods -n kube-system | grep envoy              # Envoy DaemonSet pods (actual data plane)

# === Cilium Status ===
cilium status                                             # Overall Cilium health
kubectl get gatewayclasses                                # Should show "cilium" as Accepted
kubectl logs -n kube-system -l k8s-app=cilium-operator --tail=50  # Operator logs for gateway reconciliation

# === Cloudflared ===
kubectl get pods -n cloudflared                           # Pod status
kubectl logs -n cloudflared -l app.kubernetes.io/name=cloudflared --tail=50  # Recent logs
kubectl logs -n cloudflared -l app.kubernetes.io/name=cloudflared \
  | grep "Updated to new configuration" | tail -1        # Current remote config version
kubectl rollout restart deployment/cloudflared -n cloudflared  # Force config reload

# === Certificates ===
kubectl get certificate -n gateway                        # Cert-manager certificate status
kubectl get secret -n gateway homelab-gateway-tls          # TLS secret existence

# === ArgoCD ===
kubectl get applications -n argocd                        # All ArgoCD apps and sync status
kubectl get configmap -n argocd argocd-cmd-params-cm -o yaml  # Server config params
```

---

## Sync Wave Reference

Ordering matters. Resources must exist before dependents try to reference them:

| Wave | Resource | Why |
|------|----------|-----|
| -2 | ArgoCD (Helm) | Must be running to manage everything else |
| -1 | Gateway API CRDs | CRDs must exist before any Gateway/HTTPRoute |
| 0 | Cilium (Helm) | CNI + Gateway controller |
| 1 | cert-manager | Issues certificates |
| 2 | cert-manager-config (ClusterIssuer) | References cert-manager |
| 3 | External Secrets, Secret Store | Provides secrets to other apps |
| 4 | Gateway, Cloudflared | Gateway needs CRDs + certs; cloudflared needs tunnel secret |
| 5 | platform-ingress (HTTPRoutes) | Routes need Gateway to exist |

---

## Checklist for New Tunnel Setup

1. **Cloudflare dashboard:** Create tunnel, note tunnel UUID
2. **Store credentials:** Add tunnel credentials JSON to your secret store (e.g. GCP Secret Manager)
3. **ExternalSecret:** Create ExternalSecret to sync credentials into cluster as `tunnel-credentials` Secret
4. **Cloudflared manifests:** Deployment + ConfigMap with tunnel UUID and credentials path
5. **Cloudflare dashboard routes:** Add public hostnames pointing to `https://cilium-gateway-<gateway-name>.<gateway-namespace>.svc.cluster.local`
6. **TLS settings per route:** Set Origin Server Name to a hostname matching the Gateway listener (e.g. `gateway.yourdomain.com`), enable No TLS Verify
7. **Gateway:** Ensure HTTPS listener with matching wildcard hostname and valid TLS cert
8. **HTTPRoutes:** Create routes referencing the Gateway, targeting backend services
9. **ArgoCD Application:** Ensure an Application exists for every directory containing manifests
10. **Backend config:** Disable TLS on backends where the Gateway already terminates (e.g. `configs.params.server.insecure: true` for ArgoCD)
