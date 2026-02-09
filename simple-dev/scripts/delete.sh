#!/usr/bin/env bash
set -euo pipefail

export TF_IN_AUTOMATION=1
export TF_INPUT=0

export TF_VAR_envName="${envName}"
export TF_VAR_resource_group_name="${resource_group_name}"
export TF_VAR_location="${location:-}"

terraform -chdir="${ADE_TEMPLATE_PATH:-.}" init -input=false
terraform -chdir="${ADE_TEMPLATE_PATH:-.}" destroy -auto-approve -input=false
