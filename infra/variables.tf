variable "project_name" {
  type        = string
  description = "Project name prefix used for naming resources."
  default     = "moodle-high-scale"
}

variable "region" {
  type        = string
  description = "Alibaba Cloud region for deployment."
  default     = "ap-southeast-1"
}

variable "availability_zone_id" {
  type        = string
  description = "Optional ACK/NAS zone override."
  default     = null
}

variable "rds_availability_zone_id" {
  type        = string
  description = "Optional dedicated zone for RDS."
  default     = null
}

variable "moodle_environment" {
  type        = string
  description = "Environment label used in naming and tags."
  default     = "production"

  validation {
    condition     = contains(["development", "production"], var.moodle_environment)
    error_message = "moodle_environment must be development or production."
  }
}

variable "common_tags" {
  type        = map(string)
  description = "Additional tags shared by resources."
  default     = {}
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC."
  default     = "10.254.0.0/16"
}

variable "ack_vswitch_cidr" {
  type        = string
  description = "CIDR block for ACK subnet."
  default     = "10.254.0.0/22"
}

variable "db_vswitch_cidr" {
  type        = string
  description = "CIDR block for database subnet."
  default     = "10.254.6.0/24"
}

variable "nas_vswitch_cidr" {
  type        = string
  description = "CIDR block for NAS subnet."
  default     = "10.254.8.0/24"
}

variable "ack_cluster_spec" {
  type        = string
  description = "ACK cluster specification tier."
  default     = "ack.pro.small"
}

variable "ack_cluster_profile" {
  type        = string
  description = "ACK API profile field for cluster creation (provider-level setting, not a template sizing mode)."
  default     = "Default"
}

variable "ack_kubernetes_version" {
  type        = string
  description = "Optional ACK Kubernetes version pin."
  default     = null
}

variable "ack_proxy_mode" {
  type        = string
  description = "kube-proxy mode for ACK cluster."
  default     = "ipvs"
}

variable "ack_service_cidr" {
  type        = string
  description = "Kubernetes service CIDR."
  default     = "172.29.100.0/24"
}

variable "ack_pod_vswitch_ids" {
  type        = list(string)
  description = "Optional pod vSwitch IDs for Terway."
  default     = null
}

variable "ack_new_nat_gateway" {
  type        = bool
  description = "Create NAT gateway automatically for ACK egress."
  default     = true
}

variable "ack_api_public_enabled" {
  type        = bool
  description = "Expose ACK API server to public network."
  default     = true
}

variable "ack_deletion_protection" {
  type        = bool
  description = "Enable deletion protection on ACK cluster."
  default     = false
}

variable "ack_kubeconfig_ttl_minutes" {
  type        = number
  description = "Temporary kubeconfig TTL (minutes)."
  default     = 60
}

variable "ack_default_system_disk_category" {
  type        = string
  description = "Default system disk category for ACK nodes."
  default     = "cloud_essd"
}

variable "ack_default_system_disk_size" {
  type        = number
  description = "Default system disk size in GiB for ACK nodes."
  default     = 120
}

variable "ack_minimum_eni_private_ip_address_quantity" {
  type        = number
  description = "ENI private IP minimum used when auto-discovering worker instance types."
  default     = 15
}

variable "ack_instance_type_fallback_max_count" {
  type        = number
  description = "Maximum number of fallback instance types to keep per node pool."
  default     = 10
}

variable "ack_enable_nodepool_autoscaling" {
  type        = bool
  description = "Enable node pool autoscaling blocks. Disable only if AliyunCSManagedAutoScalerRole is not authorized yet."
  default     = true
}

variable "ack_node_pool_size_overrides" {
  description = "Optional desired/min/max size overrides per ACK node pool name (for example app/pgbouncer/redis)."
  type = map(object({
    desired_size = optional(number)
    min_size     = optional(number)
    max_size     = optional(number)
  }))
  default = {}
}

variable "ack_cluster_addons" {
  description = "Core ACK addons to install."
  type = list(object({
    name     = string
    config   = optional(string)
    disabled = optional(bool, false)
  }))

  default = [
    { name = "terway-eniip" },
    { name = "csi-plugin" },
    { name = "managed-csiprovisioner" }
  ]
}

