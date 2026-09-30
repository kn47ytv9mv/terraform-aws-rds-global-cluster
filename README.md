# terraform-aws-rds-global-cluster

Terraform module for an Aurora global database — one logical database
spanning several AWS regions, with a single writable primary cluster and
read-only secondary clusters that the Aurora storage layer replicates to
directly.

## Cost

The global cluster itself is a grouping and carries no charge of its own.
The cost is the sum of its members: every regional cluster in the global
database bills in full for its own instances, storage, I/O, and backups,
so adding a region multiplies the compute and storage bill rather than
sharing it. On top of that, Aurora bills the replicated writes it sends
between regions and the cross-region data transfer they consume, neither
of which a single-region cluster pays at all. `engine_lifecycle_support`
adds RDS Extended Support charges when a version is kept past its
community end of life. See AWS's
[Aurora pricing](https://aws.amazon.com/rds/aurora/pricing/) page for
current rates.

## Design

This module wraps only the global cluster. The regional clusters that
make up its membership are
[`terraform-aws-rds-cluster`](https://github.com/kn47ytv9mv/terraform-aws-rds-cluster)
calls, each with its own provider, and each joins by passing this
module's `id` output as its own `global_cluster_identifier`.

### Two ways to create one

A global cluster is created either empty or from an existing cluster, and
the two are mutually exclusive.

Setting `engine` and `engine_version` creates an empty global cluster
with no members. The primary regional cluster is created afterward and
joins it, at which point AWS makes that cluster the writer. This is the
path to use whenever the primary cluster is also managed here, because
the dependency runs one way only: the global cluster knows nothing about
its members, and each member names the global cluster.

Setting `source_db_cluster_identifier` to an existing cluster's ARN
instead promotes that cluster to primary of a new global database, and
the global cluster inherits its engine and version. Reserve this for a
cluster this configuration does not manage, or manages in a separate
state. A cluster built by `terraform-aws-rds-cluster` in the same
configuration cannot be adopted this way: AWS populates that cluster's
own `global_cluster_identifier` as a side effect, which the module then
plans to remove on the next run, and pointing the module at this one
instead would make the two reference each other.

`engine` and `source_db_cluster_identifier` therefore reject each other,
as do `engine_version` and `source_db_cluster_identifier`. AWS does not
error on the combination — it silently ignores the configured engine
values at creation, then reports them as a pending in-place update
forever after — so this module rejects it at plan time instead.

### Ordering across regions

A global database is built in three steps, and the order is not
negotiable:

1. The global cluster, in the primary region.
2. The primary regional cluster, which joins it and owns the master
   credentials — this is the only member that accepts writes, so it is
   the only member given `master_username` and a password.
3. Each secondary regional cluster, in another region through a second
   provider alias, with no master credentials of its own and
   `depends_on` the primary. AWS rejects a secondary that supplies
   credentials, because it replicates the primary's users rather than
   creating its own, and it rejects one created before the primary has a
   running instance.

The Usage section's third example shows this shape in full.

Leave `engine_version` unset on every member cluster and set it only
here. `terraform-aws-rds-cluster` passes the value straight through to an
attribute AWS computes when it is absent, so an unset version on the
members lets a global-level upgrade land without any member's
configuration disagreeing with it afterward. Set the same value in both
places and the member's configuration goes stale the moment the global
cluster upgrades it.

`terraform-aws-rds-cluster` does not need `engine_mode` set for either
role. The `'global'` mode belongs to the retired Aurora MySQL 5.6
generation of global databases; a current Aurora global cluster is built
out of ordinary `'provisioned'` clusters.

### Secondary clusters and replication_source_identifier

AWS reports a replication source on a secondary member that no one
configured. `terraform-aws-rds-cluster` exposes
`replication_source_identifier` as a plain optional input, so a secondary
built through it with that input left unset will show AWS's value being
removed on the next plan, and applying that change promotes the secondary
out of the global database rather than doing nothing. Set the secondary's
`replication_source_identifier` to whatever AWS reports so that its
configuration agrees, or keep the secondary in a state that is not
applied alongside the rest of the global database. Do not apply that
particular diff unreviewed.

### force_destroy

`force_destroy` decides what happens to the membership when the global
cluster is destroyed, and it is left unset rather than given a default,
because both answers are consequential. Without it, `terraform destroy`
fails for as long as any member remains, and the members have to be
detached by hand before the destroy can complete. With it, the destroy
detaches every member first — the regional clusters themselves survive as
independent clusters and none of their data is deleted, but they stop
replicating to one another, and a cluster whose disaster-recovery story
depended on that replication no longer has one. Set it deliberately for a
global database that is meant to be torn down and rebuilt; leave it unset
for one that is not.

It is required whenever `source_db_cluster_identifier` is set, since the
adopted cluster is a member from the moment the global cluster exists and
the destroy would otherwise be impossible from the first apply onward.

### Engine version upgrades

An engine version upgrade is driven from the global cluster, not from its
members. Raising `engine_version` here upgrades every member cluster in
place, in AWS's own order, which is why the members should not carry a
version of their own. There is no way to upgrade one region at a time.

### Deliberately not covered

Failover between regions is not expressed here. Promoting a secondary to
primary, whether as a planned switchover or an unplanned failover, is an
operational action taken against the running global database rather than
a change to its configuration, and modelling it as one would mean
Terraform fighting whatever the operator just did.

## Usage

```hcl
module "global_cluster" {
  source = "kn47ytv9mv/rds-global-cluster/aws"

  global_cluster_identifier = "app-global"
  engine                    = "aurora-postgresql"
  engine_version            = "16.4"
  database_name             = "app"

  force_destroy = true
}
```

Or directly from this repository, adopting a cluster that already exists
as the new global database's primary:

```hcl
module "global_cluster" {
  source = "github.com/kn47ytv9mv/terraform-aws-rds-global-cluster"

  global_cluster_identifier    = "app-global"
  source_db_cluster_identifier = "arn:aws:rds:us-east-1:111122223333:cluster:app-primary"

  storage_encrypted = null
  force_destroy     = true
}
```

A complete two-region global database, with the primary in `us-east-1`
and a read-only secondary in `eu-west-1`:

```hcl
provider "aws" {
  alias  = "primary"
  region = "us-east-1"
}

provider "aws" {
  alias  = "secondary"
  region = "eu-west-1"
}

module "global_cluster" {
  source    = "kn47ytv9mv/rds-global-cluster/aws"
  providers = { aws = aws.primary }

  global_cluster_identifier = "app-global"
  engine                    = "aurora-postgresql"
  engine_version            = "16.4"
  database_name             = "app"

  force_destroy = true
}

module "primary_cluster" {
  source    = "kn47ytv9mv/rds-cluster/aws"
  providers = { aws = aws.primary }

  cluster_identifier        = "app-primary"
  global_cluster_identifier = module.global_cluster.id
  engine                    = module.global_cluster.engine

  database_name   = "app"
  master_username = "app"

  manage_master_user_password = true

  instance_class            = "db.r7g.large"
  instance_count            = 2
  db_subnet_group_name      = "app-primary"
  final_snapshot_identifier = "app-primary-final"
}

module "secondary_cluster" {
  source    = "kn47ytv9mv/rds-cluster/aws"
  providers = { aws = aws.secondary }

  cluster_identifier        = "app-secondary"
  global_cluster_identifier = module.global_cluster.id
  engine                    = module.global_cluster.engine

  instance_class            = "db.r7g.large"
  instance_count            = 1
  db_subnet_group_name      = "app-secondary"
  final_snapshot_identifier = "app-secondary-final"

  depends_on = [module.primary_cluster]
}
```

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.9 |
| aws | ~> 6.61 |
| random | ~> 3.9 |

## Providers

| Name | Version |
|---|---|
| aws | ~> 6.61 |
| random | ~> 3.9 |

## Inputs

| Name | Description | Default | Required |
|---|---|---|---|
| global_cluster_identifier | Identifier of the global cluster. Must begin with a letter and contain only lowercase alphanumeric characters and hyphens. If null, a unique identifier is generated. Cannot be changed afterward without replacing the global cluster. | `null` | no |
| engine | Engine of the global database (`'aurora-postgresql'` or `'aurora-mysql'`). Set it, with `engine_version`, to create an empty global cluster that regional clusters then join. Mutually exclusive with `source_db_cluster_identifier`. | `null` | no |
| engine_version | Engine version of the global database (e.g. `'16.4'`). Raising it upgrades every member cluster in place. If null, AWS picks its own current default for the engine. | `null` | no |
| engine_lifecycle_support | Whether the global cluster stays on RDS Extended Support past its engine version's community end of life (`'open-source-rds-extended-support'`) or is upgraded by AWS instead (`'open-source-rds-extended-support-disabled'`). Aurora PostgreSQL only, and billed separately. | `null` | no |
| source_db_cluster_identifier | ARN of an existing Aurora cluster to adopt as the global database's primary, instead of creating an empty global cluster. Requires `force_destroy`. Terraform cannot detect drift on it. Mutually exclusive with `engine` and `engine_version`. | `null` | no |
| database_name | Name of a database created on the global cluster when it is first provisioned. The primary member cluster must be given the same `database_name`. | `null` | no |
| storage_encrypted | Whether the global database's storage is encrypted at rest. Defaults true — encryption cannot be enabled in place afterward. When adopting a cluster through `source_db_cluster_identifier` this must agree with that cluster's own encryption state; set it to null to inherit. | `true` | no |
| deletion_protection | Whether AWS refuses to delete the global cluster while set. Defaults false, since enabling it makes `terraform destroy` fail until a separate apply turns it off. | `false` | no |
| force_destroy | Whether destroying the global cluster first detaches its member clusters. Without it a destroy fails while any member remains; with it the members survive as independent clusters but stop replicating. Required with `source_db_cluster_identifier`. | `null` | no |
| tags | A map of tags to assign to the global cluster. | `null` | no |

## Outputs

| Name | Description |
|---|---|
| id | The ID of the global cluster, which is its identifier. Pass this to each member cluster's `global_cluster_identifier`. |
| arn | The ARN of the global cluster. |
| global_cluster_identifier | The identifier of the global cluster. |
| endpoint | Writer endpoint of the global database. It follows the writer instance of whichever regional cluster is currently primary, including across a failover to another region. |
| engine | Engine of the global database, resolved by AWS when it was inherited from a source cluster rather than configured. Pass it to each member cluster. |
| engine_version | Engine version configured on the global database, or the version inherited from a source cluster. |
| engine_version_actual | Engine version the global database is actually running, which is more specific than `engine_version` whenever only a partial version was configured. |
| global_cluster_resource_id | AWS's own immutable identifier for the global cluster, which appears in the CloudTrail entries recording use of its KMS key. |
| global_cluster_members | Every regional cluster currently joined to the global database, each with its ARN and whether it is the primary. |

## License

MIT — see [LICENSE.md](LICENSE.md).
