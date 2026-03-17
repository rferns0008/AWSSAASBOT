terraform {
  backend "s3" {
    # Replace this with the bucket name you want to use for state
    bucket         = "terraform-state-storage-rferns-0009" 
    key            = "eks/chatbot/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    # Optional: Enable DynamoDB locking to prevent concurrent runs
    # dynamodb_table = "terraform-state-lock" 
  }
}

# --- 1. VARIABLES & PROVIDERS ---
variable "alb_dns_name" {
  type        = string
  description = "The DNS name of the ALB created by Kubernetes"
  default     = ""
}

provider "aws" {
  region = "ap-south-1"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

locals {
  cluster_name    = "secure-eks-testing"
  domain_name     = "rferns-0009.xyz"
  account_id      = "078083578991"
  hosted_zone_id  = "Z08038211C59XXRLVKOL2" 
  certificate_arn = "arn:aws:acm:us-east-1:078083578991:certificate/d161c0cb-2f9e-4a9b-b58c-c6c3b6790753"
}

# --- 2. NETWORK LAYER ---
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
}

# --- 3. COMPUTE LAYER (EKS) ---
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = "1.34"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  node_security_group_additional_rules = {
    ingress_flask_5000 = {
      description = "Allow Load Balancer to reach Flask"
      protocol    = "tcp"
      from_port   = 5000
      to_port     = 5000
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  eks_managed_node_groups = {
    testing_nodes = {
      instance_types = ["t3.small"]
      min_size       = 1
      max_size       = 2
      desired_size   = 1
      capacity_type  = "SPOT"
    }
  }
}

# --- 4. FRONTEND (S3/CloudFront) ---
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
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = local.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# --- 5. WAF ---
resource "aws_wafv2_web_acl" "main" {
  provider = aws.us_east_1
  name     = "chatbot-waf-0009"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "chatbot-waf-main"
    sampled_requests_enabled   = true
  }
}

# --- 6. DNS ---
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
  count           = var.alb_dns_name != "" ? 1 : 0
  zone_id         = local.hosted_zone_id
  name            = "api.${local.domain_name}"
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = var.alb_dns_name
    zone_id                = "ZP97RAE9L3BAZ" 
    evaluate_target_health = true
  }
}

# --- 7. S3 BUCKET POLICY ---
resource "aws_s3_bucket_policy" "allow_oac" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowCloudFrontServicePrincipalReadOnly"
        Action   = "s3:GetObject"
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.s3_distribution.arn
          }
        }
      }
    ]
  })
}