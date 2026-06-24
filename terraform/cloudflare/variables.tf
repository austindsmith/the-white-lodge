variable "cloudflare_account_id" {
  type      = string
  sensitive = true
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "domain" {
  type = string
}

variable "email_address" {
  type = string
}

variable "authentik_client_id" {
  type      = string
  sensitive = true
}

variable "authentik_client_secret" {
  type      = string
  sensitive = true
}
