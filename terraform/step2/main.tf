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
  folder_id                = local.folder_id
  zone                     = "ru-central1-a"
}

data "yandex_vpc_network" "foo" {
  network_id = "enp4r5te1vc24f5h861e"
}

data "yandex_vpc_subnet" "foo" {
  subnet_id = "e9brip4kt9bi2c1kvv8n"
}

data "yandex_container_registry" "registry1" {
  name = "registry1"
}

locals {
  folder_id = var.folderID
  service-accounts = toset([
    "bingo-sa",
    "bingo-ig-sa",
  ])
  bingo-sa-roles = toset([
    "container-registry.images.puller",
    "monitoring.editor",
  ])
  bingo-ig-sa-roles = toset([
    "compute.editor",
    "iam.serviceAccounts.user",
    "load-balancer.admin",
    "vpc.publicAdmin",
    "vpc.user",
  ])
}

resource "yandex_iam_service_account" "service-accounts" {
  for_each = local.service-accounts
  name     = "${local.folder_id}-${each.key}"
}

resource "yandex_resourcemanager_folder_iam_member" "bingo-roles" {
  for_each  = local.bingo-sa-roles
  folder_id = local.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["bingo-sa"].id}"
  role      = each.key
}

resource "yandex_resourcemanager_folder_iam_member" "bingo-ig-roles" {
  for_each  = local.bingo-ig-sa-roles
  folder_id = local.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["bingo-ig-sa"].id}"
  role      = each.key
}

data "yandex_compute_image" "coi" {
  family = "container-optimized-image"
}

resource "yandex_compute_instance_group" "bingo" {
  depends_on = [
    yandex_resourcemanager_folder_iam_member.bingo-ig-roles
  ]
  name               = "bingo"
  service_account_id = yandex_iam_service_account.service-accounts["bingo-ig-sa"].id
  allocation_policy {
    zones = ["ru-central1-a"]
  }
  deploy_policy {
    max_unavailable = 1
    max_creating    = 2
    max_expansion   = 2
    max_deleting    = 2
  }
  scale_policy {
    fixed_scale {
      size = 2
    }
  }
  instance_template {
    platform_id        = "standard-v2"
    service_account_id = yandex_iam_service_account.service-accounts["bingo-sa"].id
    resources {
      cores         = 2
      memory        = 1
      core_fraction = 50
    }
    scheduling_policy {
      preemptible = true
    }
    network_interface {
      network_id = data.yandex_vpc_network.foo.id
      subnet_ids = ["${data.yandex_vpc_subnet.foo.id}"]
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
      docker-compose = templatefile(
        "${path.module}/docker-compose.yaml",
        {
          folder_id   = "${local.folder_id}",
          registry_id = "${data.yandex_container_registry.registry1.id}",
        }
      )
      user-data = file("${path.module}/cloud-config.yaml")
      ssh-keys  = "ubuntu:${file("~/.ssh/devops_training.pub")}"
    }
  }
  load_balancer {
    target_group_name = "bingo"
  }
}

resource "yandex_lb_network_load_balancer" "lb-bingo" {
  name = "bingo"

  listener {
    name        = "bingo-listener"
    port        = 80
    target_port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  listener {
    name        = "bingo-listener443"
    port        = 443
    target_port = 443
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_compute_instance_group.bingo.load_balancer[0].target_group_id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/ping"
      }
    }
  }
}