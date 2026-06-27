terraform {
  # Utilizes .envrc to pull from encrypted secret.yaml.
  backend "local" { path = "../../.tfstate/unifi/terraform.tfstate" }
  required_providers {
    # Allows access to netcup. See hornc-greedy/netcup GitHub for API access docs.
    unifi = {
      source  = "ubiquiti-community/unifi"
      version = "0.53.0"
    }
    # Allows SOPs decryption of secrets.
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.4"
    }
    # Allows access to local file system.
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9.0"
    }
  }
}

data "sops_file" "unifi" {
  source_file = "${path.module}/secret.yaml"
}

provider "unifi" {
  api_url        = data.sops_file.unifi.data["unifi_api_url"]
  api_key        = data.sops_file.unifi.data["unifi_api_key"]
  allow_insecure = true
}


resource "unifi_wireguard_peer" "netcup" {
  network_id   = data.sops_file.unifi.data["wg_server_id"]
  name         = "netcup"
  interface_ip = data.sops_file.unifi.data["wg_interface_ip"]
  public_key   = data.sops_file.unifi.data["wg_public_key"]
}
