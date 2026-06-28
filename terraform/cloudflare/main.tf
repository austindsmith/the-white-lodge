terraform {
  backend "local" { path = "../../.tfstate/cloudflare/terraform.tfstate" }
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.21.1"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.1"
    }
  }
}

provider "onepassword" {
  account = "my.1password.com"
}

data "onepassword_item" "cloudflare" {
  vault = "the-white-lodge"
  title = "cloudflare"
}

data "onepassword_item" "netcup" {
  vault = "the-white-lodge"
  title = "netcup"
}

locals {
  cf_api_token  = data.onepassword_item.cloudflare.field["api_token"]
  cf_account_id = data.onepassword_item.cloudflare.field["account_id"]
  domain        = data.onepassword_item.netcup.field["domain"]
  email_address = data.onepassword_item.cloudflare.field["username"]
}

provider "cloudflare" {
  api_token = local.cf_api_token
}

resource "cloudflare_zero_trust_access_policy" "example_zero_trust_access_policy" {
  account_id = local.cf_account_id
  decision   = "allow"
  name       = "Email verification"
  include = [{
    email = {
      email = "${local.email_address}"
    }
  }]
  session_duration = "24h"
}

resource "cloudflare_zero_trust_access_application" "wildcard" {
  account_id                 = local.cf_account_id
  allowed_idps               = []
  app_launcher_visible       = true
  auto_redirect_to_identity  = false
  domain                     = "*.${local.domain}"
  enable_binding_cookie      = false
  http_only_cookie_attribute = false
  name                       = "*"
  options_preflight_bypass   = false
  session_duration           = "24h"
  tags                       = []
  type                       = "self_hosted"
  destinations = [{
    type = "public"
    uri  = "*.${local.domain}"
  }]
  policies = [{
    id         = cloudflare_zero_trust_access_policy.example_zero_trust_access_policy.id
    precedence = 1
  }]
}

locals {
  passthrough_apps = toset([
    "authentik",
    "rd-id",
    "rd-relay",
    "rustdesk",
    "teleport",
  ])
}

resource "cloudflare_zero_trust_access_application" "passthrough" {
  for_each = local.passthrough_apps

  account_id       = local.cf_account_id
  name             = "${title(each.key)} passthrough"
  domain           = "${each.key}.${local.domain}"
  session_duration = "24h"
  type             = "self_hosted"

  destinations = [{
    type = "public"
    uri  = "${each.key}.${local.domain}"
  }]

  policies = [{
    decision   = "bypass"
    name       = "Passthrough"
    include    = [{ everyone = {} }]
    precedence = 1
    require    = []
    reusable   = true
  }]
}

resource "cloudflare_zero_trust_access_application" "authentik_admin_console" {
  account_id                = local.cf_account_id
  app_launcher_visible      = false
  auto_redirect_to_identity = false
  name                      = "Authentik admin console"
  session_duration          = "24h"
  type                      = "self_hosted"
  domain                    = "authentik.${local.domain}/if/admin/*"

  destinations = [{
    type = "public"
    uri  = "authentik.${local.domain}/if/admin/*"
  }]

  policies = [{
    id         = cloudflare_zero_trust_access_policy.example_zero_trust_access_policy.id
    precedence = 1
  }]
}
