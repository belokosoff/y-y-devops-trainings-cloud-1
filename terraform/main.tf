terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  service_account_key_file = "./tf_key.json"
  folder_id                = var.folder_id
  zone                     = "ru-central1-a"
}

resource "yandex_vpc_network" "foo" {}

resource "yandex_vpc_subnet" "foo" {
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.foo.id
  v4_cidr_blocks = ["10.5.0.0/24"]
}

variable "folder_id" {
  type = string
}

resource "yandex_container_registry" "registry1" {
  name = "registry1"
}

resource "yandex_lb_network_load_balancer" "my_nlb" {
  name = "my-network-load-balancer"

  listener {
    name = "my-listener"
    port = 8080
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_compute_instance_group.catgpt.load_balancer.0.target_group_id

    healthcheck {
      name = "http"
      http_options {
        port = 8080
        path = "/ping"
      }
    }
  }
}

locals {
  service-accounts = toset([
    "catgpt-sa", "catgpt-ig-sa"
  ])
  catgpt-sa-roles = toset([
    "container-registry.images.puller",
    "monitoring.editor",
  ])
  catgpt-ig-sa-roles = toset([
    "compute.editor",
    "iam.serviceAccounts.user",
    "load-balancer.admin",
    "vpc.publicAdmin",  
    "vpc.user", 
  ])
}

resource "yandex_iam_service_account" "service-accounts" {
  for_each = local.service-accounts
  name     = "${var.folder_id}-${each.key}"
}
resource "yandex_resourcemanager_folder_iam_member" "catgpt-roles" {
  for_each  = local.catgpt-sa-roles
  folder_id = var.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["catgpt-sa"].id}"
  role      = each.key
}
resource "yandex_resourcemanager_folder_iam_member" "catgpt-ig-roles" {
  for_each  = local.catgpt-ig-sa-roles
  folder_id = var.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["catgpt-ig-sa"].id}"
  role      = each.key
}

data "yandex_compute_image" "coi" {
  family = "container-optimized-image"
}
resource "yandex_compute_instance_group" "catgpt" {
  depends_on = [yandex_resourcemanager_folder_iam_member.catgpt-ig-roles]
  folder_id  = var.folder_id
  service_account_id = yandex_iam_service_account.service-accounts["catgpt-ig-sa"].id
  scale_policy {
    fixed_scale {
      size = 2
    }
  }
  deploy_policy {
    max_unavailable = 1
    max_expansion = 1

  }
  allocation_policy {
    zones = ["ru-central1-a"]
  }

  instance_template {
    platform_id = "standard-v2"
    service_account_id = yandex_iam_service_account.service-accounts["catgpt-sa"].id
    resources {
      cores  = 2
      memory = 1
      core_fraction = 5
    }
    scheduling_policy {

      preemptible = true
    }
    network_interface {
      subnet_ids = ["${yandex_vpc_subnet.foo.id}"]
      nat        = true
    }
    boot_disk {
      initialize_params {
        type     = "network-hdd"
        size     = "30"
        image_id = data.yandex_compute_image.coi.id
      }
    }
    metadata = {
      user-data = "${file("cloud-config.yaml")}"
      docker-compose = templatefile("${path.module}/docker-compose.yaml", {
        registry_id = yandex_container_registry.registry1.id,
        folder_id   = var.folder_id
      })
      ssh-keys = "ubuntu:${file("~/.ssh/devops_training.pub")}"
    }
  }
}

