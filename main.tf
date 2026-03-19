# --- 1. BACKEND & PROVIDERS ---
terraform {
  backend "s3" {
    bucket         = "terraform-state-storage-rferns-0009" 
    key            = "eks/chatbot/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    # dynamodb_table = "terraform-state-lock" 
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Keeps us on the version EKS and VPC modules expect
    }
  }
}

variable "alb_dns_name" {
  type    = string
  default = ""
}
locals {
  cluster_name    = "secure-eks-testing"
  domain_name     = "rferns-0009.xyz"
  hosted_zone_id  = "Z08038211C59XXRLVKOL2" 
  certificate_arn = "arn:aws:acm:us-east-1:078083578991:certificate/d161c0cb-2f9e-4a9b-b58c-c6c3b6790753"
}

provider "aws" {
  region = "ap-south-1"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "helm" {
  # Note the '=' sign here - this is the v3.0 breaking change fix
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }
  }
}

# --- 2. NETWORK ---
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  
  name = "secure-testing-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["ap-south-1a", "ap-south-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  # --- ADD THESE TWO BLOCKS ---
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

# --- 3. EKS ---
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "secure-eks-testing"
 
  cluster_endpoint_public_access = true

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.public_subnets

  # 1. Allows whoever creates/updates the cluster (like Jenkins) to be an admin
  enable_cluster_creator_admin_permissions = true

  # 2. Permanently hardcodes your personal IAM user as a cluster admin
  access_entries = {
    rahul_admin = {
      kubernetes_groups = []
      principal_arn     = "arn:aws:iam::078083578991:user/Rahul"

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # 3. Your existing node group configuration
  eks_managed_node_groups = {
    testing_nodes = {
      min_size     = 1
      max_size     = 2
      desired_size = 1

      instance_types = ["t3.small"]
      capacity_type  = "SPOT"
      
      # Keep any existing custom tags or configurations you had here
    }
  }

  # 4. Your existing security group rules (like port 5000 for the ALB)
  node_security_group_additional_rules = {
    ingress_flask_5000 = {
      description                   = "Allow ALB to reach Flask on port 5000"
      protocol                      = "tcp"
      from_port                     = 5000
      to_port                       = 5000
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }
}

# --- 4. AWS LOAD BALANCER CONTROLLER ---

# 1. The Base Role (Created by the module)
module "lb_controller_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.44.0" 

  role_name = "aws-load-balancer-controller-role"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# 2. The Inline Patch (Injects the missing v6 permissions into the v5 role)
resource "aws_iam_role_policy" "lb_controller_patch" {
  name = "lb-controller-missing-perms"
  role = module.lb_controller_role.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeRouteTables",
          "elasticloadbalancing:DescribeListenerAttributes",
          "elasticloadbalancing:DescribeCapacityReservation"
        ]
        Resource = "*"
      }
    ]
  })
}

# 3. The Helm Release (Installs the software using the patched role)
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  depends_on = [module.eks]

  set = [
    { name = "clusterName", value = module.eks.cluster_name },
    { name = "serviceAccount.create", value = "true" },
    { name = "serviceAccount.name", value = "aws-load-balancer-controller" },
    { name = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn", value = module.lb_controller_role.iam_role_arn },
    { name = "region", value = "ap-south-1" },
    { name = "vpcId", value = module.vpc.vpc_id }
  ]
}

# --- 5. S3 & CLOUDFRONT ---
resource "aws_s3_bucket" "frontend" {
  bucket = "frontend-assets-${local.domain_name}"
}

resource "aws_cloudfront_origin_access_control" "default" {
  name                              = "s3-oac-0009"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.default.id
    origin_id                = "S3-Frontend"
  }
  enabled             = true
  default_root_object = "index.html"
  aliases             = [local.domain_name]
  web_acl_id          = aws_wafv2_web_acl.main.arn

  default_cache_behavior {
    target_origin_id       = "S3-Frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }
  restrictions {
    geo_restriction { restriction_type = "none" }
  }
  viewer_certificate {
    acm_certificate_arn      = local.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

resource "aws_s3_bucket_policy" "allow_oac" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AllowCloudFront"
      Action   = "s3:GetObject"
      Effect   = "Allow"
      Resource = "${aws_s3_bucket.frontend.arn}/*"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.s3_distribution.arn }
      }
    }]
  })
}

# --- 6. WAF ---
resource "aws_wafv2_web_acl" "main" {
  provider = aws.us_east_1
  name     = "chatbot-waf-0009"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "chatbot-waf"
    sampled_requests_enabled   = true
  }
}

# --- 7. DNS ---
resource "aws_route53_record" "www" {
  zone_id = local.hosted_zone_id
  name    = local.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "api" {
  zone_id         = local.hosted_zone_id
  name            = "api.${local.domain_name}"
  type            = "A"
  allow_overwrite = true
  alias {
    name                   = var.alb_dns_name
    zone_id                = "ZP97RAFLXTNZK"
    evaluate_target_health = true
  }
}