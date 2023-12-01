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
  folder_id                = var.folderID
  zone                     = "ru-central1-a"
}

resource "yandex_container_registry" "registry1" {
  name = "registry1"
}
