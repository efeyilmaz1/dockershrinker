module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project_name}-eks"
  cluster_version = var.eks_cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.eks_public_access_cidrs
  cluster_endpoint_private_access      = true

  # Enables IAM Roles for Service Accounts (IRSA) for future add-ons
  # (ingress-nginx, external-dns, cluster-autoscaler, ...).
  enable_irsa = true

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      subnet_ids     = module.vpc.private_subnets

      desired_size = var.node_desired_size
      min_size     = var.node_min_size
      max_size     = var.node_max_size

      labels = {
        role = "app"
      }
    }
  }

  # Grants IAM principals (e.g. your Jenkins EC2 role) kubectl/helm access
  # via EKS Access Entries instead of hand-editing the aws-auth ConfigMap.
  # See variables.tf for the shape of this map.
  access_entries = var.additional_eks_access_entries

  # The identity applying Terraform is granted cluster-admin automatically
  # by the module (enable_cluster_creator_admin_permissions default).
  enable_cluster_creator_admin_permissions = true
}
