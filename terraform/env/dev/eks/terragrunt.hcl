include "root" {
  path = find_in_parent_folders("main.hcl")
}

terraform {
  source = "../../../modules/eks"
}

dependency "network" {
  config_path = "../network"
  mock_outputs = {
    vpc_id                           = "vpc-id"
    private_subnet_ids               = ["private-subnet-1", "private-subnet-2", "private-subnet-3"]
    isolated_subnet_ids              = ["isolated-subnet-1", "isolated-subnet-2", "isolated-subnet-3"]
    apps_security_group_id           = "apps-sg-id"
    observability_security_group_id  = "observability-sg-id"
    isolated_security_group_id       = "isolated-sg-id"
    sts_vpc_endpoint_id              = "sts-endpoint-id"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "security" {
  config_path = "../security"

  mock_outputs = {
    ssm_session_logging_policy_arn = "arn:aws:iam::mock:policy/ssm-logging"
    loki_s3_bucket_arn             = "arn:aws:s3:::mock-loki-bucket"
    loki_kms_key_id                = "mock-kms-key-id"
    alertmanager_sns_topic_arn     = "arn:aws:sns:eu-west-1:mock:alertmanager-alerts"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  kubernetes_version              = "1.35"
  vpc_id                          = dependency.network.outputs.vpc_id
  private_subnet_ids              = dependency.network.outputs.private_subnet_ids
  isolated_subnet_ids             = dependency.network.outputs.isolated_subnet_ids
  apps_security_group_id          = dependency.network.outputs.apps_security_group_id
  isolated_security_group_id      = dependency.network.outputs.isolated_security_group_id
  observability_security_group_id = dependency.network.outputs.observability_security_group_id
  sts_vpc_endpoint_id             = dependency.network.outputs.sts_vpc_endpoint_id
  ssm_session_logging_policy_arn  = dependency.security.outputs.ssm_session_logging_policy_arn
  loki_s3_bucket_arn              = dependency.security.outputs.loki_s3_bucket_arn
  loki_kms_key_id                 = dependency.security.outputs.loki_kms_key_id
  alertmanager_sns_topic_arn      = dependency.security.outputs.alertmanager_sns_topic_arn
}