variable "ack_node_pools" {
  type        = map(any)
  description = "ACK node pool sizing and scheduling defaults for the 150k design baseline."

  default = {
    system = {
      instance_types       = ["ecs.g6.xlarge", "ecs.c6.xlarge", "ecs.g7.xlarge", "ecs.c7.xlarge", "ecs.g6.2xlarge"]
      min_cpu_core_count   = 4
      min_memory_size_gb   = 8
      desired_size         = 3
      min_size             = 3
      max_size             = 6
      enable_autoscaling   = true
      scaling_type         = "cpu"
      system_disk_category = "cloud_essd"
      system_disk_size     = 200
      labels = {
        role = "system"
      }
      taints = []
    }

    app = {
      instance_types       = ["ecs.c6.2xlarge", "ecs.g6.2xlarge", "ecs.c7.2xlarge", "ecs.g7.2xlarge"]
      min_cpu_core_count   = 8
      min_memory_size_gb   = 16
      desired_size         = 12
      min_size             = 8
      max_size             = 80
      enable_autoscaling   = true
      scaling_type         = "cpu"
      system_disk_category = "cloud_essd"
      system_disk_size     = 200
      labels = {
        workload = "app"
      }
      taints = [
        {
          key    = "workload-type"
          value  = "app"
          effect = "NoSchedule"
        }
      ]
    }

    jobs = {
      instance_types       = ["ecs.c6.xlarge", "ecs.g6.xlarge", "ecs.c7.xlarge", "ecs.g7.xlarge"]
      min_cpu_core_count   = 4
      min_memory_size_gb   = 8
      desired_size         = 3
      min_size             = 2
      max_size             = 20
      enable_autoscaling   = true
      scaling_type         = "cpu"
      system_disk_category = "cloud_essd"
      system_disk_size     = 200
      labels = {
        workload = "jobs"
      }
      taints = [
        {
          key    = "workload-type"
          value  = "jobs"
          effect = "NoSchedule"
        }
      ]
    }

    redis = {
      instance_types       = ["ecs.r6.2xlarge", "ecs.g6.2xlarge", "ecs.r7.2xlarge", "ecs.g7.2xlarge"]
      min_cpu_core_count   = 8
      min_memory_size_gb   = 32
      desired_size         = 6
      min_size             = 4
      max_size             = 24
      enable_autoscaling   = true
      scaling_type         = "cpu"
      system_disk_category = "cloud_essd"
      system_disk_size     = 200
      labels = {
        workload = "redis"
      }
      taints = [
        {
          key    = "workload-type"
          value  = "redis"
          effect = "NoSchedule"
        }
      ]
    }

    pgbouncer = {
      instance_types       = ["ecs.g6.2xlarge", "ecs.c6.2xlarge", "ecs.g7.2xlarge", "ecs.c7.2xlarge"]
      min_cpu_core_count   = 8
      min_memory_size_gb   = 16
      desired_size         = 8
      min_size             = 4
      max_size             = 24
      enable_autoscaling   = true
      scaling_type         = "cpu"
      system_disk_category = "cloud_essd"
      system_disk_size     = 200
      labels = {
        workload = "pgbouncer"
      }
      taints = [
        {
          key    = "workload-type"
          value  = "pgbouncer"
          effect = "NoSchedule"
        }
      ]
    }
  }
}

variable "rds_pg_version" {
  type        = string
  description = "RDS PostgreSQL engine version."
  default     = "15.0"
}

variable "rds_category" {
  type        = string
  description = "RDS edition category."
  default     = "HighAvailability"
}

variable "rds_instance_charge_type" {
  type        = string
  description = "RDS charge type (PostPaid/PrePaid)."
  default     = "PostPaid"
}

variable "rds_db_instance_storage_type" {
  type        = string
  description = "RDS storage type."
  default     = "cloud_essd"
}

variable "rds_instance_type" {
  type        = string
  description = "Optional explicit RDS primary instance class."
  default     = null
}

variable "rds_readonly_instance_type" {
  type        = string
  description = "Optional explicit RDS readonly instance class."
  default     = null
}

variable "rds_instance_storage_gb" {
  type        = number
  description = "RDS primary storage size in GB."
  default     = 512
}

variable "rds_readonly_instance_storage_gb" {
  type        = number
  description = "Optional explicit RDS readonly storage size in GB."
  default     = null
}

