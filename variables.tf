variable "global_cluster_identifier" {
  default     = null
  description = "Identifier of the global cluster. Must begin with a letter and contain only lowercase alphanumeric characters and hyphens — AWS rejects anything else. If null, a unique identifier is generated. Cannot be changed afterward without replacing the global cluster."

  validation {
    condition     = var.global_cluster_identifier == null || can(regex("^[a-z][a-z0-9-]*$", var.global_cluster_identifier))
    error_message = "A global cluster identifier must begin with a letter and contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "engine" {
  default     = null
  description = "Engine of the global database ('aurora-postgresql' or 'aurora-mysql'). Set it, with engine_version, to create an empty global cluster that regional clusters then join. Cannot be changed afterward without replacing the global cluster. Mutually exclusive with source_db_cluster_identifier."

  validation {
    condition     = var.engine != null || var.source_db_cluster_identifier != null
    error_message = "Either engine, to create an empty global cluster, or source_db_cluster_identifier, to adopt an existing cluster as the primary, must be set. AWS's own default engine for a global cluster is the retired 'aurora' engine, so leaving both unset does not produce a usable global database."
  }

  validation {
    condition     = var.source_db_cluster_identifier == null || (var.engine == null && var.engine_version == null)
    error_message = "engine and engine_version cannot be combined with source_db_cluster_identifier. The global cluster inherits both from the source cluster and ignores whatever is configured here, then reports the difference as an in-place update on every subsequent plan."
  }
}

variable "engine_version" {
  default     = null
  description = "Engine version of the global database (e.g. '16.4'). The engine, the version, and each member cluster's instance class must together support global databases. Raising it here upgrades every member cluster in place. If null, AWS picks its own current default for the engine."
}

variable "engine_lifecycle_support" {
  default     = null
  description = "Whether the global cluster stays on RDS Extended Support once its engine version reaches community end of life ('open-source-rds-extended-support'), or is upgraded by AWS instead ('open-source-rds-extended-support-disabled'). Applies to Aurora PostgreSQL only, and Extended Support carries its own charge. If null, AWS's own default (Extended Support enabled) applies."
}

variable "source_db_cluster_identifier" {
  default     = null
  description = "ARN of an existing Aurora cluster to adopt as the global database's primary, instead of creating an empty global cluster. Requires force_destroy. AWS offers no way to read this value back, so Terraform cannot detect drift on it; once the global cluster exists it may be removed from the configuration and replaced with engine and engine_version. Mutually exclusive with engine and engine_version."
}

variable "database_name" {
  default     = null
  description = "Name of a database created on the global cluster when it is first provisioned. The primary member cluster must be given the same database_name. Cannot be changed afterward without replacing the global cluster. If null, no database is created."
}

variable "storage_encrypted" {
  default     = true
  description = "Whether the global database's storage is encrypted at rest. Defaults true — encryption cannot be enabled in place afterward, only by rebuilding the global database. When adopting an existing cluster through source_db_cluster_identifier this must agree with that cluster's own encryption state; set it to null to inherit whatever the source uses."
}

variable "deletion_protection" {
  default     = false
  description = "Whether AWS refuses to delete the global cluster while set. Defaults false, since enabling it makes terraform destroy fail until a separate apply turns it off again."
}

variable "force_destroy" {
  default     = null
  description = "Whether destroying the global cluster first detaches its member clusters. Without it, a destroy fails for as long as any member remains and the members have to be detached by hand. With it, the member clusters survive as independent regional clusters rather than being deleted, but they stop replicating to one another. If null, AWS's own default (refuse the destroy) applies."

  validation {
    condition     = var.source_db_cluster_identifier == null || var.force_destroy != null
    error_message = "force_destroy must be set whenever source_db_cluster_identifier is, since the source cluster is a member of the global cluster from the moment it is created and a global cluster that still has members cannot be destroyed."
  }
}

variable "tags" {
  default     = null
  description = "A map of tags to assign to the global cluster."
}
