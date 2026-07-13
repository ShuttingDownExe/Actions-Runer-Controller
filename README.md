# GitHub Actions Runner Controller on AKS — Cost-Optimized

Deploy self-hosted GitHub Actions runners on AKS using the **Actions Runner Controller (ARC v2)** with a custom runner image that includes **Azure CLI** and **Terraform** pre-installed.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  AKS Cluster (Free tier)                                    │
│                                                             │
│  ┌──────────────────────┐  ┌──────────────────────────────┐ │
│  │  System Node Pool    │  │  Runner Node Pool            │ │
│  │  (Standard_B2s × 1)  │  │  (Standard_B2ms × 0-3)      │ │
│  │                      │  │  ☁ Azure Spot Instances      │ │
│  │  • kube-system       │  │  ↕ Autoscale 0 → 3 nodes    │ │
│  │  • ARC Controller    │  │                              │ │
│  │                      │  │  • Runner Pods (0 → 5)       │ │
│  │                      │  │  • Azure CLI + Terraform     │ │
│  └──────────────────────┘  └──────────────────────────────┘ │
│                                                             │
│  ACR (Basic) ← Custom runner image                          │
└─────────────────────────────────────────────────────────────┘
```

## Cost Breakdown (Estimated Monthly)

| Resource | Spec | Est. Cost |
|---|---|---|
| AKS Control Plane | Free tier | **$0** |
| System Node | B2s × 1 (always on) | **~$30** |
| Runner Nodes | B2ms × 0-3 (Spot, autoscale) | **~$6-12/node** when active |
| ACR | Basic tier | **~$5** |
| **Idle cost** | No runner jobs | **~$35/mo** |

> Spot instances can be **up to 90% cheaper** than on-demand. Runners scale to zero pods *and* zero nodes when idle.

## Prerequisites

- Azure CLI authenticated (`az login`)
- Terraform ≥ 1.5
- Docker (to build the custom runner image)
- A GitHub PAT with `admin:org` scope (for org runners) or `repo` scope (for repo runners)

## Quick Start

### 1. Build & Push the Custom Runner Image

```bash
# Login to your ACR (replace with your ACR name)
az acr login --name youruniqueacrname

# Build the image
docker build -t youruniqueacrname.azurecr.io/actions-runner-custom:latest -f Dockerfile .

# Push to ACR
docker push youruniqueacrname.azurecr.io/actions-runner-custom:latest
```

### 2. Deploy Infrastructure

```bash
# Copy and fill in variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Deploy
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 3. Use in GitHub Workflows

```yaml
name: My Workflow
on: push

jobs:
  deploy:
    runs-on: arc-runner-set   # ← matches runner_scale_set_name
    steps:
      - uses: actions/checkout@v4

      - name: Terraform Plan
        run: |
          terraform init
          terraform plan

      - name: Azure CLI
        run: |
          az account show
          az group list
```

## Project Structure

```
.
├── main.tf                         # AKS cluster, ACR, node pools
├── arc.tf                          # ARC controller + runner Helm releases
├── variables.tf                    # All configurable variables
├── outputs.tf                      # Useful outputs
├── terraform.tfvars.example        # Example variable values
├── Dockerfile                      # Custom runner: actions-runner + az cli + terraform
│
└── charts/
    └── arc-custom-runner/          # Custom Helm chart for runner scale set
        ├── Chart.yaml
        ├── values.yaml
        └── templates/
            ├── _helpers.tpl
            ├── autoscaling-runner-set.yaml   # AutoScalingRunnerSet CR
            ├── github-secret.yaml            # GitHub PAT/App secret
            ├── serviceaccount.yaml
            └── pvc.yaml                      # Optional persistent work vol
```

## Key Configuration

### Scale-to-Zero Behavior

- **Pod level**: `runner_min_count = 0` — no runner pods when no jobs queued
- **Node level**: `runner_node_min_count = 0` — AKS cluster autoscaler removes runner nodes entirely
- **Spin-up time**: ~2-4 minutes (node provision + pod start) for the first job after idle

### Spot Instance Eviction

Spot VMs can be evicted with 30s notice. This is fine for CI/CD because:
- ARC automatically re-queues interrupted jobs
- Jobs are ephemeral by nature
- Cost savings (60-90%) outweigh occasional re-runs

### Using GitHub App Instead of PAT

For production, prefer a GitHub App over a PAT:

```hcl
# In terraform.tfvars, leave github_pat empty and configure the chart values directly
# Or modify the Helm chart values to use GitHub App credentials
```

### Docker-in-Docker

If your workflows need to build Docker images, enable DinD in the Helm values:

```yaml
# charts/arc-custom-runner/values.yaml
dockerInDocker:
  enabled: true
```

## Tearing Down

```bash
terraform destroy
```
