# Operation Clean Slate v3 — Complete Build Checklist

> **How to use this document:** Work through phases sequentially. Each phase has a verification step — do not move to the next phase until verification passes. Check off items as you complete them.
>
> **What changed from v2:** Streamlined to an 8-phase MVP. Dropped MetalLB in favor of Cilium L2 announcements. Removed UFW/iptables (conflicts with Cilium eBPF). Added HashiCorp Vault for dynamic secrets. Aligned NFS paths/IPs across all repos. Bumped mgmt-plane RAM to 16GB. Deferred Kyverno, Velero, ARC, Authentik, n8n, pgBackRest, restic, NetworkPolicies, and Trivy to an Upgrades section at the end.
>
> **Repos involved:**
> - `homelab-gitops` — All Kubernetes manifests, Helm values, ArgoCD apps, Flux config
> - `homelab-ansible` — OS-level configuration for all nodes and VMs
> - `homelab-terraform` — Proxmox VM provisioning via bpg/proxmox provider
>
> **Cluster naming:**
> - **Workload cluster:** gandalf (CP), aragorn (W1), legolas (W2), gimli (W3)
> - **Management cluster:** mgmt-plane (single-node k3s, Flux-managed)
> - **Infrastructure:** nfs-server (VM), garage (LXC container)

---

## Pre-Flight: Decisions Locked In

Before starting, confirm you're aligned on all of these:

- [x]  **CNI:** Cilium (replaces Flannel AND kube-proxy via eBPF)
- [x]  **Load Balancing:** Cilium L2 announcements (replaces MetalLB — fewer components, same result)
- [x]  **Ingress:** Cilium Gateway API (replaces Traefik — `--disable traefik` in k3s)
- [x]  **GitOps (workload):** ArgoCD with app-of-apps, custom AppProject
- [x]  **GitOps (mgmt):** Flux — demonstrates multi-tool breadth
- [x]  **Storage (file):** NFS backed by ZFS on dedicated Proxmox VM
- [x]  **Storage (object):** Garage (S3-compatible, replaces MinIO) — runs as LXC container
- [x]  **Secrets (static):** ESO + GCP Secret Manager (already working)
- [x]  **Secrets (dynamic):** HashiCorp Vault Community Edition — dynamic DB credentials, PKI
- [x]  **Observability:** Prometheus + Loki + Alloy + Hubble + Grafana + Alertmanager (on mgmt cluster)
- [x]  **TLS:** cert-manager with DNS-01 via Cloudflare (already working)
- [x]  **Tunnel:** Cloudflared (already working)

---

## Network & IP Allocation (Reference)

Keep this table handy — everything references it.

| Host | IP | VLAN | Role | Location |
| --- | --- | --- | --- | --- |
| Workstation (Ryzen 9) | 192.168.10.77 | 10 | Daily driver | Physical |
| gandalf (M920q) | 192.168.40.30 | 40 | k3s control plane | Physical |
| aragorn (M920q) | 192.168.40.31 | 40 | k3s worker 1 | Physical |
| legolas (M920q) | 192.168.40.32 | 40 | k3s worker 2 | Physical |
| Proxmox host (M920 SFF) | 192.168.40.50 | 40 | Hypervisor (64GB RAM, 1TB SSD) | Physical |
| nfs-server (VM) | 192.168.40.51 | 40 | NFS + ZFS persistent storage | VM on Proxmox |
| mgmt-plane (VM) | 192.168.40.52 | 40 | Observability stack (independent k3s) | VM on Proxmox |
| garage (LXC) | 192.168.40.53 | 40 | S3-compatible object storage | LXC on Proxmox |
| gimli (VM) | 192.168.40.33 | 40 | k3s worker 3 | VM on Proxmox |

**Service IPs (Cilium L2 pool):** 192.168.40.240–192.168.40.250

---

## Phase 0: Proxmox Installation on SFF PC

**Goal:** Bare-metal Proxmox VE running on the M920 SFF, accessible from the workstation.

- [x]  Download Proxmox VE ISO (latest stable) and flash to USB
- [x]  Boot the M920 SFF from USB, begin Proxmox installation
- [x]  **Disk setup during install:** Select the 1TB SSD, use **ext4** or **XFS** for the Proxmox root filesystem
    - Do NOT select ZFS at the Proxmox level — ZFS will live inside the NFS VM only
    - Proxmox just needs a reliable filesystem for itself and VM disk images
- [x]  Set the management IP: `192.168.40.50`, gateway and DNS per your network
- [x]  Set hostname: `proxmox` (or whatever you prefer)
- [x]  Complete installation, reboot, remove USB
- [x]  Access Proxmox web UI from workstation: `https://192.168.40.50:8006`
- [x]  Configure Proxmox networking:
    - Verify `vmbr0` bridge is bound to the physical NIC
    - Confirm bridge is on VLAN 40 (or trunk — depends on your switch config)
    - VMs will get IPs in the 192.168.40.0/24 range via static assignment
- [x]  Set DHCP reservation on your router/firewall for 192.168.40.50
- [x]  Upload Ubuntu Server 24.04 ISO to Proxmox local storage (or download via URL in the UI)

### Verification

- [x]  Proxmox web UI loads from workstation browser
- [x]  Can ping 192.168.40.50 from workstation
- [x]  Ubuntu 24.04 ISO visible in Proxmox storage

---

## Phase 1: Terraform — VM Provisioning

**Goal:** All VMs and LXC containers created on Proxmox via Terraform (IaC, not clicking through the UI).

### 1a. Set Up homelab-terraform Repo

- [x]  Create `homelab-terraform` repo
- [x]  Initialize Terraform project structure:

```
homelab-terraform/
├── main.tf              # Provider config
├── infra.tf             # VM and LXC resource definitions
├── locals.tf            # Configuration locals and node specs
├── variables.tf         # Variable definitions
├── terraform.tfvars     # Actual values (gitignored if contains secrets)
├── outputs.tf           # Output IP addresses, VM IDs
├── cloud-init/          # Cloud-init templates
│   ├── nfs-server.yaml
│   ├── mgmt-plane.yaml
│   └── gimli.yaml
└── docs/
    └── 01-proxmox-terraform-bootstrap.md
```

- [x]  Configure the bpg/proxmox provider (v0.97.1+):

```hcl
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.97.0"
    }
  }
}

provider "proxmox" {
  endpoint = "https://192.168.40.50:8006/"
  # Auth via API token — SSH via ssh-agent for SFTP snippet uploads
  insecure = true  # Self-signed cert
}
```

- [x]  Create a Proxmox API token for Terraform (better than using root password)
    - Proxmox UI → Datacenter → Permissions → API Tokens
    - Store token in `terraform.tfvars` (gitignored) or environment variable

### 1b. Define VMs in Terraform

- [x]  Define all resources with cloud-init. Resource sizing:

| Resource | Type | VM ID | vCPU | RAM | Disk | Static IP |
| --- | --- | --- | --- | --- | --- | --- |
| nfs-server | VM (Ubuntu 24.04) | 101 | 2 | 4GB | 600GB | 192.168.40.51 |
| mgmt-plane | VM (Ubuntu 24.04) | 102 | 4 | 16GB | 60GB | 192.168.40.52 |
| gimli | VM (Ubuntu 24.04) | 100 | 4 | 8GB | 50GB | 192.168.40.33 |
| garage | LXC (Debian 13) | 200 | 2 | 2GB | 8GB + 200GB data | 192.168.40.53 |

> **Note on mgmt-plane RAM:** 16GB gives comfortable headroom for kube-prometheus-stack + Loki + Grafana. Proxmox host has 64GB — total VM allocation is ~30GB, leaving plenty of headroom.

> **Note on garage:** LXC container, not a VM. Garage needs minimal resources (~1GB RAM). LXC is lighter weight and faster to provision.

- [x]  Cloud-init templates should set:
    - Hostname
    - Static IP, gateway, DNS
    - SSH public key (your workstation key)
    - Disable password auth
    - Package update on first boot
    - Install `qemu-guest-agent`
- [x]  Run `terraform plan` — review the plan carefully
- [x]  Run `terraform apply` — create all resources
- [x]  Set DHCP reservations on your router for all IPs (belt and suspenders with static cloud-init)

### Verification

