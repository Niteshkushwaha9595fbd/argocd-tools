# HashiCorp Vault OIDC Authentication with GitHub Integration

## 📋 Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [GitHub Configuration](#github-configuration)
4. [Vault Setup](#vault-setup)
5. [ArgoCD Integration](#argocd-integration)
6. [Security & Compliance](#security--compliance)
7. [Troubleshooting](#troubleshooting)

---

## Overview

### Architecture Flow
```
GitHub (OIDC Provider)
    ↓
Vault (Identity Management Hub)
    ↓
ArgoCD (Application Deployment)
```

### Key Features
- ✅ **Centralized Identity Management** - Single source of truth for users/teams
- ✅ **Role-Based Access Control (RBAC)** - Granular permissions for Developers & Admins
- ✅ **Security Compliance** - OAuth 2.0/OIDC standards, encrypted tokens
- ✅ **Consistency Across Tools** - Same identity for Vault, ArgoCD, and other applications
- ✅ **Audit Trail** - Complete logging of access and changes

---

## Prerequisites

### Required Components
- ✅ HashiCorp Vault (v1.12+)
- ✅ Kubernetes Cluster (Helm/ArgoCD deployed)
- ✅ GitHub Organization Account
- ✅ kubectl configured
- ✅ Vault CLI installed

### Install Vault CLI (if not already installed)
```bash
# macOS
brew install vault

# Linux
wget https://releases.hashicorp.com/vault/1.15.0/vault_1.15.0_linux_amd64.zip
unzip vault_1.15.0_linux_amd64.zip
sudo mv vault /usr/local/bin/
```

---

## GitHub Configuration

### Step 1: Create GitHub OAuth Application

**Location:** GitHub Settings → Developer Settings → OAuth Apps

#### 1.1 Create New OAuth App
```
Application name: Vault OIDC
Homepage URL: https://vault.yourdomain.com
Authorization callback URL: https://vault.yourdomain.com/ui/vault/auth/oidc/oidc/callback
```

#### 1.2 Generate Client Credentials
After creating the app, you'll receive:
- **Client ID**: `xxxxxxxxxxxxxxxxxxxxxxxx`
- **Client Secret**: `xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

**⚠️ IMPORTANT:** Store these securely (use Kubernetes Secrets or external secret manager)

---

## Vault Setup

### Step 2: Vault Server Configuration

#### 2.1 Unseal Vault & Login
```bash
# Unseal Vault (if using raft storage)
vault operator unseal

# Login with root token
vault login -method=token
```

#### 2.2 Enable OIDC Auth Method
```bash
# Enable OIDC auth at path 'oidc'
vault auth enable oidc

# List enabled auth methods
vault auth list
```

### Step 3: Configure OIDC with GitHub

#### 3.1 Create OIDC Configuration

```bash
vault write auth/oidc/config \
  oidc_discovery_url="https://token.actions.githubusercontent.com" \
  oidc_client_id="YOUR_GITHUB_CLIENT_ID" \
  oidc_client_secret="YOUR_GITHUB_CLIENT_SECRET" \
  default_role="github-user"
```

#### 3.2 Configure OIDC Role for GitHub Users

**For Developers:**
```bash
vault write auth/oidc/role/github-developer \
  bound_audiences="STSAssumeRoleWithWebIdentity" \
  user_claim="sub" \
  groups_claim="org:team" \
  allowed_redirect_uris="https://vault.yourdomain.com/ui/vault/auth/oidc/oidc/callback,http://localhost:8250/oidc/callback" \
  token_ttl=24h \
  token_max_ttl=30d \
  policies="github-developer"
```

**For Admins:**
```bash
vault write auth/oidc/role/github-admin \
  bound_audiences="STSAssumeRoleWithWebIdentity" \
  user_claim="sub" \
  groups_claim="org:team" \
  allowed_redirect_uris="https://vault.yourdomain.com/ui/vault/auth/oidc/oidc/callback,http://localhost:8250/oidc/callback" \
  token_ttl=24h \
  token_max_ttl=30d \
  policies="github-admin"
```

### Step 4: Create Vault Policies

#### 4.1 Developer Policy
```bash
cat > /tmp/github-developer-policy.hcl << 'EOF'
# GitHub Developer Policy
path "argocd/data/dev/*" {
  capabilities = ["read", "list"]
}

path "argocd/metadata/dev/*" {
  capabilities = ["read", "list"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOF

vault policy write github-developer /tmp/github-developer-policy.hcl
```

#### 4.2 Admin Policy
```bash
cat > /tmp/github-admin-policy.hcl << 'EOF'
# GitHub Admin Policy
path "argocd/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/argocd/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "auth/token/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF

vault policy write github-admin /tmp/github-admin-policy.hcl
```

### Step 5: Map GitHub Teams to Vault Roles

```bash
# Map GitHub admin team to Vault admin role
vault write auth/oidc/role/github-admin \
  user_claim="sub" \
  groups_claim="org:team" \
  bound_claims='{"org:team": ["your-org/admin-team"]}'

# Map GitHub developer team to Vault developer role
vault write auth/oidc/role/github-developer \
  user_claim="sub" \
  groups_claim="org:team" \
  bound_claims='{"org:team": ["your-org/dev-team"]}'
```

---

## ArgoCD Integration

### Step 6: Configure ArgoCD with Vault OIDC

#### 6.1 Create ArgoCD Config Secret
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-oidc-vault
  namespace: argocd
type: Opaque
stringData:
  vault-addr: "https://vault.yourdomain.com:8200"
  vault-role: "argocd-auth"
  github-org: "your-github-org"
```

Deploy the secret:
```bash
kubectl apply -f argocd-oidc-vault-secret.yaml
```

#### 6.2 Update ArgoCD ConfigMap for OIDC
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
  namespace: argocd
data:
  # OIDC Configuration
  oidc.config: |
    name: Vault OIDC (GitHub)
    issuer: https://token.actions.githubusercontent.com
    clientID: <YOUR_GITHUB_CLIENT_ID>
    clientSecret: $oidc.github.clientSecret
    requestedScopes:
      - openid
      - profile
      - email
    requestedIDTokenClaims:
      - groups_pretty
      - teams_pretty
    logoutURL: https://vault.yourdomain.com/ui/vault/auth/oidc/oidc/logout
```

#### 6.3 Update ArgoCD RBAC ConfigMap
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    # GitHub Organization Mappings
    # Format: g, <user/group>, <role>
    
    # Admin Role - Full access
    g, your-org:admin-team, role:admin
    p, role:admin, *, *, */*, allow
    p, role:admin, logs, *, *, allow
    
    # Developer Role - Application deployments
    g, your-org:dev-team, role:developer
    p, role:developer, applications, get, */*, allow
    p, role:developer, applications, create, */*, allow
    p, role:developer, applications, update, */*, allow
    p, role:developer, applications, delete, */*, allow
    p, role:developer, repositories, get, *, allow
    p, role:developer, repositories, list, *, allow
    
    # ReadOnly Role - View only
    g, your-org:viewer-team, role:readonly
    p, role:readonly, applications, get, */*, allow
    p, role:readonly, repositories, get, *, allow
    p, role:readonly, certificates, get, *, allow
    
  policy.matchMode: 'glob'
  
  scopes: '[groups, email, profile]'
```

Deploy the ConfigMap:
```bash
kubectl apply -f argocd-rbac-cm.yaml
```

#### 6.4 Restart ArgoCD Server
```bash
kubectl rollout restart deployment/argocd-server -n argocd
```

---

## Security & Compliance

### Step 7: Implement Security Controls

#### 7.1 Token Rotation & Expiry
```bash
# Set token TTL to 24 hours (auto-renewal)
vault write auth/oidc/role/github-developer token_ttl=24h token_max_ttl=720h

vault write auth/oidc/role/github-admin token_ttl=24h token_max_ttl=720h
```

#### 7.2 Enable Audit Logging
```bash
# Enable audit logging
vault audit enable file file_path=/vault/logs/audit.log

# View audit logs
vault audit list
```

#### 7.3 Implement MFA (Multi-Factor Authentication)
```bash
# Enable TOTP MFA in Vault
vault write sys/mfa/totp/enforce \
  force=false \
  issuer="Vault OIDC"
```

#### 7.4 Network Policies
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: vault-argocd-network-policy
  namespace: argocd
spec:
  podSelector:
    matchLabels:
      app: argocd-server
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: vault
      ports:
        - protocol: TCP
          port: 8200
```

#### 7.5 TLS Configuration
```bash
# Ensure Vault uses TLS
vault write auth/oidc/config \
  tls_client_ca_cert="@/path/to/ca.pem" \
  tls_client_cert="@/path/to/client.pem" \
  tls_client_key="@/path/to/client-key.pem"
```

### Step 8: Compliance & Monitoring

#### 8.1 Enable Metrics for Compliance Tracking
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-telemetry
  namespace: vault
data:
  telemetry.hcl: |
    telemetry {
      prometheus_retention_time = "30s"
      disable_hostname = false
    }
```

#### 8.2 Set Up Audit Compliance Reports
```bash
# Query audit logs for compliance
vault audit list -detailed

# Export audit logs
vault audit list | grep file
```

---

## Complete Integration YAML

### deploy-vault-oidc-github.yaml
```yaml
---
# Namespace
apiVersion: v1
kind: Namespace
metadata:
  name: vault
---
# Vault ConfigMap - OIDC Configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-oidc-config
  namespace: vault
data:
  vault-config.hcl: |
    ui = true
    
    listener "tcp" {
      address       = "0.0.0.0:8200"
      tls_cert_file = "/vault/config/tls.crt"
      tls_key_file  = "/vault/config/tls.key"
    }
    
    storage "raft" {
      path = "/vault/data"
    }
    
    telemetry {
      prometheus_retention_time = "30s"
    }
---
# ArgoCD OIDC Secret
apiVersion: v1
kind: Secret
metadata:
  name: argocd-oidc-config
  namespace: argocd
type: Opaque
stringData:
  oidc.clientSecret: "YOUR_GITHUB_CLIENT_SECRET"
---
# ArgoCD RBAC ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    g, your-org:admin-team, role:admin
    g, your-org:dev-team, role:developer
    g, your-org:viewer-team, role:readonly
    
    p, role:admin, *, *, */*, allow
    p, role:admin, logs, *, *, allow
    
    p, role:developer, applications, get, */*, allow
    p, role:developer, applications, create, */*, allow
    p, role:developer, applications, update, */*, allow
    p, role:developer, repositories, get, *, allow
    
    p, role:readonly, applications, get, */*, allow
    
  policy.matchMode: 'glob'
  scopes: '[groups, email, profile]'
---
# Network Policy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: vault-argocd-security
  namespace: argocd
spec:
  podSelector:
    matchLabels:
      app: argocd-server
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: vault
      ports:
        - protocol: TCP
          port: 8200
```

---

## Troubleshooting

### Common Issues & Solutions

#### Issue 1: "Invalid OIDC Token"
```bash
# Check OIDC configuration
vault read auth/oidc/config

# Verify callback URL matches GitHub settings
vault read auth/oidc/role/github-developer
```

#### Issue 2: "Permission Denied" in ArgoCD
```bash
# Check ArgoCD RBAC policies
kubectl get configmap argocd-rbac-cm -n argocd -o yaml

# Verify user groups in token
vault read auth/oidc/role/github-developer
```

#### Issue 3: Token Expiry
```bash
# Check token TTL settings
vault read auth/oidc/role/github-developer

# Update TTL if needed
vault write auth/oidc/role/github-developer token_ttl=48h
```

#### Issue 4: GitHub Org Not Recognized
```bash
# Verify GitHub OAuth app configuration
# Settings → Developer Settings → OAuth Apps → Edit

# Check bound claims
vault read auth/oidc/role/github-developer | grep bound_claims
```

### Debugging Commands
```bash
# Enable debug logging
vault audit enable file file_path=/vault/logs/debug.log

# Check audit logs
tail -f /vault/logs/audit.log

# Test OIDC login
vault login -method=oidc role=github-developer

# Verify token claims
vault token lookup
```

---

## Security Best Practices

✅ **Do's:**
- Use TLS/HTTPS for all Vault communications
- Implement MFA for sensitive operations
- Regularly rotate client secrets
- Monitor audit logs for suspicious activity
- Use network policies to restrict access
- Enable encryption at rest for Vault storage
- Implement least privilege access (RBAC)
- Use short-lived tokens (24h TTL)

❌ **Don'ts:**
- Don't store GitHub client secrets in Git
- Don't use unencrypted HTTP for Vault
- Don't grant admin role to all developers
- Don't ignore audit logs
- Don't share client credentials
- Don't use default/weak passwords
- Don't disable TLS verification
- Don't grant excessive permissions

---

## References

- [HashiCorp Vault OIDC Documentation](https://www.vaultproject.io/docs/auth/jwt/oidc-providers/github)
- [ArgoCD SSO Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/)
- [GitHub OAuth Documentation](https://docs.github.com/en/developers/apps/building-oauth-apps)
- [Vault Security Documentation](https://www.vaultproject.io/docs/internals/security)

---

## Support & Issues

For issues or questions:
1. Check Vault audit logs: `/vault/logs/audit.log`
2. Check ArgoCD logs: `kubectl logs -f deployment/argocd-server -n argocd`
3. Verify network connectivity between services
4. Confirm GitHub OAuth app settings match Vault configuration

**Last Updated:** February 2026
