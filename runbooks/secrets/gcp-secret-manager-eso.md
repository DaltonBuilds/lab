# **GCP Secret Manager & ESO Runbook**

**1. Service Account (SA) Setup**

Check for an existing SA or create a new one to act as the "Secret Reader."

- **List SAs**: `gcloud iam service-accounts list`
- **Create SA**:
    
    **bash**
    
    `gcloud iam service-accounts create [SA_NAME] --display-name="ESO Secret Reader"`
    
- **Grant Access**: Assign the `Secret Manager Secret Accessor` role.
    
    **bash**
    
    `gcloud projects add-iam-policy-binding [PROJECT_ID] \
      --member="serviceAccount:[SA_EMAIL]" \
      --role="roles/secretmanager.secretAccessor"`

**2. Key Management**

Generate the JSON key required for external cluster authentication.

- **Create Key**:
    
    **bash**
    
    `gcloud iam service-accounts keys create ./gcp-creds.json \
      --iam-account=[SA_EMAIL]`
    
- **List Keys**: `gcloud iam service-accounts keys list --iam-account=[SA_EMAIL]`
- **Delete Old Key**: `gcloud iam service-accounts keys delete [KEY_ID] --iam-account=[SA_EMAIL]`

**3. GCP Secret Manager Operations**

Manage the actual secrets stored in the cloud.

- **Create Secret**: `gcloud secrets create [SECRET_ID] --replication-policy="automatic"`
- **Add Version**: `echo -n "my-password" | gcloud secrets versions add [SECRET_ID] --data-file=-`
- **List Secrets**: `gcloud secrets list`
    
**4. k3s / ESO Integration**

Bridge GCP and Kubernetes by storing the JSON key as a native Secret.

- **Create Kubernetes Secret**:
    
    **bash**
    
    `kubectl create secret generic gcp-secret-manager-credentials \
      --from-file=credentials.json=./gcp-creds.json \
      -n external-secrets`
    
- **Verify ClusterSecretStore**: Ensure the operator has a "Valid" connection.
    
    **bash**
    
    `kubectl get clustersecretstore [STORE_NAME]`
    
- **Check Status Details**: `kubectl describe clustersecretstore [STORE_NAME]`

**5. Essential Security Cleanup**

- **Delete local JSON**: `rm ./gcp-creds.json` immediately after creating the K8s secret.
- **Purge Redundant K8s Secrets**: `kubectl delete secret [OLD_NAME] -n external-secrets`.
- **Keep System Secrets**: Do **not** delete `external-secrets-webhook`; it is required for ESO operations.
