provider "alicloud" {
  region = var.region
}

data "alicloud_account" "current" {}

data "alicloud_zones" "available" {
  available_resource_creation = "VSwitch"
}

data "alicloud_cs_cluster_credential" "ack" {
  cluster_id                 = alicloud_cs_managed_kubernetes.main.id
  temporary_duration_minutes = var.ack_kubeconfig_ttl_minutes
}

locals {
  name_prefix = lower(replace("${var.project_name}-${var.moodle_environment}", "_", "-"))

  common_tags = merge(
    {
      project     = var.project_name
      environment = var.moodle_environment
      managed_by  = "terraform"
      stack       = "moodle-high-scale-alibaba2"
    },
    var.common_tags
  )

  settings = var.environment_configuration[var.moodle_environment]

  selected_zone_id = coalesce(var.availability_zone_id, data.alicloud_zones.available.zones[0].id)

  ack_kubeconfig         = try(yamldecode(data.alicloud_cs_cluster_credential.ack.kube_config), {})
  ack_kubeconfig_cluster = try(local.ack_kubeconfig["clusters"][0]["cluster"], {})
  ack_kubeconfig_user    = try(local.ack_kubeconfig["users"][0]["user"], {})
}

provider "kubernetes" {
  host                   = try(local.ack_kubeconfig_cluster["server"], null)
  cluster_ca_certificate = try(base64decode(local.ack_kubeconfig_cluster["certificate-authority-data"]), null)
  client_certificate     = try(base64decode(local.ack_kubeconfig_user["client-certificate-data"]), null)
  client_key             = try(base64decode(local.ack_kubeconfig_user["client-key-data"]), null)
}
