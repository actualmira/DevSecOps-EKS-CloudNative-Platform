data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.project}-${var.environment}-cluster/cluster"
  retention_in_days = 30

  tags = {
    Name        = "${var.project}-${var.environment}-eks-cluster-logs"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role" "eks_cluster" {
  name = "${var.project}-${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project}-${var.environment}-eks-cluster-role"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

data "aws_iam_policy_document" "eks_secrets_kms" {
  statement {
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:CreateGrant"
    ]
    resources = [var.eks_secrets_key_arn]
  }
}

resource "aws_iam_policy" "eks_secrets_kms" {
  name   = "${var.project}-${var.environment}-eks-secrets-kms-policy"
  policy = data.aws_iam_policy_document.eks_secrets_kms.json
}

resource "aws_iam_role_policy_attachment" "eks_secrets_kms" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = aws_iam_policy.eks_secrets_kms.arn
}

resource "aws_eks_cluster" "devsecops" {
  name     = "${var.project}-${var.environment}-cluster"
  version  = var.kubernetes_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = concat(
      var.private_subnet_ids,
      var.isolated_subnet_ids
    )

    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  encryption_config {
    provider {
      key_arn = var.eks_secrets_key_arn
    }
    resources = ["secrets"]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_secrets_kms,
    aws_cloudwatch_log_group.eks_cluster
  ]

  tags = {
    Name        = "${var.project}-${var.environment}-cluster"
    Environment = var.environment
    Project     = var.project
  }
}

data "tls_certificate" "eks" {
  url = aws_eks_cluster.devsecops.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.devsecops.identity[0].oidc[0].issuer

  tags = {
    Name        = "${var.project}-${var.environment}-oidc-provider"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.devsecops.name
  addon_name   = "vpc-cni"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name        = "${var.project}-${var.environment}-vpc-cni-addon"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.devsecops.name
  addon_name   = "kube-proxy"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name        = "${var.project}-${var.environment}-kube-proxy-addon"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.devsecops.name
  addon_name   = "coredns"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.apps,
    aws_eks_node_group.isolated
  ]

  tags = {
    Name        = "${var.project}-${var.environment}-coredns-addon"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "node_shared" {
  name        = "${var.project}-${var.environment}-node-shared-sg"
  description = "Shared security group for all EKS worker nodes"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.project}-${var.environment}-node-shared-sg"
    Environment = var.environment
    Project     = var.project
    "kubernetes.io/cluster/${var.project}-${var.environment}-cluster" = "owned"
  }
}

resource "aws_vpc_security_group_ingress_rule" "nodes_from_nodes" {
  security_group_id            = aws_security_group.node_shared.id
  referenced_security_group_id = aws_security_group.node_shared.id
  ip_protocol                  = "-1"

  tags = {
    Name = "${var.project}-${var.environment}-nodes-from-nodes"
  }
}

resource "aws_vpc_security_group_egress_rule" "nodes_to_nodes" {
  security_group_id            = aws_security_group.node_shared.id
  referenced_security_group_id = aws_security_group.node_shared.id
  ip_protocol                  = "-1"

  tags = {
    Name = "${var.project}-${var.environment}-nodes-to-nodes"
  }
}

