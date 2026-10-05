include "root" {
  path = find_in_parent_folders("main.hcl")
}

terraform {
  source = "../../../modules/security"
}

dependency "network" {
  config_path = "../network"

  mock_outputs = {
    vpc_id = "vpc-id"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  vpc_id = dependency.network.outputs.vpc_id
  lambda_source_path = abspath("${get_repo_root()}/lambda")
}
