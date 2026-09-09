provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "platform-engineering-idp"
      Environment = "shared"
      Component   = "bootstrap"
      ManagedBy   = "terraform"
      Owner       = var.owner
      CostCentre  = var.cost_centre
    }
  }
}
