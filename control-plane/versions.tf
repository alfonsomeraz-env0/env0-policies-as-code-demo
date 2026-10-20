terraform {
  required_version = ">= 1.6"

  required_providers {
    env0 = {
      source  = "env0/env0"
      version = ">= 1.31.0"
    }
  }
}

# Auth comes from the environment:
#   ENV0_API_KEY, ENV0_API_SECRET, ENV0_ORGANIZATION_ID
provider "env0" {}
