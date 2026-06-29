# EBS CSI Driver IRSA
data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpce"
      values   = [var.sts_vpc_endpoint_id]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.project}-${var.environment}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = {
    Name        = "${var.project}-${var.environment}-ebs-csi-role"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Vault IRSA
data "aws_iam_policy_document" "vault_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:vault:vault"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpce"
      values   = [var.sts_vpc_endpoint_id]
    }
  }
}

resource "aws_iam_role" "vault" {
  name               = "${var.project}-${var.environment}-vault-role"
  assume_role_policy = data.aws_iam_policy_document.vault_assume_role.json

  tags = {
    Name        = "${var.project}-${var.environment}-vault-role"
    Environment = var.environment
    Project     = var.project
  }
}

data "aws_iam_policy_document" "vault_kms_unseal" {
  statement {
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = [var.vault_unseal_key_arn]
  }
}

resource "aws_iam_policy" "vault_kms_unseal" {
  name   = "${var.project}-${var.environment}-vault-kms-unseal-policy"
  policy = data.aws_iam_policy_document.vault_kms_unseal.json
}

resource "aws_iam_role_policy_attachment" "vault_kms_unseal" {
  role       = aws_iam_role.vault.name
  policy_arn = aws_iam_policy.vault_kms_unseal.arn
}
