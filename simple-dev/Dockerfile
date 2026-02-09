FROM mcr.microsoft.com/deployment-environments/runners/core:latest

ARG TERRAFORM_VERSION=1.6.6

RUN apk add --no-cache curl unzip bash dos2unix \
  && curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip -o /tmp/terraform.zip \
  && unzip /tmp/terraform.zip -d /usr/local/bin \
  && terraform -version

COPY scripts/ /scripts/
RUN find /scripts -type f -name "*.sh" -exec dos2unix {} \; \
 && chmod +x /scripts/*.sh