- [x]  All VMs and LXC running in Proxmox UI
- [x]  Can SSH to each from workstation using key auth:

    ```bash
    ssh dalton@192.168.40.51  # nfs-server (cloud-init creates dalton)
    ssh dalton@192.168.40.52  # mgmt-plane (cloud-init creates dalton)
    ssh root@192.168.40.53    # garage (LXC — Proxmox injects keys for root only)
    ssh dalton@192.168.40.33  # gimli (cloud-init creates dalton)
    ```

    > **Note (LXC vs VM access):** Proxmox LXC containers don't support cloud-init user creation — the `user_account { keys }` block injects SSH keys for `root`, not a named user. Ansible inventory handles this via `ansible_user: root` on the `proxmox_lxc` group. The `common.yaml` base play still creates the `dalton` user on LXC containers for interactive SSH, but Ansible itself always connects as root. This is a deliberate design decision — see the `common.yaml` annotations below.

- [x]  Each VM/LXC can ping gandalf (192.168.40.30) and vice versa
- [x]  `terraform state list` shows all resources
- [x]  Commit Terraform code (excluding `.tfvars` with secrets)

---

## Phase 2: Ansible — Update Inventory & Roles

**Goal:** `homelab-ansible` updated with new VM inventory and roles for all new machines.

### 2a. Update Inventory

- [x]  Add new hosts to your Ansible inventory:

```yaml
all:
  vars:
    ansible_user: dalton
    ansible_become: true
  children:
    baremetal:
      hosts:
        gandalf:
          ansible_host: 192.168.40.30
        aragorn:
          ansible_host: 192.168.40.31
        legolas:
          ansible_host: 192.168.40.32
    proxmox_vms:
      hosts:
        nfs-server:
          ansible_host: 192.168.40.51
        mgmt-plane:
          ansible_host: 192.168.40.52
        gimli:
          ansible_host: 192.168.40.33
    proxmox_lxc:
      vars:
        ansible_user: root       # LXC containers only get root SSH from Proxmox
        ansible_become: false     # Already root — no sudo needed
      hosts:
        garage:
          ansible_host: 192.168.40.53
    # All managed hosts — base config (SSH, user, node-exporter, timezone)
    linux_hosts:
      children:
        baremetal:
        proxmox_vms:
        proxmox_lxc:
    # Logical service groups
    nfs:
      hosts:
        nfs-server:
    object_storage:
      hosts:
        garage:
    fellowship_control_plane:
      hosts:
        gandalf:
    fellowship_workers:
      hosts:
        aragorn:
        legolas:
        gimli:
    mgmt_control_plane:
      hosts:
        mgmt-plane:
    k3s_all:
      children:
        fellowship_control_plane:
        fellowship_workers:
        mgmt_control_plane:
```

### 2b. Update k3s Playbooks for Cilium

- [x]  Update the control plane playbook (`k3s-server.yaml`):

```yaml
- name: Install k3s control plane
  hosts: fellowship_control_plane
  become: true
  tasks:
    - name: Install k3s server
      shell: >
        curl -sfL https://get.k3s.io | sh -s - server
        --write-kubeconfig-mode 644
        --disable servicelb
        --disable traefik
        --flannel-backend=none
        --disable-network-policy
        --disable-kube-proxy
        --node-ip {{ ansible_host }}
        --tls-san {{ ansible_host }}
      args:
        creates: /etc/rancher/k3s/k3s.yaml
```

- [x]  Update the worker/agent playbook (`k3s-agent.yaml`):

```yaml
- name: Install k3s workers
  hosts: fellowship_workers
  become: true
  tasks:
    - name: Install k3s agent
      shell: >
        curl -sfL https://get.k3s.io | sh -s - agent
        --server https://192.168.40.30:6443
        --token {{ k3s_token }}
        --node-ip {{ ansible_host }}
      args:
        creates: /etc/rancher/k3s/k3s.yaml
```

### 2c. Create Ansible Playbooks/Roles

- [x]  **Playbook: `common.yaml`** — two plays in one file:

    **Play 1: Base configuration (`linux_hosts`)** — every managed host gets this:
    - Update apt cache
    - Install base packages (curl, wget, vim, htop, jq, prometheus-node-exporter)
    - Enable and start `prometheus-node-exporter`
    - Ensure `dalton` user exists with sudo and SSH authorized key
    - Set timezone (America/Denver)
    - Harden SSH: disable password auth (all hosts), disable root login (skipped on LXC where `ansible_user == root`)

    **Play 2: k3s node configuration (`k3s_all`)** — only k3s cluster members:
    - Full package upgrade (`apt dist-upgrade`)
    - Install `nfs-common`
    - Disable and remove swap

    - **No UFW or iptables** — Cilium eBPF manages network policy. Host-level firewalling would conflict with Cilium's dataplane.

    > **Blog note — LXC bootstrap pattern:** Proxmox LXC containers don't support cloud-init user creation (only VMs do). The `proxmox_lxc` inventory group overrides `ansible_user: root` because that's the only SSH access Terraform can provision. The `common.yaml` base play creates the `dalton` user for interactive SSH but Ansible always connects as root. The "disable root login" hardening task uses a `when: ansible_user != 'root'` guard to avoid locking Ansible out — this is an intentional tradeoff where the security delta is negligible (VMs use NOPASSWD sudo, so key compromise gives root either way). This is a good architectural decision to discuss in the blog post.
- [ ]  **Playbook: `nfs-server.yaml`**
    - Install ZFS: `apt install zfsutils-linux`
    - Create ZFS pool: `zpool create tank /dev/sdX` (where sdX is the data disk)
    - Create dataset: `zfs create tank/k8s`
    - Set compression: `zfs set compression=lz4 tank/k8s`
    - Install NFS server: `apt install nfs-kernel-server`
    - Configure `/etc/exports`:

        ```
        /tank/k8s 192.168.40.0/24(rw,sync,no_subtree_check,root_squash)
        ```

    - Enable and start NFS server
    - Install `zfs-auto-snapshot` or create systemd timers for snapshots:
        - Hourly snapshots, keep 24
        - Daily snapshots, keep 30
        - Weekly snapshots, keep 8

> **Canonical NFS path:** `/tank/k8s` on `192.168.40.51`. All StorageClasses, cloud-init configs, and Ansible playbooks must reference this exact path and IP.

