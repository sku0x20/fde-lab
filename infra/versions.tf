terraform {
  required_version = "~> 1.13"

  required_providers {
    runpod = {
      # not on the OpenTofu registry: a bare "runpod/runpod" doesn't resolve
      source  = "registry.terraform.io/runpod/runpod"
      version = "~> 2.0" # 1.x uses RunPod's REST v1 API, switched off 2026-11-16
    }
  }

  # local state for now (gitignored)
}
