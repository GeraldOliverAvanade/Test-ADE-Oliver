#!/usr/bin/env bash
set -euo pipefail

# ADE passes parameters as env vars in many setups.
# We map them to Terraform variables.
export TF_IN_AUTOMATION=1
export TF_INPUT=0

export TF_VAR_envName="${envName}"
export TF_VAR_resource_group_name="${resource_group_name}"
export TF_VAR_location="${location:-}"

terraform -chdir="${ADE_TEMPLATE_PATH:-.}" init -input=false
terraform -chdir="${ADE_TEMPLATE_PATH:-.}" apply -auto-approve -input=false