variable "rds_readonly_enabled" {
  type        = bool
  description = "Create RDS readonly instance."
  default     = true
}

variable "rds_readonly_commodity_code" {
  type        = string
  description = "Optional explicit commodity code for readonly instance class discovery (for example rords_intl)."
  default     = null
}

variable "rds_database_name" {
  type        = string
  description = "Moodle database name in RDS."
  default     = "moodle"
}

variable "rds_account_name" {
  type        = string
  description = "Moodle account name in RDS."
  default     = "moodleadmin"
}

variable "rds_account_privilege" {
  type        = string
  description = "RDS account privilege level for Moodle account."
  default     = "DBOwner"
}

variable "rds_security_ips" {
  type        = list(string)
  description = "Optional RDS IP whitelist CIDRs. Empty means VPC CIDR is used."
  default     = []
}

variable "rds_create_service_linked_role" {
  type        = bool
  description = "Create AliyunServiceRoleForRdsPgsqlOnEcs automatically."
  default     = false
}

variable "oss_assets_bucket_name" {
  type        = string
  description = "Optional explicit OSS assets bucket name."
  default     = null
}

variable "oss_config_bucket_name" {
  type        = string
  description = "Optional explicit OSS config bucket name."
  default     = null
}

variable "oss_assets_bucket_name_prefix" {
  type        = string
  description = "Prefix used for generated OSS assets bucket name."
  default     = "moodle-assets"
}

variable "oss_config_bucket_name_prefix" {
  type        = string
  description = "Prefix used for generated OSS config bucket name."
  default     = "moodle-config"
}

variable "oss_force_destroy" {
  type        = bool
  description = "Allow destroy with objects still present in OSS buckets."
  default     = false
}

variable "nas_storage_type" {
  type        = string
  description = "NAS storage type (default tuned for higher metadata/IO performance)."
  default     = "Performance"
}

variable "nas_file_system_type" {
  type        = string
  description = "NAS file system type."
  default     = "standard"
}

variable "nas_access_group_name" {
  type        = string
  description = "Optional explicit NAS access group name."
  default     = null
}

variable "nas_rw_access_type" {
  type        = string
  description = "NAS access rule read/write type."
  default     = "RDWR"
}

variable "nas_user_access_type" {
  type        = string
  description = "NAS access rule user access type."
  default     = "no_squash"
}

variable "nas_access_rule_priority" {
  type        = string
  description = "NAS access rule priority."
  default     = "1"
}

variable "objectfs_s3_enabled" {
  type        = bool
  description = "Enable ObjectFS S3-compatible runtime configuration."
  default     = true
}

variable "objectfs_s3_bucket_name" {
  type        = string
  description = "Optional explicit ObjectFS bucket name (defaults to assets bucket)."
  default     = null
}

variable "objectfs_s3_region" {
  type        = string
  description = "Optional explicit ObjectFS S3 region."
  default     = null
}

variable "objectfs_s3_base_url" {
  type        = string
  description = "Optional explicit ObjectFS S3 endpoint URL."
  default     = null
}

variable "objectfs_s3_key_prefix" {
  type        = string
  description = "Object key prefix used by ObjectFS."
  default     = "objectfs/"
}

variable "objectfs_s3_use_sdk_creds" {
  type        = bool
  description = "Use SDK-discovered credentials instead of explicit access key and secret."
  default     = false
}

variable "objectfs_s3_create_ram_credentials" {
  type        = bool
  description = "Create dedicated RAM user/policy/access key for ObjectFS when SDK creds are disabled and static credentials are not provided."
  default     = true
}

variable "objectfs_s3_access_key" {
  type        = string
  description = "Optional explicit access key for ObjectFS S3-compatible authentication (used when objectfs_s3_use_sdk_creds=false)."
  default     = null
  sensitive   = true
}

variable "objectfs_s3_secret" {
  type        = string
  description = "Optional explicit secret key for ObjectFS S3-compatible authentication (used when objectfs_s3_use_sdk_creds=false)."
  default     = null
  sensitive   = true
}

variable "objectfs_s3_ram_user_name" {
  type        = string
  description = "Optional RAM user name for dedicated ObjectFS access key. Null generates a unique name per stack."
  default     = null
}

