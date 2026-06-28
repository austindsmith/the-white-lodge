terraform {
  backend "local" { path = "../../.tfstate/unifi/terraform.tfstate" }
  required_providers {
    ansible = {
      source  = "ansible/ansible"
      version = "1.4.0"
    }
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

data "onepassword_item" "ansible" {
  vault = "the-white-lodge"
  title = "ansible"
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
  ansible = data.onepassword_item.ansible.section_map[""].field_map

  netcup = data.onepassword_item.netcup.section_map[""].field_map

  unifi = data.onepassword_item.unifi.section_map[""].field_map

}

output "debug_ansible_fields" {
  value = keys(data.onepassword_item.ansible.section_map[""].field_map)
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

resource "ansible_playbook" "wireguard" {
  playbook   = "${path.cwd}/../../ansible/playbooks/wireguard.yml"
  name       = local.netcup["public_ip_address"].value
  replayable = true
  extra_vars = {
    wg_interface_ip              = local.netcup["wg_ip_address"].value
    wg_server_endpoint           = local.unifi["public_ip_address"].value
    wg_server_pubkey             = local.unifi["wg_server_pub_key"].value
    wg_listen_port               = local.unifi["wg_listen_port"].value
    wg_private_key               = wireguard_asymmetric_key.netcup.private_key
    ansible_user                 = data.onepassword_item.ansible.username
    ansible_become_user          = local.ansible["become_user"].value
    ansible_become_password      = data.onepassword_item.ansible.password
    ansible_ssh_private_key_file = local.ansible["ssh_private_key_file"].value
  }
  depends_on = [unifi_wireguard_peer.netcup]
}

resource "ansible_playbook" "site" {
  playbook   = "${path.cwd}/../../ansible/playbooks/kubernetes.yml"
  name       = local.netcup["public_ip_address"].value
  replayable = true
  extra_vars = {
    ansible_user                 = data.onepassword_item.ansible.username
    ansible_become_user          = local.ansible["become_user"].value
    ansible_become_password      = data.onepassword_item.ansible.password
    ansible_ssh_private_key_file = local.ansible["ssh_private_key_file"].value
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
