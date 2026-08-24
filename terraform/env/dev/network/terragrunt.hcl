include "root" {
  path = find_in_parent_folders("main.hcl")
}

terraform {
  source = "../../../modules/network"
}
