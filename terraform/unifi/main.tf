terraform {
  backend "local" { path = "../../.tfstate/unifi/terraform.tfstate" }
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "3.3.1"
    }
    unifi = {
      source  = "ubiquiti-community/unifi"
      version = "0.53.0"
    }
    wireguard = {
      source  = "OJFord/wireguard"
      version = "0.4.0"
    }
  }
}

provider "onepassword" {
  account = "my.1password.com"
}

data "onepassword_vault" "white_lodge" {
  name = "the-white-lodge"
}

data "onepassword_item" "netcup" {
  vault = "the-white-lodge"
  title = "netcup"
}

data "onepassword_item" "unifi" {
  vault = "the-white-lodge"
  title = "unifi"
}

locals {
  netcup = data.onepassword_item.netcup.section_map[""].field_map
  unifi  = data.onepassword_item.unifi.section_map[""].field_map
}

provider "unifi" {
  api_url        = local.unifi["api_url"].value
  api_key        = local.unifi["api_key"].value
  allow_insecure = true
}

provider "wireguard" {}

resource "wireguard_asymmetric_key" "netcup" {}

resource "unifi_wireguard_peer" "netcup" {
  network_id   = local.unifi["wg_server_id"].value
  name         = "netcup"
  interface_ip = local.netcup["wg_ip_address"].value
  public_key   = wireguard_asymmetric_key.netcup.public_key
}

resource "onepassword_item" "wireguard_netcup" {
  vault    = data.onepassword_vault.white_lodge.uuid
  title    = "wireguard-netcup"
  category = "password"

  section {
    label = "wireguard"

    field {
      label = "public_key"
      type  = "STRING"
      value = wireguard_asymmetric_key.netcup.public_key
    }

    field {
      label = "private_key"
      type  = "CONCEALED"
      value = wireguard_asymmetric_key.netcup.private_key
    }

    field {
      label = "interface_ip"
      type  = "STRING"
      value = local.netcup["wg_ip_address"].value
    }

    field {
      label = "server_endpoint"
      type  = "STRING"
      value = "${local.unifi["public_ip_address"].value}:${local.unifi["wg_listen_port"].value}"
    }

    field {
      label = "server_public_key"
      type  = "STRING"
      value = local.unifi["wg_server_pub_key"].value
    }
  }
}

output "wg_public_key" {
  value = wireguard_asymmetric_key.netcup.public_key
}
