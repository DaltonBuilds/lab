# **Kubernetes YAML Validation & Formatting**

**1. Native Validation (The `terraform validate` Alt)**

`kubectl` provides two levels of validation to catch indentation errors and invalid properties.

- **Client-Side Validation:** Quick local check against the OpenAPI schema. Good for catching basic typos without a cluster connection.
    
    **bash**
    
    `kubectl apply -f your-file.yaml --dry-run=client`
    
- **Server-Side Validation:** The most accurate check. It sends the manifest to the API server to be processed by the admission chain (validating CRDs, webhooks, and permissions) without persisting it.
    
    **bash**
    
    `kubectl apply -f your-file.yaml --dry-run=server`

**2. Native Formatting (The `terraform fmt` Alt)**

While `kubectl` lacks a dedicated "format" command, you can use the API server's output engine to "round-trip" your file into a standardized structure.

- **Reformat & Standardize:** This reads your input and spits out a "valid" YAML with standard indentation.
    
    **bash**
    
    `kubectl create -f input.yaml --dry-run=client -o yaml > formatted.yaml`

**3. Advanced Linting & Cleanup (Krew Plugins)**

Krew plugins are industry standards for maintaining clean manifests:

- [**kubectl-neat](https://github.com/itaysk/kubectl-neat):** Strips out redundant system-generated fields (like `status`, `uid`, and `creationTimestamp`) to keep your YAMLs human-readable and portable.
    
    **bash**
    
    `kubectl neat -f messy-file.yaml > clean-runbook.yaml`
    
- **Kubeconform:** A high-performance local validator that is often preferred over `kubectl --dry-run=client` because it can validate against specific Kubernetes versions and external schemas.
- **Kube-Linter:** Goes beyond syntax to check for **security best practices** (e.g., "running as root" or "missing resource limits").

**4. Quick Resource Inspection**

- **`kubectl explain`**: If you aren't sure which properties are missing, use this for "man-page" style documentation of any resource field.
    
    **bash**
    
    `kubectl explain pod.spec.containers`
