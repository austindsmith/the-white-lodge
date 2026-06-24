terraform {
  # Utilizes .envrc to pull from encrypted secret.yaml.
  backend "local" { path = "../../.tfstate/netcup/terraform.tfstate" }
  #backend "s3" {
  #  bucket                      = "state"
  #  key                         = "migration/netcup.tfstate"
  #  region                      = "us-east-1"
  #  skip_credentials_validation = true
  #  skip_region_validation      = true
  #  skip_requesting_account_id  = true
  #  skip_s3_checksum            = true
  #  use_path_style              = true
  #}
  required_providers {
    # Allows access to netcup. See hornc-greedy/netcup GitHub for API access docs.
    netcup = {
      source  = "hornc-greedy/netcup"
      version = "1.0.0"
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



data "sops_file" "netcup" {
  source_file = "${path.module}/secret.yaml"
}

provider "netcup" {
  customer_number   = data.sops_file.netcup.data["netcup_customer_number"]
  api_key           = data.sops_file.netcup.data["netcup_api_key"]
  api_password      = data.sops_file.netcup.data["netcup_api_password"]
  scp_refresh_token = data.sops_file.netcup.data["netcup_scp_refresh_token"]
}

###################################################
#                  Data sources                   #
###################################################

data "netcup_failover_ips" "all" {}

data "netcup_firewall_policies" "all" {}

data "netcup_maintenance" "all" {}

data "netcup_servers" "all" {}

data "netcup_server" "all" {
  for_each = {
    for s in data.netcup_servers.all.servers :
    s.id => s
  }

  id = each.key
}

data "netcup_server_interfaces" "all" {
  for_each = {
    for s in data.netcup_servers.all.servers :
    s.id => s
  }

  server_id = each.key
}

data "netcup_ssh_keys" "all" {}

###################################################
#                    Resources                    #
###################################################

resource "netcup_ssh_key" "user" {
  name = "user_ssh_key"
  key  = trimspace(file("~/.ssh/keys/austin@theblacklodge.org.pub"))
}

resource "netcup_ssh_key" "ansible" {
  name = "ansible_ssh_key"
  key  = trimspace(file("~/.ssh/keys/ansible@theblacklodge.org.pub"))
}

resource "local_file" "json" {
  content = jsonencode({
    paths             = { root : path.root, cwd : path.cwd, module : path.module }
    failover_ips      = [for s in data.netcup_failover_ips.all : s]
    maintenance       = [for s in data.netcup_maintenance.all : s]
    servers           = [for s in data.netcup_servers.all : s]
    server            = [for s in data.netcup_server.all : s]
    server_interfaces = [for s in data.netcup_server_interfaces.all : s]
    ssh_keys          = [for s in data.netcup_ssh_keys.all : s]

    firewall_policy_ids = [for p in data.netcup_firewall_policies.all.policies : p]
  })
  filename = "${path.root}/.generated/${path.module}/outputs.json"
}

#resource "netcup_firewall_policy" "web" {
#  name = "web"
#  rule {
#    action            = "ACCEPT"
#    protocol          = "TCP"
#    direction         = "INGRESS"
#    destination_ports = "443"
#    sources           = ["0.0.0.0/0"]
#  }
#}

#resource "netcup_server_firewall" "srv" {
#  server_id  = 296155
#  mac        = "ba:ad:7a:1f:d3:68"
#  policy_ids = [netcup_firewall_policy.web.id]
#  active     = true
#}

#resource "netcup_server_snapshot" "daily" {
#  server_id   = 296155
#  name        = "daily"
#  description = "Managed by Terraform"
#}
