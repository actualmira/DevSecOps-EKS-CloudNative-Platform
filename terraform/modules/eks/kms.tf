#Vault
resource "aws_kms_key" "vault_unseal" {
  description             = "KMS key for Vault auto-unseal"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = "${var.project}-${var.environment}-vault-unseal-key"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/${var.project}-${var.environment}-vault-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

#ectd
resource "aws_kms_key" "eks_secrets" {
  description             = "KMS key for EKS etcd secrets envelope encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = "${var.project}-${var.environment}-eks-secrets-key"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.project}-${var.environment}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

