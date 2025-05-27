provider "aws" {
  region = var.aws_region
}



resource "aws_s3_bucket" "frontend" {
  bucket        = "fsl-frontend-john-duran-1234-${var.env}"
  force_destroy = true
  tags = {
    Name = "fsl-frontend-john-duran-1234-${var.env}"
  }
}

locals {
    build_dir=var.build_path
    files = fileset(local.build_dir,"**/*")
}

resource "aws_s3_object" "object" {
    for_each = { for file in local.files: file => file}

  bucket = aws_s3_bucket.frontend.id

  key    = each.key

  source = "${local.build_dir}/${each.key}"
  etag = filemd5("${local.build_dir}/${each.key}")
  content_type=lookup({
    html="text/html"
    js="application/javascript"
    json="application/json"
    txt="text/plain"
    map="application/json"
  },regex("[^.]+$",each.key),"default")

}

resource "aws_s3_bucket_public_access_block" "frontend_bucket" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

locals {
  s3_origin_id = "FLSAppS3Origin"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.default.id
    origin_id                = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = false
  comment             = "CDN FSL ${var.env}"
  default_root_object = "index.html"

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.frontend_logs.bucket_regional_domain_name
  }


  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"

    }
  }

  tags = {
    Environment = var.env
  }

  depends_on = [
    aws_s3_bucket_ownership_controls.cloudfront_logs,
    aws_s3_bucket_acl.cloudfront_logs_acl,
    aws_s3_bucket_public_access_block.frontend_bucket
  ]

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_cloudfront_origin_access_control" "default" {
  name                              = "FrontendOAC-${var.env}"
  description                       = "FrontendOAC-${var.env}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket" "frontend_logs" {
  bucket        = "fsl-frontend-john-duran-1234-${var.env}-logs"
  force_destroy = true
  tags = {
    Name = "fsl-frontend-john-duran-1234-${var.env}-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend_bucket_logs" {
  bucket = aws_s3_bucket.frontend_logs.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_ownership_controls" "cloudfront_logs" {
  bucket = aws_s3_bucket.frontend_logs.id
  rule {
    object_ownership = "ObjectWriter"
  }
}


resource "aws_s3_bucket_acl" "cloudfront_logs_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.cloudfront_logs]

  bucket = aws_s3_bucket.frontend_logs.id
  acl    = "log-delivery-write"
}


resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode(
    {
      Version = "2012-10-17",
      Statement = {
        Sid    = "AllowCloudFrontServicePrincipalReadOnly",
        Effect = "Allow",
        Principal = {
          Service = "cloudfront.amazonaws.com"
        },
        Action   = "s3:GetObject",
        Resource = "${aws_s3_bucket.frontend.arn}/*",
        Condition = {
          StringEquals : {
            "AWS:SourceArn" : aws_cloudfront_distribution.s3_distribution.arn
          }
        }
      }
    }
  )
}

