# Step 3 - Private artifacts bucket holding the two JARs and the ca1-aws helper folder.

locals {
  repo_root   = abspath("${path.module}/..") # project folder (parent of terraform/), works on any machine
  ca1_aws_dir = "${local.repo_root}/ca1-aws"

  # Built JARs, uploaded under the short names the user-data scripts expect
  jars = {
    "productservice.jar" = "${local.repo_root}/productservice/target/productservice-0.0.1-SNAPSHOT.jar"
    "couponservice.jar"  = "${local.repo_root}/couponservice/target/couponservice-0.0.1-SNAPSHOT.jar"
  }

  # Everything in ca1-aws/ except macOS and Python junk -> ca1-aws/aws/..., ca1-aws/k6/..., etc.
  ca1_aws_files = [
    for f in fileset(local.ca1_aws_dir, "**") : f
    if !strcontains(f, ".DS_Store") && !strcontains(f, "__pycache__")
  ]
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = var.bucket_name
  force_destroy = var.bucket_force_destroy
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "jar" {
  for_each = local.jars

  bucket       = aws_s3_bucket.artifacts.id
  key          = each.key
  source       = each.value
  source_hash  = filemd5(each.value) # re-upload when you rebuild the JAR
  content_type = "application/java-archive"
}

resource "aws_s3_object" "ca1_aws" {
  for_each = toset(local.ca1_aws_files)

  bucket      = aws_s3_bucket.artifacts.id
  key         = "ca1-aws/${each.value}"
  source      = "${local.ca1_aws_dir}/${each.value}"
  source_hash = filemd5("${local.ca1_aws_dir}/${each.value}")
}
