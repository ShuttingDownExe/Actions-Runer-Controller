# =============================================================================
# Custom GitHub Actions Runner Image
# Base: Official GitHub Actions Runner
# Additions: Azure CLI, Terraform, common IaC tools
# =============================================================================

FROM ghcr.io/actions/actions-runner:latest

# Switch to root for package installation
USER root

# Install prerequisites and Azure CLI
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    apt-transport-https \
    lsb-release \
    gnupg \
    jq \
    unzip \
    git \
    wget \
    software-properties-common \
    && curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Terraform
ARG TERRAFORM_VERSION=1.12.1
RUN wget -q "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    && unzip "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -d /usr/local/bin/ \
    && rm "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    && chmod +x /usr/local/bin/terraform

# Install kubectl (useful for K8s-related workflows)
RUN curl -fsSL "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# Install Helm
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installations
RUN az version \
    && terraform version \
    && kubectl version --client \
    && helm version

# Switch back to the runner user
USER runner
