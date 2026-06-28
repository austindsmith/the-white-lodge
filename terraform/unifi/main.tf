terraform {
  backend "local" { path = "../../.tfstate/unifi/terraform.tfstate" }
  required_providers {
    unifi = {
      source  = "ubiquiti-community/unifi"
      version = "0.53.0"
    }
    wireguard = {
      source  = "OJFord/wireguard"
      version = "0.4.0"
    }
    ansible = {
      source  = "ansible/ansible"
      version = "1.4.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.4"
    }
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

provider "wireguard" {}

resource "wireguard_asymmetric_key" "netcup" {}

resource "unifi_wireguard_peer" "netcup" {
  network_id   = data.sops_file.unifi.data["wg_server_id"]
  name         = "netcup"
  interface_ip = data.sops_file.unifi.data["wg_interface_ip"]
  public_key   = wireguard_asymmetric_key.netcup.public_key
}

resource "ansible_playbook" "wireguard" {
  playbook   = "${path.cwd}/../../ansible/playbooks/wireguard.yml"
  name       = data.sops_file.unifi.data["netcup_host"]
  replayable = true
  extra_vars = {
    wg_interface_ip              = data.sops_file.unifi.data["wg_interface_ip"]
    wg_server_endpoint           = data.sops_file.unifi.data["wg_server_endpoint"]
    wg_server_pubkey             = data.sops_file.unifi.data["wg_server_pubkey"]
    wg_listen_port               = data.sops_file.unifi.data["wg_listen_port"]
    wg_private_key               = wireguard_asymmetric_key.netcup.private_key
    ansible_user                 = data.sops_file.unifi.data["ansible_user"]
    ansible_become_user          = data.sops_file.unifi.data["ansible_become_user"]
    ansible_become_password      = data.sops_file.unifi.data["ansible_become_password"]
    ansible_ssh_private_key_file = data.sops_file.unifi.data["ansible_ssh_private_key_file"]
  }
  depends_on = [unifi_wireguard_peer.netcup]
}

resource "ansible_playbook" "site" {
  playbook   = "${path.cwd}/../../ansible/playbooks/kubernetes.yml"
  name       = data.sops_file.unifi.data["netcup_host"]
  replayable = true
  extra_vars = {
    ansible_user                 = data.sops_file.unifi.data["ansible_user"]
    ansible_become_user          = data.sops_file.unifi.data["ansible_become_user"]
    ansible_become_password      = data.sops_file.unifi.data["ansible_become_password"]
    ansible_ssh_private_key_file = data.sops_file.unifi.data["ansible_ssh_private_key_file"]
  }
  depends_on = [ansible_playbook.wireguard]
}

output "wg_public_key" {
  description = "netcup public WireGuard key"
  value       = wireguard_asymmetric_key.netcup.public_key
}

output "wg_private_key" {
  description = "netcup private WireGuard key"
  value       = wireguard_asymmetric_key.netcup.private_key
  sensitive   = true
}
