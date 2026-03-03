terraform {
  required_version = ">= 1.4.0"

  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~> 1.271.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
