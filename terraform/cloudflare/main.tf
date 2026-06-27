terraform {
  # Utilizes .envrc to pull from encrypted secret.yaml.
  backend "local" { path = "../../.tfstate/cloudflare/terraform.tfstate" }
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.21.1"
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

data "sops_file" "cloudflare" {
  source_file = "${path.module}/secret.yaml"
}

provider "cloudflare" {
  api_token = data.sops_file.cloudflare.data["cloudflare_api_token"]
}

resource "cloudflare_zero_trust_access_policy" "example_zero_trust_access_policy" {
  account_id = data.sops_file.cloudflare.data["cloudflare_account_id"]
  decision   = "allow"
  name       = "Email verification"
  include = [{
    email = {
      email = "${data.sops_file.cloudflare.data["email_address"]}"
    }
  }]
  session_duration = "24h"
}

resource "cloudflare_zero_trust_access_application" "wildcard" {
  account_id                 = data.sops_file.cloudflare.data["cloudflare_account_id"]
  allowed_idps               = []
  app_launcher_visible       = true
  auto_redirect_to_identity  = false
  domain                     = "*.${data.sops_file.cloudflare.data["domain"]}"
  enable_binding_cookie      = false
  http_only_cookie_attribute = false
  name                       = "*"
  options_preflight_bypass   = false
  session_duration           = "24h"
  tags                       = []
  type                       = "self_hosted"
  destinations = [{
    type = "public"
    uri  = "*.${data.sops_file.cloudflare.data["domain"]}"
  }]
  policies = [{
    id         = cloudflare_zero_trust_access_policy.example_zero_trust_access_policy.id
    precedence = 1
  }]
}