resource "aws_iam_role" "apps_node" {
  name = "${var.project}-${var.environment}-apps-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.project}-${var.environment}-apps-node-role"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy_attachment" "apps_node_eks_worker" {
  role       = aws_iam_role.apps_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "apps_node_ecr" {
  role       = aws_iam_role.apps_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "apps_node_cni" {
  role       = aws_iam_role.apps_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "apps_node_ssm" {
  role       = aws_iam_role.apps_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "apps_node_ssm_session_logging" {
  role       = aws_iam_role.apps_node.name
  policy_arn = var.ssm_session_logging_policy_arn
}

resource "aws_iam_role" "isolated_node" {
  name = "${var.project}-${var.environment}-isolated-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.project}-${var.environment}-isolated-node-role"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy_attachment" "isolated_node_eks_worker" {
  role       = aws_iam_role.isolated_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "isolated_node_ecr" {
  role       = aws_iam_role.isolated_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "isolated_node_cni" {
  role       = aws_iam_role.isolated_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "isolated_node_ssm" {
  role       = aws_iam_role.isolated_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "isolated_node_ssm_session_logging" {
  role       = aws_iam_role.isolated_node.name
  policy_arn = var.ssm_session_logging_policy_arn
} 

resource "aws_launch_template" "apps" {
  name = "${var.project}-${var.environment}-apps-lt"

  vpc_security_group_ids = [
    aws_security_group.node_shared.id,
    var.apps_security_group_id
  ]

  metadata_options {
    http_tokens                = "required"
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
  }

  
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project}-${var.environment}-apps-node"
      Environment = var.environment
      Project     = var.project
      "Patch Group" = aws_ssm_patch_group.eks_nodes.patch_group
    }
  }

  tags = {
    Name        = "${var.project}-${var.environment}-apps-lt"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_launch_template" "isolated" {
  name = "${var.project}-${var.environment}-isolated-lt"

  vpc_security_group_ids = [
    aws_security_group.node_shared.id,
    var.isolated_security_group_id
  ]

  metadata_options {
    http_tokens                = "required"
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
  }


  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project}-${var.environment}-isolated-node"
      Environment = var.environment
      Project     = var.project
      "Patch Group" = aws_ssm_patch_group.eks_nodes.patch_group
    }
  }

  tags = {
    Name        = "${var.project}-${var.environment}-isolated-lt"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_eks_node_group" "apps" {
  cluster_name    = aws_eks_cluster.devsecops.name
  node_group_name = "${var.project}-${var.environment}-apps"
  node_role_arn   = aws_iam_role.apps_node.arn
  subnet_ids      = [var.private_subnet_ids[0]]
  instance_types  = ["t3.large"]
  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "ON_DEMAND"

  launch_template {
    id      = aws_launch_template.apps.id
    version = aws_launch_template.apps.latest_version
  }

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 2
  }

  labels = {
    role        = "apps"
    environment = var.environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.apps_node_eks_worker,
    aws_iam_role_policy_attachment.apps_node_ecr,
    aws_iam_role_policy_attachment.apps_node_cni,
    aws_iam_role_policy_attachment.apps_node_ssm
  ]

  tags = {
    Name        = "${var.project}-${var.environment}-apps-node"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_eks_node_group" "isolated" {
  cluster_name    = aws_eks_cluster.devsecops.name
  node_group_name = "${var.project}-${var.environment}-isolated"
  node_role_arn   = aws_iam_role.isolated_node.arn
  subnet_ids      = [var.isolated_subnet_ids[0]]
  instance_types  = ["t3.medium"]
  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "ON_DEMAND"

  launch_template {
    id      = aws_launch_template.isolated.id
    version = aws_launch_template.isolated.latest_version
  }

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  labels = {
    role        = "isolated"
    environment = var.environment
  }

  taint {
    key    = "workload"
    value  = "isolated"
    effect = "NO_SCHEDULE"
  }

  depends_on = [
    aws_iam_role_policy_attachment.isolated_node_eks_worker,
    aws_iam_role_policy_attachment.isolated_node_ecr,
    aws_iam_role_policy_attachment.isolated_node_cni,
    aws_iam_role_policy_attachment.isolated_node_ssm
  ]

  tags = {
    Name        = "${var.project}-${var.environment}-isolated-node"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_vpc_security_group_ingress_rule" "cluster_sg_from_nodes" {
  security_group_id            = aws_eks_cluster.devsecops.vpc_config[0].cluster_security_group_id
  referenced_security_group_id = aws_security_group.node_shared.id
  ip_protocol                  = "-1"

  tags = {
    Name = "${var.project}-${var.environment}-cluster-sg-from-nodes"
  }
}

resource "aws_vpc_security_group_egress_rule" "nodes_to_cluster_sg" {
  security_group_id            = aws_security_group.node_shared.id
  referenced_security_group_id = aws_eks_cluster.devsecops.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "-1"

  tags = {
    Name = "${var.project}-${var.environment}-nodes-to-cluster-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "cluster_sg_to_nodes" {
  security_group_id            = aws_eks_cluster.devsecops.vpc_config[0].cluster_security_group_id
  referenced_security_group_id = aws_security_group.node_shared.id
  ip_protocol                  = "-1"

  tags = {
    Name = "${var.project}-${var.environment}-cluster-sg-to-nodes"
  }
}

resource "aws_vpc_security_group_ingress_rule" "nodes_from_cluster_sg" {
  security_group_id            = aws_security_group.node_shared.id
  referenced_security_group_id = aws_eks_cluster.devsecops.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "-1"

  tags = {
    Name = "${var.project}-${var.environment}-nodes-from-cluster-sg"
  }
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.devsecops.name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = aws_iam_role.ebs_csi.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi_policy
  ]

  tags = {
    Name        = "${var.project}-${var.environment}-ebs-csi-addon"
    Environment = var.environment
    Project     = var.project
  }
}