- [ ]  **Playbook: `garage.yaml`**
    - Download Garage binary (latest stable release)
    - Ensure `/mnt/data` (Terraform's 200GB data volume) is writable
    - Create Garage config file (`/etc/garage.toml`):

        ```toml
        metadata_dir = "/var/lib/garage/meta"
        data_dir = "/mnt/data"
        db_engine = "lmdb"

        replication_factor = 1

        [s3_api]
        s3_region = "garage"
        api_bind_addr = "[::]:3900"
        root_domain = ".s3.garage.local"

        [s3_web]
        bind_addr = "[::]:3902"
        root_domain = ".web.garage.local"

        [admin]
        api_bind_addr = "[::]:3903"

        [rpc]
        bind_addr = "[::]:3901"
        secret = "GENERATE_A_SECRET_HERE"
        ```

    - Create systemd service with `DynamicUser=true` and `StateDirectory=garage` (per [Garage docs](https://garagehq.deuxfleurs.fr/documentation/cookbook/systemd/))
    - Enable and start Garage
    - Initialize cluster layout: `garage layout assign -z dc1 -c 200G <node-id>`
    - Apply layout: `garage layout apply`
    - Create access key: `garage key create homelab-service-key`
    - Create buckets:
        - `garage bucket create loki-chunks`
    - Grant key permissions on each bucket:
        - `garage bucket allow --read --write --owner loki-chunks --key homelab-service-key`

> **Note:** Additional buckets (velero-backups, pgbackrest) will be created when those features are added in the Upgrades section.

> **Blog note — Garage DynamicUser hardening:** The systemd unit uses `DynamicUser=true` + `StateDirectory=garage` per the official Garage docs. This means Garage runs as a transient non-root user with a dynamic UID — it can only write to `/var/lib/garage` (metadata, managed by systemd) and `/mnt/data` (object storage, the 200GB Terraform volume via `ReadWritePaths`). Do NOT pre-create `/var/lib/garage` — systemd manages it. The `data_dir` was corrected from `/var/lib/garage/data` (8GB root disk) to `/mnt/data` (the actual 200GB data volume from Terraform). This is a good example of defense-in-depth to discuss alongside the Kyverno `require-non-root` policy in the blog post.

- [ ]  **Playbook: `mgmt-plane.yaml`**
    - Install k3s in single-node server mode:

        ```bash
        curl -sfL https://get.k3s.io | sh -s - server \
          --write-kubeconfig-mode 644 \
          --disable servicelb \
          --disable traefik
        ```

        > Note: mgmt cluster does NOT need Cilium/Gateway API — it's a simple single-node cluster for internal observability. Default Flannel is fine here.

    - Copy kubeconfig to a known location for Flux bootstrap

### 2d. Run Ansible

- [ ]  Run the `common` playbook against all hosts (bare-metal, VMs, and LXC containers):

    ```bash
    ansible-playbook -i inventory.yaml playbooks/common.yaml --ask-vault-pass
    ```

- [ ]  Run the `nfs-server` playbook:

    ```bash
    ansible-playbook -i inventory.yaml playbooks/nfs-server.yaml
    ```

- [ ]  Run the `garage` playbook:

    ```bash
    ansible-playbook -i inventory.yaml playbooks/garage.yaml
    ```

- [ ]  Run the `mgmt-plane` playbook:

    ```bash
    ansible-playbook -i inventory.yaml playbooks/mgmt-plane.yaml
    ```

- [ ]  Do NOT run k3s install on any workers yet — no workers should join until Cilium is running on the control plane

### Verification

- [ ]  NFS: From any existing cluster node, test mount:

    ```bash
    sudo mount -t nfs 192.168.40.51:/tank/k8s /mnt/test
    touch /mnt/test/hello
    ls /mnt/test/hello  # Should exist
    sudo umount /mnt/test
    ```

- [ ]  ZFS: On nfs-server:

    ```bash
    zpool status tank          # Pool healthy
    zfs list                    # Dataset visible
    zfs get compression tank/k8s  # Shows lz4
    ```

- [ ]  Garage: From workstation or any node, test S3 access:

    ```bash
    aws --endpoint-url http://192.168.40.53:3900 s3 ls
    # Should list your buckets
    ```

- [ ]  mgmt-plane: SSH in and verify k3s:

    ```bash
    kubectl get nodes  # Single node, Ready
    ```

- [ ]  node_exporter: On each node, curl `http://localhost:9100/metrics` returns Prometheus metrics
- [ ]  Commit all Ansible changes to `homelab-ansible`

---

## Phase 3: Workload Cluster Rebuild — Cilium Migration

**Goal:** Workload cluster (gandalf, aragorn, legolas, gimli) rebuilt with Cilium as CNI, kube-proxy replaced, Gateway API enabled, L2 load balancing active.

> ⚠️ **This is destructive.** You are reinstalling k3s on all existing nodes. Back up anything you need from the current cluster first. Since your GitOps repo has all manifests, the cluster state is recoverable, but be deliberate.

### 3a. Back Up Current State

- [ ]  Export any resources not yet in your Git repo:

    ```bash
    kubectl get all --all-namespaces -o yaml > cluster-backup.yaml
    ```

- [ ]  Verify your `homelab-gitops` repo has all the manifests you need
- [ ]  Note down your cert-manager ClusterIssuer config, ESO ClusterSecretStore — these will be redeployed via ArgoCD

### 3b. Tear Down Existing Cluster

- [ ]  On each worker (aragorn, legolas):

    ```bash
    /usr/local/bin/k3s-agent-uninstall.sh
    ```

- [ ]  On control plane (gandalf):

    ```bash
    /usr/local/bin/k3s-uninstall.sh
    ```

- [ ]  Verify k3s is fully removed from all nodes:

    ```bash
    which k3s         # Should not exist
    ls /etc/rancher/  # Should not exist
    ```

### 3c. Reinstall k3s with Cilium Flags

- [ ]  Run updated Ansible playbook for control plane (gandalf):

    ```bash
    ansible-playbook -i inventory.yaml playbooks/k3s-server.yaml
    ```

    This installs k3s with: `--flannel-backend=none --disable-network-policy --disable-kube-proxy --disable traefik --disable servicelb`

- [ ]  Verify gandalf is up (node will be `NotReady` — this is expected, no CNI yet):

    ```bash
    kubectl get nodes
    # NAME      STATUS     ROLES                  AGE   VERSION
    # gandalf   NotReady   control-plane,master   30s   v1.xx.x
    ```

### 3d. Install Cilium

- [ ]  Install Cilium CLI on your workstation:

    ```bash
    CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
    curl -L --fail --remote-name-all \
      https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz
    sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin
    ```

- [ ]  Install Cilium via Helm (bootstrap manually — ArgoCD will adopt it in Phase 4):

    ```bash
    helm repo add cilium https://helm.cilium.io/
    helm repo update

    helm install cilium cilium/cilium --version 1.17.x \
      --namespace kube-system \
      --set kubeProxyReplacement=true \
      --set k8sServiceHost=192.168.40.30 \
      --set k8sServicePort=6443 \
      --set gatewayAPI.enabled=true \
      --set l2announcements.enabled=true \
      --set externalIPs.enabled=true \
      --set hubble.enabled=true \
      --set hubble.relay.enabled=true \
      --set hubble.ui.enabled=true \
      --set operator.replicas=1 \
      --set ipam.operator.clusterPoolIPv4PodCIDRList="10.42.0.0/16"
    ```

    > Adjust `--version` to the latest stable 1.17.x release. The `k8sServiceHost` and port point to your control plane since kube-proxy is disabled. `l2announcements.enabled` and `externalIPs.enabled` replace MetalLB entirely.

- [ ]  Wait for Cilium to be ready:

    ```bash
    cilium status --wait
    ```

- [ ]  Verify gandalf becomes `Ready`:

    ```bash
    kubectl get nodes
    # NAME      STATUS   ROLES                  AGE    VERSION
    # gandalf   Ready    control-plane,master   5m     v1.xx.x
    ```

### 3e. Apply Cilium L2 Configuration

- [ ]  Create the LoadBalancer IP pool and L2 announcement policy:

    ```bash
    kubectl apply -f - <<EOF
    apiVersion: cilium.io/v2alpha1
    kind: CiliumLoadBalancerIPPool
    metadata:
      name: homelab-pool
    spec:
      blocks:
        - start: 192.168.40.240
          stop: 192.168.40.250
    ---
    apiVersion: cilium.io/v2alpha1
    kind: CiliumL2AnnouncementPolicy
    metadata:
      name: default-l2
    spec:
      loadBalancerIPs: true
    EOF
    ```

- [ ]  Verify the pool is recognized:

    ```bash
    kubectl get ciliumloadbalancerippool
    # NAME           DISABLED   CONFLICTING   IPS AVAILABLE   AGE
    # homelab-pool   false      False         11              10s
    ```

### 3f. Join All Workers

> **Important:** No workers should join until Cilium is running. This applies to all workers equally — aragorn, legolas, and gimli.

- [ ]  Run Ansible for all workers:

    ```bash
    ansible-playbook -i inventory.yaml playbooks/k3s-agent.yaml
    ```

- [ ]  Wait for all workers to become `Ready`:

    ```bash
    kubectl get nodes
    # NAME      STATUS   ROLES                  AGE    VERSION
    # gandalf   Ready    control-plane,master   10m    v1.xx.x
    # aragorn   Ready    <none>                 2m     v1.xx.x
    # legolas   Ready    <none>                 2m     v1.xx.x
    # gimli     Ready    <none>                 2m     v1.xx.x
    ```

- [ ]  Label gimli as a Proxmox-hosted node:

    ```bash
    kubectl label node gimli topology.kubernetes.io/zone=proxmox
    ```

### 3g. Verify Cilium, Hubble & L2

- [ ]  Run Cilium connectivity test:

    ```bash
    cilium connectivity test
    ```

    > This creates test pods across nodes and verifies networking, DNS, NetworkPolicy enforcement. It takes a few minutes.

- [ ]  Verify Hubble is working:

    ```bash
    cilium hubble port-forward &
    hubble observe --follow
    ```

    > You should see flow logs appearing in real time.

- [ ]  Verify Gateway API CRDs are installed:

    ```bash
    kubectl get crd | grep gateway
    # Should show: gateways.gateway.networking.k8s.io, httproutes.gateway.networking.k8s.io, etc.
    ```

- [ ]  Verify L2 announcements are working — create a test LoadBalancer service:

    ```bash
    kubectl create deployment nginx-test --image=nginx:1.27
    kubectl expose deployment nginx-test --type=LoadBalancer --port=80
    kubectl get svc nginx-test
    # Should show an EXTERNAL-IP from 192.168.40.240-250
    curl http://<EXTERNAL-IP>
    # Should return nginx welcome page
    kubectl delete deployment nginx-test
    kubectl delete svc nginx-test
    ```

### Verification

- [ ]  All 4 nodes `Ready`
- [ ]  `cilium status` shows all agents healthy
- [ ]  `cilium connectivity test` passes
- [ ]  `hubble observe` shows flows
- [ ]  `kubectl get crd | grep gateway` shows Gateway API CRDs
- [ ]  No kube-proxy pods running: `kubectl get pods -n kube-system | grep kube-proxy` returns nothing
- [ ]  LoadBalancer services get IPs from Cilium L2 pool
- [ ]  No MetalLB components anywhere in the cluster

---

## Phase 4: ArgoCD & Core Platform Bootstrap

**Goal:** ArgoCD redeployed, core platform services restored and operational.

### 4a. Install ArgoCD

- [ ]  Install ArgoCD via Helm (bootstrap — ArgoCD will manage itself after):

    ```bash
    kubectl create namespace argocd

    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo update

    helm install argocd argo/argo-cd \
      --namespace argocd \
      --set server.insecure=true  # TLS terminates at Gateway
    ```

- [ ]  Verify ArgoCD pods are running:

    ```bash
    kubectl get pods -n argocd
    ```

- [ ]  Get initial admin password:

    ```bash
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
    ```

### 4b. Deploy Root Application (App of Apps)

- [ ]  Ensure your `homelab-gitops` repo has the updated `argocd/root.yaml` pointing to the correct repo URL and path
- [ ]  Apply the AppProject (update to remove MetalLB, add Gateway API CRDs):

    ```yaml
    apiVersion: argoproj.io/v1alpha1
    kind: AppProject
    metadata:
      name: homelab
      namespace: argocd
    spec:
      description: Homelab GitOps project
      sourceRepos:
        - https://github.com/DaltonBuilds/homelab-gitops
        - https://charts.jetstack.io
        - https://charts.external-secrets.io
        - https://helm.cilium.io
        - https://helm.releases.hashicorp.com
      destinations:
        - server: https://kubernetes.default.svc
          namespace: '*'
      clusterResourceWhitelist:
        - group: ''
          kind: Namespace
        - group: cert-manager.io
          kind: ClusterIssuer
        - group: external-secrets.io
          kind: ClusterSecretStore
        - group: cilium.io
          kind: CiliumLoadBalancerIPPool
        - group: cilium.io
          kind: CiliumL2AnnouncementPolicy
        - group: gateway.networking.k8s.io
          kind: Gateway
        - group: gateway.networking.k8s.io
          kind: GatewayClass
        - group: gateway.networking.k8s.io
          kind: HTTPRoute
        - group: storage.k8s.io
          kind: StorageClass
    ```

- [ ]  Apply the root app:

    ```bash
    kubectl apply -f argocd/apps/app-project-homelab.yaml
    kubectl apply -f argocd/root.yaml
    ```

### 4c. Adopt Cilium into ArgoCD

> **Critical:** Cilium was installed manually via Helm in Phase 3. ArgoCD needs to take over management without disrupting the running CNI.

- [ ]  Create `argocd/apps/cilium.yaml` ArgoCD Application pointing to the Cilium Helm chart
- [ ]  Create `apps/cilium/values.yaml` with the **exact same Helm values** used in Phase 3d:

    ```yaml
    kubeProxyReplacement: true
    k8sServiceHost: "192.168.40.30"
    k8sServicePort: 6443
    gatewayAPI:
      enabled: true
    l2announcements:
      enabled: true
    externalIPs:
      enabled: true
    hubble:
      enabled: true
      relay:
        enabled: true
      ui:
        enabled: true
    operator:
      replicas: 1
    ipam:
      operator:
        clusterPoolIPv4PodCIDRList:
          - "10.42.0.0/16"
    ```

- [ ]  Move the L2 pool and announcement policy into `apps/cilium/`:
    - `apps/cilium/ip-pool.yaml` — CiliumLoadBalancerIPPool
    - `apps/cilium/l2-policy.yaml` — CiliumL2AnnouncementPolicy

- [ ]  Set sync policy with `ServerSideApply` and `Replace=true` to cleanly adopt existing resources:

    ```yaml
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=false
        - ServerSideApply=true
        - Replace=true
    ```

- [ ]  Sync — ArgoCD should show `Synced` and `Healthy` without restarting Cilium pods
- [ ]  Verify cluster connectivity is uninterrupted after sync

### 4d. Restore Core Services (in ArgoCD sync order)

ArgoCD will begin syncing applications. Use sync waves to control ordering:

1. **External Secrets Operator** (sync wave: 1):
    - [ ]  Sync `external-secrets.yaml` and `external-secrets-store.yaml`
    - [ ]  Verify ClusterSecretStore: `kubectl get clustersecretstore`
2. **cert-manager** (sync wave: 2):
    - [ ]  Sync `cert-manager.yaml` and `cert-manager-config.yaml`
    - [ ]  Verify ClusterIssuer: `kubectl get clusterissuer`
    - [ ]  Verify Cloudflare secret syncs: `kubectl get externalsecret -A`
3. **NFS Provisioner** (sync wave: 3):
    - [ ]  Create `argocd/apps/nfs-provisioner.yaml` pointing to `apps/nfs-provisioner/`
    - [ ]  Ensure StorageClasses point to `192.168.40.51:/tank/k8s`:

        ```yaml
        apiVersion: storage.k8s.io/v1
        kind: StorageClass
        metadata:
          name: nfs-zfs-retain
          annotations:
            storageclass.kubernetes.io/is-default-class: "true"
        provisioner: cluster.local/nfs-subdir-external-provisioner
        parameters:
          server: "192.168.40.51"
          share: "/tank/k8s"
          pathPattern: "${.PVC.namespace}/${.PVC.name}"
        reclaimPolicy: Retain
        allowVolumeExpansion: true
        mountOptions:
          - nfsvers=4.1
        ---
        apiVersion: storage.k8s.io/v1
        kind: StorageClass
        metadata:
          name: nfs-zfs-delete
        provisioner: cluster.local/nfs-subdir-external-provisioner
        parameters:
          server: "192.168.40.51"
          share: "/tank/k8s"
          pathPattern: "${.PVC.namespace}/${.PVC.name}"
        reclaimPolicy: Delete
        allowVolumeExpansion: true
        mountOptions:
          - nfsvers=4.1
        ```

    - [ ]  Sync
    - [ ]  Test dynamic provisioning:

        ```bash
        kubectl apply -f - <<EOF
        apiVersion: v1
        kind: PersistentVolumeClaim
        metadata:
          name: test-pvc
        spec:
          accessModes: [ReadWriteMany]
          storageClassName: nfs-zfs-retain
          resources:
            requests:
              storage: 1Gi
        EOF
        kubectl get pvc test-pvc  # Should be Bound
        kubectl delete pvc test-pvc
        ```

4. **Gateway + Cloudflared** (sync wave: 4):
    - [ ]  Create `apps/gateway/` directory with:
        - `gateway.yaml` — the shared Gateway resource (Cilium GatewayClass, HTTPS listener, cert-manager annotation)
        - No GatewayClass needed — Cilium auto-creates one named `cilium`
    - [ ]  Create `argocd/apps/gateway.yaml` ArgoCD Application
    - [ ]  Sync
    - [ ]  Verify Gateway has an external IP from Cilium L2 pool:

        ```bash
        kubectl get gateway -A
        # homelab-gateway   cilium   True   Programmed   192.168.40.24X
        ```

    - [ ]  Note the Gateway's LoadBalancer IP — Cloudflared needs this
    - [ ]  Update Cloudflared config to point tunnel at the Gateway's LoadBalancer IP
    - [ ]  Create `argocd/apps/cloudflared.yaml` and `apps/cloudflared/` with deployment
    - [ ]  Sync Cloudflared

### 4e. Deploy Platform Ingress (as HTTPRoutes)

- [ ]  Rewrite all files in `apps/platform-ingress/` from `kind: Ingress` to `kind: HTTPRoute`:

    ```yaml
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: argocd-route
      namespace: argocd
    spec:
      parentRefs:
        - name: homelab-gateway
          namespace: gateway
      hostnames:
        - argocd.daltonbuilds.com
      rules:
        - backendRefs:
            - name: argocd-server
              port: 80
    ```

- [ ]  Routes to create:
    - [ ]  `argocd-route.yaml`
    - [ ]  `hubble-route.yaml` (new — expose Hubble UI)
- [ ]  Sync platform-ingress ArgoCD app
- [ ]  Verify ArgoCD is accessible via its hostname through Cloudflared tunnel

### Verification

- [ ]  ArgoCD UI accessible via browser (through tunnel)
- [ ]  All synced ArgoCD applications show `Healthy` and `Synced`
- [ ]  Cilium L2 assigning IPs to LoadBalancer services
- [ ]  cert-manager issuing certificates: `kubectl get certificates -A`
- [ ]  ESO secrets syncing from GCP
- [ ]  NFS StorageClass provisioning PVCs
- [ ]  Gateway has an external IP and is `Programmed`
- [ ]  Cloudflared tunnel routing traffic to Gateway IP

---

## Phase 5: Management Cluster — Observability Stack

**Goal:** Independent Prometheus + Loki + Grafana + Alertmanager on mgmt-plane, managed by Flux.

### 5a. Bootstrap Flux on mgmt-plane

- [ ]  Install Flux CLI on your workstation:

    ```bash
    curl -s https://fluxcd.io/install.sh | sudo bash
    ```

- [ ]  Create `mgmt-cluster/` directory in `homelab-gitops` repo
- [ ]  Bootstrap Flux against the mgmt-plane cluster:

    ```bash
    # Point kubectl at the mgmt-plane cluster
    export KUBECONFIG=/path/to/mgmt-plane-kubeconfig

    flux bootstrap github \
      --owner=DaltonBuilds \
      --repository=homelab-gitops \
      --branch=main \
      --path=mgmt-cluster \
      --personal
    ```

    > This creates the `flux-system/` directory inside `mgmt-cluster/` and configures Flux to watch that path.

### 5b. Deploy Observability Stack via Flux

- [ ]  Create `mgmt-cluster/infrastructure/sources.yaml` — HelmRepository definitions:

    ```yaml
    apiVersion: source.toolkit.fluxcd.io/v1
    kind: HelmRepository
    metadata:
      name: prometheus-community
      namespace: flux-system
    spec:
      interval: 1h
      url: https://prometheus-community.github.io/helm-charts
    ---
    apiVersion: source.toolkit.fluxcd.io/v1
    kind: HelmRepository
    metadata:
      name: grafana
      namespace: flux-system
    spec:
      interval: 1h
      url: https://grafana.github.io/helm-charts
    ```

- [ ]  Create `mgmt-cluster/infrastructure/prometheus/helmrelease.yaml`:

    ```yaml
    apiVersion: helm.toolkit.fluxcd.io/v2
    kind: HelmRelease
    metadata:
      name: kube-prometheus-stack
      namespace: monitoring
    spec:
      interval: 1h
      chart:
        spec:
          chart: kube-prometheus-stack
          sourceRef:
            kind: HelmRepository
            name: prometheus-community
            namespace: flux-system
      values:
        prometheus:
          prometheusSpec:
            retention: 15d
            resources:
              requests:
                memory: 2Gi
                cpu: 500m
              limits:
                memory: 4Gi
            # Scrape workload cluster node-exporters
            additionalScrapeConfigs:
              - job_name: 'workload-nodes'
                static_configs:
                  - targets:
                      - '192.168.40.30:9100'  # gandalf
                      - '192.168.40.31:9100'  # aragorn
                      - '192.168.40.32:9100'  # legolas
                      - '192.168.40.33:9100'  # gimli
                      - '192.168.40.51:9100'  # nfs-server
              - job_name: 'garage'
                static_configs:
                  - targets:
                      - '192.168.40.53:3903'  # Garage admin API exposes metrics
        grafana:
          adminPassword: changeme  # Replace with secret reference
          persistence:
            enabled: true
            size: 5Gi
        alertmanager:
          alertmanagerSpec:
            resources:
              requests:
                memory: 256Mi
              limits:
                memory: 512Mi
    ```

- [ ]  Create `mgmt-cluster/infrastructure/loki/helmrelease.yaml`:

    ```yaml
    apiVersion: helm.toolkit.fluxcd.io/v2
    kind: HelmRelease
    metadata:
      name: loki
      namespace: monitoring
    spec:
      interval: 1h
      chart:
        spec:
          chart: loki
          sourceRef:
            kind: HelmRepository
            name: grafana
            namespace: flux-system
      values:
        deploymentMode: SingleBinary
        loki:
          auth_enabled: false
          storage:
            type: s3
            s3:
              endpoint: http://192.168.40.53:3900
              bucketnames: loki-chunks
              region: garage
              access_key_id: YOUR_KEY      # Use a Kubernetes secret
              secret_access_key: YOUR_SECRET
              s3ForcePathStyle: true
          commonConfig:
            replication_factor: 1
          limits_config:
            retention_period: 720h  # 30 days
        singleBinary:
          replicas: 1
          resources:
            requests:
              memory: 1Gi
              cpu: 250m
            limits:
              memory: 2Gi
    ```

- [ ]  Create Flux Kustomization to tie it all together:

    ```yaml
    # mgmt-cluster/infrastructure/kustomization.yaml
    apiVersion: kustomize.toolkit.fluxcd.io/v1
    kind: Kustomization
    metadata:
      name: infrastructure
      namespace: flux-system
    spec:
      interval: 1h
      sourceRef:
        kind: GitRepository
        name: flux-system
      path: ./mgmt-cluster/infrastructure
      prune: true
    ```

- [ ]  Push to Git — Flux will reconcile automatically

### 5c. Configure Workload Cluster → Management Cluster Data Flow

- [ ]  Deploy **Alloy** as a DaemonSet in the **workload cluster** (via ArgoCD):
    - [ ]  Create `argocd/apps/alloy.yaml`
    - [ ]  Create `apps/monitoring/alloy/values.yaml`:
        - Ship logs to Loki on mgmt-plane: `http://192.168.40.52:3100/loki/api/v1/push`
        - Scrape workload cluster Kubernetes metrics and forward to mgmt Prometheus via remote-write
    - [ ]  Sync via ArgoCD

- [ ]  Configure Grafana data sources on the mgmt cluster (can be done via Helm values or provisioning):
    - Prometheus (local on mgmt-plane)
    - Loki (local on mgmt-plane)
    - Alertmanager (local on mgmt-plane)

- [ ]  Import/build Grafana dashboards:
    - [ ]  Cluster overview (node CPU, RAM, disk)
    - [ ]  Pod health and restarts
    - [ ]  NFS server metrics (from node_exporter on nfs-server VM)
    - [ ]  Cilium/Hubble network flows
    - [ ]  Garage S3 metrics

- [ ]  Configure Alertmanager notification routing:
    - [ ]  Create a Discord webhook (or Slack, email)
    - [ ]  Configure alert routes for: node down, high CPU/memory, NFS unreachable, cert expiry, PVC near capacity
    - [ ]  Test an alert fires and notification arrives

### Verification

- [ ]  Flux reconciliation is healthy: `flux get all` (on mgmt-plane)
- [ ]  Prometheus is scraping targets: check Prometheus UI targets page
- [ ]  Loki is receiving logs: query `{namespace="kube-system"}` in Grafana
- [ ]  Grafana dashboards load with real data
- [ ]  Alertmanager has routes configured: check Alertmanager UI
- [ ]  Test alert notification reaches your channel
- [ ]  Management cluster survives workload cluster being offline (kill a workload node and verify monitoring stays up)

---

## Phase 6: HashiCorp Vault — Dynamic Secrets

**Goal:** Vault deployed on the workload cluster, integrated with ESO for dynamic secret delivery to applications.

> **Why Vault alongside GCP SM?** GCP Secret Manager handles static infrastructure secrets (API tokens, Cloudflare credentials). Vault handles dynamic secrets — short-lived database credentials that are generated on-demand and automatically revoked. Together they demonstrate understanding of when to use each tool. The ESO integration means your GitOps workflow is identical regardless of the secret source.
>
> **Why ESO over VSO (Vault Secrets Operator)?** VSO only speaks Vault, so using it alongside ESO (which handles GCP SM) would mean running two operators for no benefit. More importantly, GCP SM is deliberately kept for bootstrap-critical secrets because Vault has a cold-start dependency — it requires manual unsealing after pod restarts. Secrets needed to bring up cert-manager, Cloudflared, and the rest of the platform must be available before Vault is operational. ESO handles both backends with identical `ExternalSecret` CRDs, keeping application manifests backend-agnostic.

### 6a. Deploy Vault via ArgoCD

- [ ]  Create `argocd/apps/vault.yaml`:

    ```yaml
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: vault
      namespace: argocd
      annotations:
        argocd.argoproj.io/sync-wave: "3"
    spec:
      project: homelab
      source:
        repoURL: https://helm.releases.hashicorp.com
        chart: vault
        targetRevision: 0.29.x  # Check for latest
        helm:
          valuesObject:
            server:
              dataStorage:
                enabled: true
                storageClass: nfs-zfs-retain
                size: 5Gi
              standalone:
                enabled: true
                config: |
                  ui = true
                  listener "tcp" {
                    address = "[::]:8200"
                    tls_disable = 1
                  }
                  storage "raft" {
                    path = "/vault/data"
                  }
              resources:
                requests:
                  memory: 256Mi
                  cpu: 250m
                limits:
                  memory: 512Mi
            ui:
              enabled: true
      destination:
        server: https://kubernetes.default.svc
        namespace: vault
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
    ```

- [ ]  Sync via ArgoCD
- [ ]  Wait for the Vault pod to be running (it will be in `0/1 Running` — not ready until initialized)

### 6b. Initialize and Unseal Vault

- [ ]  Initialize Vault:

    ```bash
    kubectl exec -n vault vault-0 -- vault operator init \
      -key-shares=5 \
      -key-threshold=3 \
      -format=json > vault-init.json
    ```

    > **CRITICAL:** Save `vault-init.json` securely. This contains your unseal keys and initial root token. Store it encrypted on your workstation (e.g., in a GPG-encrypted file or your password manager). Do NOT commit it to Git. Do NOT store it in GCP SM (that's circular — Vault needs to be unsealed before it can serve secrets).

- [ ]  Unseal Vault (need 3 of 5 keys):

    ```bash
    # Repeat with 3 different unseal keys from vault-init.json
    kubectl exec -n vault vault-0 -- vault operator unseal <key-1>
    kubectl exec -n vault vault-0 -- vault operator unseal <key-2>
    kubectl exec -n vault vault-0 -- vault operator unseal <key-3>
    ```

- [ ]  Verify Vault is unsealed and ready:

    ```bash
    kubectl exec -n vault vault-0 -- vault status
    # Sealed: false
    # HA Enabled: false
    ```

- [ ]  Log in with the root token:

    ```bash
    kubectl exec -n vault vault-0 -- vault login <root-token>
    ```

### 6c. Configure Vault Secrets Engines

- [ ]  Enable the **KV v2 secrets engine** (for general secrets):

    ```bash
    kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2
    ```

- [ ]  Enable the **database secrets engine** (for dynamic DB credentials):

    ```bash
    kubectl exec -n vault vault-0 -- vault secrets enable database
    ```

    > The database engine will be configured with specific Postgres connections when applications are deployed (Uptime Kuma in Phase 7, or Authentik/n8n in Upgrades). For now, enabling the engine is sufficient.

- [ ]  Create a policy for ESO to read secrets:

    ```bash
    kubectl exec -n vault vault-0 -- vault policy write eso-reader - <<EOF
    path "secret/data/*" {
      capabilities = ["read"]
    }
    path "database/creds/*" {
      capabilities = ["read"]
    }
    EOF
    ```

### 6d. Enable Kubernetes Auth for ESO

- [ ]  Enable Kubernetes authentication in Vault:

    ```bash
    kubectl exec -n vault vault-0 -- vault auth enable kubernetes
    ```

- [ ]  Configure the Kubernetes auth method:

    ```bash
    kubectl exec -n vault vault-0 -- sh -c '
      vault write auth/kubernetes/config \
        kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"
    '
    ```

- [ ]  Create a role for ESO:

    ```bash
    kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/eso \
      bound_service_account_names=external-secrets \
      bound_service_account_namespaces=external-secrets \
      policies=eso-reader \
      ttl=1h
    ```

### 6e. Add Vault as an ESO SecretStore

- [ ]  Create `apps/external-secrets/vault-secret-store.yaml`:

    ```yaml
    apiVersion: external-secrets.io/v1beta1
    kind: ClusterSecretStore
    metadata:
      name: vault
    spec:
      provider:
        vault:
          server: "http://vault.vault.svc.cluster.local:8200"
          path: "secret"
          version: "v2"
          auth:
            kubernetes:
              mountPath: "kubernetes"
              role: "eso"
              serviceAccountRef:
                name: external-secrets
                namespace: external-secrets
    ```

- [ ]  Sync via ArgoCD
- [ ]  Verify the store is healthy:

    ```bash
    kubectl get clustersecretstore vault
    # NAME    AGE   STATUS   CAPABILITIES   READY
    # vault   30s   Valid    ReadOnly       True
    ```

### 6f. Test the Integration

- [ ]  Write a test secret to Vault:

    ```bash
    kubectl exec -n vault vault-0 -- vault kv put secret/test hello=world
    ```

- [ ]  Create an ExternalSecret that reads from Vault:

    ```bash
    kubectl apply -f - <<EOF
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: vault-test
      namespace: default
    spec:
      refreshInterval: 1m
      secretStoreRef:
        name: vault
        kind: ClusterSecretStore
      target:
        name: vault-test-secret
      data:
        - secretKey: hello
          remoteRef:
            key: test
            property: hello
    EOF
    ```

- [ ]  Verify the secret was created:

    ```bash
    kubectl get secret vault-test-secret -o jsonpath='{.data.hello}' | base64 -d
    # Should output: world
    ```

- [ ]  Clean up test resources:

    ```bash
    kubectl delete externalsecret vault-test
    kubectl delete secret vault-test-secret
    kubectl exec -n vault vault-0 -- vault kv delete secret/test
    ```

### 6g. Create HTTPRoute for Vault UI

- [ ]  Add `apps/platform-ingress/vault-route.yaml`:

    ```yaml
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: vault-route
      namespace: vault
    spec:
      parentRefs:
        - name: homelab-gateway
          namespace: gateway
      hostnames:
        - vault.daltonbuilds.com
      rules:
        - backendRefs:
            - name: vault-ui
              port: 8200
    ```

- [ ]  Add DNS record for vault.daltonbuilds.com in Cloudflare (or add to Cloudflared tunnel config)

### Verification

- [ ]  Vault pod running and unsealed: `kubectl exec -n vault vault-0 -- vault status`
- [ ]  Vault UI accessible via browser
- [ ]  KV v2 and database secrets engines enabled: `vault secrets list`
- [ ]  Kubernetes auth configured: `vault auth list`
- [ ]  ESO ClusterSecretStore for Vault shows `Ready: True`
- [ ]  ExternalSecret successfully pulls from Vault
- [ ]  You now have **two** ClusterSecretStores: `gcp-secret-manager` (static) and `vault` (dynamic)
- [ ]  Root token stored securely offline

> **Operational note:** If the Vault pod restarts (node reboot, pod eviction, etc.), you must unseal it again. This takes ~30 seconds with 3 unseal keys. Auto-unseal via GCP KMS is available as a future upgrade.

---

## Phase 7: Demo Application — Uptime Kuma

**Goal:** Deploy a real application on the platform to prove the full stack works end-to-end.

> Uptime Kuma is ideal for this: it's simple, useful (monitors your other services), and exercises the full platform — NFS storage, Gateway API routing, TLS via cert-manager, external access via Cloudflared, and secrets via ESO.

### 7a. Deploy Uptime Kuma

- [ ]  Create `argocd/apps/uptime-kuma.yaml`:

    ```yaml
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: uptime-kuma
      namespace: argocd
      annotations:
        argocd.argoproj.io/sync-wave: "5"
    spec:
      project: homelab
      source:
        repoURL: https://github.com/DaltonBuilds/homelab-gitops
        path: apps/uptime-kuma
        targetRevision: main
      destination:
        server: https://kubernetes.default.svc
        namespace: uptime-kuma
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
    ```

- [ ]  Create `apps/uptime-kuma/deployment.yaml`:

    ```yaml
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: uptime-kuma
      namespace: uptime-kuma
      labels:
        app.kubernetes.io/name: uptime-kuma
    spec:
      replicas: 1
      selector:
        matchLabels:
          app.kubernetes.io/name: uptime-kuma
      template:
        metadata:
          labels:
            app.kubernetes.io/name: uptime-kuma
        spec:
          containers:
            - name: uptime-kuma
              image: louislam/uptime-kuma:1  # Pin to major version
              ports:
                - containerPort: 3001
              volumeMounts:
                - name: data
                  mountPath: /app/data
              resources:
                requests:
                  memory: 128Mi
                  cpu: 100m
                limits:
                  memory: 256Mi
          volumes:
            - name: data
              persistentVolumeClaim:
                claimName: uptime-kuma-data
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: uptime-kuma
      namespace: uptime-kuma
    spec:
      selector:
        app.kubernetes.io/name: uptime-kuma
      ports:
        - port: 80
          targetPort: 3001
    ---
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: uptime-kuma-data
      namespace: uptime-kuma
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: nfs-zfs-retain
      resources:
        requests:
          storage: 2Gi
    ```

- [ ]  Create `apps/uptime-kuma/httproute.yaml`:

    ```yaml
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: uptime-kuma-route
      namespace: uptime-kuma
    spec:
      parentRefs:
        - name: homelab-gateway
          namespace: gateway
      hostnames:
        - status.daltonbuilds.com
      rules:
        - backendRefs:
            - name: uptime-kuma
              port: 80
    ```

- [ ]  Add DNS record / Cloudflared tunnel config for `status.daltonbuilds.com`
- [ ]  Sync via ArgoCD

### 7b. Configure Monitors

- [ ]  Access Uptime Kuma via browser, create admin account
- [ ]  Add monitors:
    - [ ]  ArgoCD — HTTPS check on `argocd.daltonbuilds.com`
    - [ ]  Vault UI — HTTPS check on `vault.daltonbuilds.com`
    - [ ]  NFS server — TCP check on `192.168.40.51:2049`
    - [ ]  Garage — HTTP check on `http://192.168.40.53:3903/health`
    - [ ]  Grafana — will be added after setting up mgmt cluster ingress (or use direct IP)

### Verification

- [ ]  Uptime Kuma shows `Healthy` and `Synced` in ArgoCD
- [ ]  Accessible via `status.daltonbuilds.com` through Cloudflared tunnel
- [ ]  TLS certificate issued by cert-manager
- [ ]  PVC bound on `nfs-zfs-retain` StorageClass
- [ ]  Monitors are active and reporting status
- [ ]  This proves the full pipeline: Git → ArgoCD → Kubernetes → Cilium Gateway → Cloudflared → browser

---

## Phase 8: Documentation & Portfolio Polish

**Goal:** Make the repos something you'd be proud to share with a hiring manager.

### 8a. Architecture Diagram

- [ ]  Create a Mermaid diagram (or draw.io exported to SVG) showing:
    - Physical machines and VMs
    - Network topology (VLANs 10, 40)
    - Data flow: user → Cloudflare → Cloudflared → Cilium Gateway → services
    - Monitoring flow: workload cluster → Alloy → mgmt cluster (Prometheus/Loki/Grafana)
    - Secrets flow: GCP SM → ESO → Kubernetes secrets (static), Vault → ESO → Kubernetes secrets (dynamic)
- [ ]  Commit diagram to `docs/` and reference in root README

### 8b. Root README.md (for homelab-gitops)

- [ ]  Technology stack table with one-line rationale per tool:

    | Component | Tool | Why |
    | --- | --- | --- |
    | CNI | Cilium | eBPF-based, replaces kube-proxy, native L2 LB + Gateway API |
    | Load Balancing | Cilium L2 | Consolidated into CNI — no separate MetalLB needed |
    | Ingress | Cilium Gateway API | Kubernetes-native, vendor-neutral, replaces Traefik |
    | GitOps (workload) | ArgoCD | App-of-apps pattern, UI for visibility |
    | GitOps (mgmt) | Flux | Demonstrates multi-tool breadth, lightweight |
    | Storage (file) | NFS + ZFS | Snapshots, compression, proven reliability |
    | Storage (object) | Garage | S3-compatible, 1GB RAM vs MinIO's 4-6GB |
    | Secrets (static) | ESO + GCP SM | No plaintext in Git, cloud-grade secret management |
    | Secrets (dynamic) | Vault | Short-lived DB credentials, auto-rotation, Secret Zero |
    | TLS | cert-manager | Automated Let's Encrypt via DNS-01 |
    | Tunnel | Cloudflared | Zero-trust external access, no port forwarding |
    | Observability | Prometheus + Loki + Grafana | Industry standard, Alloy for unified collection |
    | IaC | Terraform | Proxmox VMs as code via bpg/proxmox provider |
    | Config Mgmt | Ansible | OS-level config, k3s bootstrap, SSH hardening |

- [ ]  Architecture diagram (embedded)
- [ ]  Repo structure explanation
- [ ]  Quick links to docs

### 8c. Key Documentation

- [ ]  `docs/architecture.md` — Architecture Decision Records (ADRs):
    - Why Cilium over Flannel (eBPF, kube-proxy replacement, L2 LB, Gateway API — one tool for four functions)
    - Why Cilium L2 over MetalLB (reduce component count, Cilium already owns the dataplane)
    - Why Gateway API over Traefik Ingress (Kubernetes-native, vendor-neutral, growing ecosystem standard)
    - Why NFS/ZFS over Longhorn (ZFS snapshots, compression, proven at scale, simpler failure domain)
    - Why Garage over MinIO (memory footprint, single-binary, S3-compatible for the same use cases)
    - Why ESO + GCP SM over Sealed Secrets (central management, audit log, no encryption key management)
    - Why Vault for dynamic secrets (Secret Zero, automatic credential rotation, lease-based revocation)
    - Why ESO over VSO (VSO is Vault-only; ESO handles both GCP SM and Vault with identical CRDs; GCP SM is kept for bootstrap-critical secrets that must be available before Vault unseal)
    - Why independent management cluster (observability survives workload cluster failures)
- [ ]  `docs/network-topology.md` — VLANs, IP allocation, Cilium L2 pool

### Verification

- [ ]  README renders well on GitHub
- [ ]  Architecture diagram is clear and accurate
- [ ]  ADRs are written and committed
- [ ]  No plaintext secrets anywhere in the repo (`git log --all -p | grep -i "password\|secret\|token\|key"` to check)
- [ ]  You can explain every architectural decision if asked in an interview

---

## Post-MVP: Ongoing Operations

These aren't build steps but habits to maintain:

- [ ]  Monitor Alertmanager notifications — respond to alerts
- [ ]  Keep Helm charts updated (Renovate Bot is a great future addition for automated PRs)
- [ ]  Practice explaining each architectural decision aloud — prepare for interview questions
- [ ]  After Vault pod restarts, unseal within a reasonable window

---

## Upgrades — Post-MVP Enhancements

Everything below is deferred from the MVP. Each section is self-contained and can be tackled independently in any order. They build on the foundation established in Phases 0–8.

---

### Upgrade: Kyverno — Policy Enforcement

**Value:** Admission control preventing misconfigurations. Shows understanding of Kubernetes security posture management.

**What to deploy:**
- Kyverno controller via ArgoCD Helm chart
- Separate ArgoCD app for policies (update policies without restarting controller)
- Policies to create (start in `Audit` mode, switch to `Enforce` after fixing violations):
    - `disallow-privileged.yaml` — no privileged containers
    - `require-resource-limits.yaml` — all pods must have resource requests/limits
    - `require-labels.yaml` — require `app.kubernetes.io/name` and `app.kubernetes.io/part-of`
    - `restrict-image-registries.yaml` — allow only docker.io, ghcr.io, quay.io, registry.k8s.io
    - `disallow-latest-tag.yaml` — no `:latest` image tags
    - `require-non-root.yaml` — all containers run as non-root
    - `auto-inject-labels.yaml` — mutating policy to auto-add `managed-by: argocd`

**AppProject update:** Add Kyverno CRDs to `clusterResourceWhitelist`.

**Interview talking point:** "I use Kyverno for admission control — policies start in audit mode so I can fix existing violations before enforcement. This prevents deploying misconfigured workloads while avoiding a flag-day migration."

---

### Upgrade: Velero — Disaster Recovery

**Value:** Scheduled cluster-state backups with tested restore. Shows operational maturity.

**Prerequisites:** Create `velero-backups` bucket in Garage: `garage bucket create velero-backups`

**What to deploy:**
- Velero via ArgoCD Helm chart
- BackupStorageLocation pointing to Garage S3 (`http://192.168.40.53:3900`, bucket `velero-backups`)
- Garage credentials via ESO (from GCP SM or Vault)
- Scheduled backup: daily at 3 AM, 30-day retention, all namespaces, fsBackup for PVCs

**Critical step:** Test the restore procedure. An untested backup is not a backup.

```bash
# Create test namespace, take backup, delete namespace, restore, verify
velero backup create test-backup --include-namespaces velero-test
kubectl delete namespace velero-test
velero restore create --from-backup test-backup
```

---

### Upgrade: ARC — Self-Hosted CI Runners

**Value:** GitHub Actions runners as ephemeral Kubernetes pods. Shows CI/CD automation at the infrastructure level.

**What to deploy:**
- ARC controller: `oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller`
- RunnerScaleSet: `oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set`
- GitHub PAT or GitHub App credentials via ESO
- Scale from 0 runners when idle, max 3 when jobs are queued

**Important:** Pin the runner image to a specific version (not `:latest`) — especially if Kyverno is deployed.

**Test with:**
```yaml
# .github/workflows/test-runner.yml
name: Test Self-Hosted Runner
on: workflow_dispatch
jobs:
  test:
    runs-on: arc-runner-set
    steps:
      - run: echo "Running on self-hosted ARC runner!"
```

---

### Upgrade: Authentik — Identity Provider / SSO

**Value:** Centralized authentication. Shows understanding of identity management in a platform context.

**What to deploy:**
- Authentik via ArgoCD Helm chart
- Postgres database for Authentik on `nfs-zfs-retain` StorageClass
- HTTPRoute for `auth.daltonbuilds.com`
- All secrets via ESO

**Dynamic DB credentials via Vault:**
This is where Vault's database secrets engine shines. Configure Vault to generate short-lived Postgres credentials for Authentik:

```bash
vault write database/config/authentik-postgres \
  plugin_name=postgresql-database-plugin \
  connection_url="postgresql://{{username}}:{{password}}@authentik-postgres.authentik.svc:5432/authentik?sslmode=disable" \
  allowed_roles="authentik-app" \
  username="vault_admin" \
  password="INITIAL_PASSWORD"

vault write database/roles/authentik-app \
  db_name=authentik-postgres \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT ALL ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"
```

Then ESO pulls dynamic creds via: `vault read database/creds/authentik-app`

**Integrate with:**
- Grafana (OAuth2 login)
- ArgoCD (OIDC login)
- Vault UI (OIDC login)

---

### Upgrade: n8n — Workflow Automation

**Value:** Self-hosted workflow automation platform for homelab integrations.

**What to deploy:**
- n8n via ArgoCD Helm chart
- Postgres (can share instance with Authentik or run separately)
- PVC on `nfs-zfs-retain` for n8n data
- HTTPRoute for `n8n.daltonbuilds.com`
- All secrets via ESO

---

### Upgrade: pgBackRest — Database WAL Archiving

**Value:** Point-in-time recovery for Postgres databases. Enterprise-grade database DR.

**When to add:** When you have multiple Postgres instances (Authentik, n8n) and want to demonstrate advanced database operations knowledge.

**What to deploy:**
- pgBackRest configured per Postgres instance
- S3 repository pointing to Garage `pgbackrest` bucket
- Full backup weekly, differential daily
- WAL archiving enabled (enables PITR)

**Create bucket:** `garage bucket create pgbackrest`

**Interview talking point:** "For my homelab scale, pg_dump is sufficient. But I've implemented pgBackRest to demonstrate understanding of WAL archiving and point-in-time recovery — the kind of setup you'd need for production databases where full dumps are impractical and RPO requirements are tight."

---

### Upgrade: restic — Offsite Backups to Workstation

**Value:** 3-2-1 backup rule compliance. Shows operational rigor.

**Strategy by data type:**
1. **Cluster state:** Already covered by Velero → Garage
2. **ZFS data:** `zfs send` (incremental) → workstation — far more efficient than restic for ZFS
3. **Garage data:** restic → workstation via SFTP
4. **Infrastructure:** Terraform + Ansible are the backup (rebuild from code)

**What to deploy:**
- restic configured with SFTP backend to workstation
- systemd timer for nightly runs
- Retention: keep 7 daily, 4 weekly, 6 monthly
- Alertmanager rule for stale backups

---

### Upgrade: NetworkPolicies & Hardening

**Value:** Defense-in-depth. Shows security awareness beyond "it works."

**What to deploy:**
- Default-deny NetworkPolicy for every namespace
- Explicit allow policies: DNS egress, Gateway ingress, Prometheus scraping, app-specific egress
- RBAC review: no unnecessary cluster-admin bindings
- k3s API server audit logging
- (Optional) CiliumNetworkPolicies for L7 filtering

**Test thoroughly:** A curl pod in a locked-down namespace should be blocked. Legitimate traffic should still work.

---

### Upgrade: Trivy Operator — Vulnerability Scanning

**Value:** Continuous image vulnerability scanning. Lightweight addition.

**What to deploy:**
- Trivy Operator via ArgoCD Helm chart
- Review VulnerabilityReports: `kubectl get vulnerabilityreports -A`
- Alertmanager rules for critical/high CVEs

---

### Upgrade: Vault Auto-Unseal via GCP KMS

**Value:** Vault automatically unseals after pod restarts without manual intervention.

**What to configure:**
- Create a GCP KMS key ring and crypto key
- Update Vault config to use GCP KMS seal stanza:

    ```hcl
    seal "gcpckms" {
      project     = "homelab-forge"
      region      = "us-central1"
      key_ring    = "vault-unseal"
      crypto_key  = "vault-key"
    }
    ```

- Migrate from Shamir to auto-unseal: `vault operator unseal -migrate`

---

### Upgrade: Full Documentation Suite

**Additional docs beyond the MVP README and architecture.md:**
- `docs/disaster-recovery.md` — Step-by-step restore procedures for each backup path
- `docs/adding-an-app.md` — How to onboard a new service to the platform
- Per-app `README.md` in each `apps/` subdirectory

---

## Final Repo Structure (MVP + Upgrades path)

```
homelab-gitops/
├── README.md
├── docs/
│   ├── architecture.md          # ADRs
│   └── network-topology.md      # VLANs, IPs, Cilium L2
├── argocd/
│   ├── root.yaml
│   └── apps/
│       ├── app-project-homelab.yaml
│       ├── cilium.yaml
│       ├── cert-manager.yaml
│       ├── cert-manager-config.yaml
│       ├── external-secrets.yaml
│       ├── external-secrets-store.yaml
│       ├── nfs-provisioner.yaml
│       ├── gateway.yaml
│       ├── cloudflared.yaml
│       ├── vault.yaml
│       ├── alloy.yaml
│       ├── platform-ingress.yaml
│       └── uptime-kuma.yaml
├── apps/
│   ├── cilium/
│   │   ├── values.yaml
│   │   ├── ip-pool.yaml
│   │   └── l2-policy.yaml
│   ├── cert-manager/
│   │   ├── cloudflare-secret.yaml
│   │   └── cluster-issuer.yaml
│   ├── external-secrets/
│   │   ├── cluster-secret-store.yaml       # GCP SM
│   │   └── vault-secret-store.yaml         # Vault
│   ├── gateway/
│   │   └── gateway.yaml
│   ├── nfs-provisioner/
│   │   ├── storageclass-nfs-zfs-retain.yaml
│   │   └── storageclass-nfs-zfs-delete.yaml
│   ├── vault/
│   │   └── (managed via Helm values in ArgoCD app)
│   ├── monitoring/
│   │   └── alloy/
│   │       └── values.yaml
│   ├── platform-ingress/
│   │   ├── argocd-route.yaml
│   │   ├── hubble-route.yaml
│   │   └── vault-route.yaml
│   ├── cloudflared/
│   │   └── deployment.yaml
│   └── uptime-kuma/
│       ├── deployment.yaml
│       └── httproute.yaml
└── mgmt-cluster/
    ├── flux-system/
    │   ├── gotk-components.yaml
    │   ├── gotk-sync.yaml
    │   └── kustomization.yaml
    └── infrastructure/
        ├── kustomization.yaml
        ├── sources.yaml
        ├── prometheus/
        │   └── helmrelease.yaml
        ├── loki/
        │   └── helmrelease.yaml
        └── grafana/
            ├── helmrelease.yaml
            └── dashboards/
```
