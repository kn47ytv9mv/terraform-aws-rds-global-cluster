locals {
  global_cluster_identifier = coalesce(var.global_cluster_identifier, "global-${random_uuid.resource.id}")
}

resource "random_uuid" "resource" {}

resource "aws_rds_global_cluster" "resource" {
  global_cluster_identifier = local.global_cluster_identifier

  engine                   = var.engine
  engine_version           = var.engine_version
  engine_lifecycle_support = var.engine_lifecycle_support

  source_db_cluster_identifier = var.source_db_cluster_identifier

  database_name     = var.database_name
  storage_encrypted = var.storage_encrypted

  deletion_protection = var.deletion_protection
  force_destroy       = var.force_destroy

  tags = var.tags
}

output "id" {
  description = "The ID of the global cluster, which is its identifier. Pass this to each member cluster's global_cluster_identifier."
  value       = aws_rds_global_cluster.resource.id
}

output "arn" {
  description = "The ARN of the global cluster."
  value       = aws_rds_global_cluster.resource.arn
}

output "global_cluster_identifier" {
  description = "The identifier of the global cluster."
  value       = aws_rds_global_cluster.resource.global_cluster_identifier
}

output "endpoint" {
  description = "Writer endpoint of the global database. It follows the writer instance of whichever regional cluster is currently primary, including across a failover to another region."
  value       = aws_rds_global_cluster.resource.endpoint
}

output "engine" {
  description = "Engine of the global database, resolved by AWS when it was inherited from a source cluster rather than configured. Pass it to each member cluster so every member agrees with the global cluster."
  value       = aws_rds_global_cluster.resource.engine
}

output "engine_version" {
  description = "Engine version configured on the global database, or the version inherited from a source cluster."
  value       = aws_rds_global_cluster.resource.engine_version
}

output "engine_version_actual" {
  description = "Engine version the global database is actually running, which is more specific than engine_version whenever only a partial version was configured."
  value       = aws_rds_global_cluster.resource.engine_version_actual
}

output "global_cluster_resource_id" {
  description = "AWS's own immutable identifier for the global cluster, which appears in the CloudTrail entries recording use of its KMS key."
  value       = aws_rds_global_cluster.resource.global_cluster_resource_id
}

output "global_cluster_members" {
  description = "Every regional cluster currently joined to the global database, each with its ARN and whether it is the primary."
  value       = aws_rds_global_cluster.resource.global_cluster_members
}
