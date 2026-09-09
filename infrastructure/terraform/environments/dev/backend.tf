# Remote state is initialised with -backend-config so the bucket name stays out of
# version control. S3 native locking (use_lockfile) replaces the DynamoDB table
# that older setups required.
terraform {
  backend "s3" {}
}
