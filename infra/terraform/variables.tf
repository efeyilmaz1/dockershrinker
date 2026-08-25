variable "aws_region" {
  description = "AWS region to deploy into. Use the same region your Jenkins/SonarQube/Nexus EC2 instances already run in, so cross-service traffic stays in-region."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Short name used to prefix/tag all resources."
  type        = string
  default     = "smartdockershrinker"
}

variable "environment" {
  description = "Environment tag (dev/staging/prod)."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the new VPC that will host the EKS cluster."
  type        = string
  default     = "10.60.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets across."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per AZ. Cheaper, fine for a dev/portfolio cluster; set false for production HA."
  type        = bool
  default     = true
}

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.31"
}

variable "eks_public_access_cidrs" {
  description = <<-EOT
    CIDR blocks allowed to reach the EKS API's public endpoint.
    Defaults wide open (0.0.0.0/0) so this works out of the box, but you
    should narrow it to your Jenkins EC2's Elastic IP (/32) and your own
    PC's IP once you know them. Example: ["203.0.113.10/32", "198.51.100.7/32"]
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "EC2 instance types for the EKS managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "additional_eks_access_entries" {
  description = <<-EOT
    Extra IAM principals to grant EKS cluster access via EKS Access Entries
    (the modern replacement for hand-editing the aws-auth ConfigMap).
    Use this to grant your Jenkins EC2 instance role kubectl/helm access, e.g.:

    additional_eks_access_entries = {
      jenkins = {
        principal_arn = "arn:aws:iam::123456789012:role/jenkins-ec2-role"
        policy_associations = {
          admin = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    }
  EOT
  type        = any
  default     = {}
}
