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
    resources = [aws_kms_key.vault_unseal.arn]
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

# Load Balancer Controller IRSA
data "aws_iam_policy_document" "aws_lbc_assume_role" {
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
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
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

resource "aws_iam_role" "aws_lbc" {
  name               = "${var.project}-${var.environment}-aws-lbc-role"
  assume_role_policy = data.aws_iam_policy_document.aws_lbc_assume_role.json

  tags = {
    Name        = "${var.project}-${var.environment}-aws-lbc-role"
    Environment = var.environment
    Project     = var.project
  }
}

data "local_file" "aws_lbc_policy" {
  filename = "${path.module}/policies/aws_lbc_iam_policy_v3.5.0.json"
}

resource "aws_iam_policy" "aws_lbc" {
  name   = "${var.project}-${var.environment}-aws-lbc-policy"
  policy = data.local_file.aws_lbc_policy.content

  tags = {
    Name        = "${var.project}-${var.environment}-aws-lbc-policy"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy_attachment" "aws_lbc" {
  role       = aws_iam_role.aws_lbc.name
  policy_arn = aws_iam_policy.aws_lbc.arn
}

# Loki IRSA
data "aws_iam_policy_document" "loki_assume_role" {
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
      values   = ["system:serviceaccount:observability:loki"]
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

resource "aws_iam_role" "loki" {
  name               = "${var.project}-${var.environment}-loki-role"
  assume_role_policy = data.aws_iam_policy_document.loki_assume_role.json

  tags = {
    Name        = "${var.project}-${var.environment}-loki-role"
    Environment = var.environment
    Project     = var.project
  }
}

data "aws_iam_policy_document" "loki_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      var.loki_s3_bucket_arn,
      "${var.loki_s3_bucket_arn}/*"
    ]
  }
}

resource "aws_iam_policy" "loki_s3" {
  name   = "${var.project}-${var.environment}-loki-s3-policy"
  policy = data.aws_iam_policy_document.loki_s3.json
}

resource "aws_iam_role_policy_attachment" "loki_s3" {
  role       = aws_iam_role.loki.name
  policy_arn = aws_iam_policy.loki_s3.arn
}

resource "aws_kms_grant" "loki" {
  name              = "${var.project}-${var.environment}-loki-kms-grant"
  key_id            = var.loki_kms_key_id
  grantee_principal = aws_iam_role.loki.arn
  operations        = ["Encrypt", "Decrypt", "GenerateDataKey", "DescribeKey"]
}

# AlertManager IRSA
data "aws_iam_policy_document" "alertmanager_assume_role" {
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
      values   = ["system:serviceaccount:observability:kube-prometheus-stack-alertmanager"]
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

resource "aws_iam_role" "alertmanager" {
  name               = "${var.project}-${var.environment}-alertmanager-role"
  assume_role_policy = data.aws_iam_policy_document.alertmanager_assume_role.json

  tags = {
    Name        = "${var.project}-${var.environment}-alertmanager-role"
    Environment = var.environment
    Project     = var.project
  }
}

data "aws_iam_policy_document" "alertmanager_sns" {
  statement {
    effect = "Allow"
    actions = [
      "sns:Publish"
    ]
    resources = [
      var.alertmanager_sns_topic_arn
    ]
  }
}

resource "aws_iam_policy" "alertmanager_sns" {
  name   = "${var.project}-${var.environment}-alertmanager-sns-policy"
  policy = data.aws_iam_policy_document.alertmanager_sns.json

  tags = {
    Name        = "${var.project}-${var.environment}-alertmanager-sns-policy"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy_attachment" "alertmanager_sns" {
  role       = aws_iam_role.alertmanager.name
  policy_arn = aws_iam_policy.alertmanager_sns.arn
}
