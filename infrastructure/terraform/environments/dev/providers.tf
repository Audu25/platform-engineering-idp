provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "platform-engineering-idp"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}
