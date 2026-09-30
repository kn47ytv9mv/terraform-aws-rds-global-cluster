mock_provider "aws" {}

run "invalid_global_cluster_identifier_is_rejected" {
  command = plan

  variables {
    global_cluster_identifier = "0Bad_Global"
    engine                    = "aurora-postgresql"
  }

  expect_failures = [var.global_cluster_identifier]
}

run "engine_or_source_cluster_must_be_set" {
  command = plan

  variables {
    global_cluster_identifier = "app-global"
  }

  expect_failures = [var.engine]
}

run "source_cluster_conflicts_with_engine" {
  command = plan

  variables {
    global_cluster_identifier    = "app-global"
    engine                       = "aurora-postgresql"
    source_db_cluster_identifier = "arn:aws:rds:us-east-1:111122223333:cluster:app-primary"
    force_destroy                = true
  }

  expect_failures = [var.engine]
}

run "source_cluster_requires_force_destroy" {
  command = plan

  variables {
    global_cluster_identifier    = "app-global"
    source_db_cluster_identifier = "arn:aws:rds:us-east-1:111122223333:cluster:app-primary"
  }

  expect_failures = [var.force_destroy]
}

run "global_cluster_identifier_defaults_to_prefixed_random_uuid" {
  command = apply

  variables {
    engine = "aurora-postgresql"
  }

  assert {
    condition     = aws_rds_global_cluster.resource.global_cluster_identifier == "global-${random_uuid.resource.id}"
    error_message = "Leaving global_cluster_identifier unset should fall back to a letter-prefixed random_uuid, since AWS rejects an identifier that does not begin with a letter."
  }
}

run "secure_defaults_are_applied" {
  command = plan

  variables {
    global_cluster_identifier = "app-global"
    engine                    = "aurora-postgresql"
  }

  assert {
    condition     = aws_rds_global_cluster.resource.storage_encrypted == true
    error_message = "Global database storage encryption should be enabled by default."
  }

  assert {
    condition     = aws_rds_global_cluster.resource.deletion_protection == false
    error_message = "Deletion protection should be off by default, so a destroy does not require a separate apply to turn it off first."
  }
}

run "engine_and_version_drive_an_empty_global_cluster" {
  command = plan

  variables {
    global_cluster_identifier = "app-global"
    engine                    = "aurora-postgresql"
    engine_version            = "16.4"
    database_name             = "app"
  }

  assert {
    condition     = aws_rds_global_cluster.resource.engine == "aurora-postgresql"
    error_message = "The configured engine should reach the global cluster unchanged."
  }

  assert {
    condition     = aws_rds_global_cluster.resource.engine_version == "16.4"
    error_message = "The configured engine version should reach the global cluster unchanged."
  }
}

run "source_cluster_adopts_an_existing_primary" {
  command = plan

  variables {
    global_cluster_identifier    = "app-global"
    source_db_cluster_identifier = "arn:aws:rds:us-east-1:111122223333:cluster:app-primary"
    force_destroy                = true
  }

  assert {
    condition     = aws_rds_global_cluster.resource.source_db_cluster_identifier == "arn:aws:rds:us-east-1:111122223333:cluster:app-primary"
    error_message = "The source cluster ARN should reach the global cluster unchanged."
  }

  assert {
    condition     = aws_rds_global_cluster.resource.force_destroy == true
    error_message = "Adopting a source cluster should carry force_destroy, without which the global cluster can never be destroyed."
  }
}

run "readme_empty_global_cluster_example" {
  command = plan

  variables {
    global_cluster_identifier = "app-global"
    engine                    = "aurora-postgresql"
    engine_version            = "16.4"
    database_name             = "app"
    force_destroy             = true
  }
}

run "readme_source_cluster_example" {
  command = plan

  variables {
    global_cluster_identifier    = "app-global"
    source_db_cluster_identifier = "arn:aws:rds:us-east-1:111122223333:cluster:app-primary"
    storage_encrypted            = null
    force_destroy                = true
  }
}