variable "cr_enabled" {
  type        = bool
  description = "Enable CR EE provisioning."
  default     = false
}

variable "cr_existing_instance_id" {
  type        = string
  description = "Optional existing CR EE instance ID to reuse."
  default     = null
}

variable "cr_instance_type" {
  type        = string
  description = "CR EE instance type."
  default     = "Basic"
}

variable "cr_period" {
  type        = number
  description = "CR EE subscription period in months."
  default     = 1
}

variable "cr_renew_period" {
  type        = number
  description = "CR EE auto-renew period in months."
  default     = 1
}

variable "cr_renewal_status" {
  type        = string
  description = "CR EE renewal status."
  default     = "AutoRenewal"
}

variable "cr_namespace" {
  type        = string
  description = "CR namespace for Moodle images."
  default     = "moodle-high-scale"
}

variable "cr_repo_moodle_name" {
  type        = string
  description = "CR repository name for Moodle image."
  default     = "moodle"
}

variable "cr_repo_pgbouncer_name" {
  type        = string
  description = "CR repository name for PgBouncer image."
  default     = "pgbouncer"
}

variable "cr_link_ack_vpc_endpoint" {
  type        = bool
  description = "Link ACR EE Registry module to the ACK VPC and vSwitch."
  default     = true
}

variable "cr_vpc_endpoint_enable_privatezone_dns" {
  type        = bool
  description = "Automatically create PrivateZone DNS record when linking ACR VPC endpoint."
  default     = true
}

variable "cr_registry_endpoint_prefer_vpc" {
  type        = bool
  description = "Prefer ACR VPC endpoint over public endpoint for runtime image pulls."
  default     = true
}

variable "cr_enable_internet_acl_service" {
  type        = bool
  description = "Enable ACR internet endpoint ACL service (fallback path when VPC endpoint is not used)."
  default     = false
}

variable "cr_internet_acl_entries" {
  type        = list(string)
  description = "CIDR entries allowed by ACR internet endpoint ACL (for example [\"203.0.113.10/32\"])."
  default     = []
}

variable "redis_session_host" {
  type        = string
  description = "Redis session host consumed by Moodle runtime secret."
  default     = "redis-cluster-svc"
}

variable "redis_session_port" {
  type        = string
  description = "Redis session port consumed by Moodle runtime secret."
  default     = "6379"
}

variable "redis_cache_host" {
  type        = string
  description = "Redis cache host consumed by Moodle runtime secret."
  default     = "redis-cache-cluster-svc"
}

variable "redis_cache_port" {
  type        = string
  description = "Redis cache port consumed by Moodle runtime secret."
  default     = "6379"
}

variable "moodle_database_prefix" {
  type        = string
  description = "Moodle DB table prefix."
  default     = "md_"
}

variable "moodle_www_root" {
  type        = string
  description = "Public Moodle URL. Leave empty to auto-detect from incoming request host during bootstrap."
  default     = ""

  validation {
    condition     = var.moodle_www_root == "" || can(regex("^https?://", var.moodle_www_root))
    error_message = "moodle_www_root must be empty or start with http:// or https://."
  }
}

variable "moodle_data_root" {
  type        = string
  description = "Moodle data root path in container."
  default     = "/var/www/moodledata"
}

variable "moodle_admin_user" {
  type        = string
  description = "Moodle admin username in generated config."
  default     = "admin"
}

variable "moodle_ssl_proxy" {
  type        = string
  description = "Moodle SSL proxy flag in generated config."
  default     = "false"
}

variable "moodle_muc_autoconfig_enabled" {
  type        = bool
  description = "Enable automatic MUC cache store and mapping bootstrap on container startup."
  default     = true
}

variable "pgbouncer_max_client_conn" {
  type        = string
  description = "PgBouncer MAX_CLIENT_CONN."
  default     = "20000"
}

variable "pgbouncer_default_pool_size" {
  type        = string
  description = "PgBouncer DEFAULT_POOL_SIZE."
  default     = "235"
}

variable "pgbouncer_min_pool_size" {
  type        = string
  description = "PgBouncer MIN_POOL_SIZE."
  default     = "235"
}

variable "pgbouncer_server_tls_sslmode" {
  type        = string
  description = "PgBouncer SERVER_TLS_SSLMODE."
  default     = "prefer"
}
