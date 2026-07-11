terraform {
  backend "local" { path = "../../.tfstate/offsite-backups/terraform.tfstate" }
  required_providers {
    backblaze = {
      source  = "Backblaze/b2"
      version = "0.13.0"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "3.3.1"
    }
  }
}

provider "onepassword" {
}

data "onepassword_item" "backblaze" {
  vault = "the-white-lodge"
  title = "backblaze"
}

provider "b2" {
}

resource "b2_application_key" "example_key" {
  key_name     = "my-key"
  capabilities = ["readFiles"]
}

data "b2_account_info" "b2_account" {
}

resource "b2_bucket" "example_bucket" {
  bucket_name = "my-b2-bucket"
  bucket_type = "allPublic"
}

resource "b2_bucket_notification_rules" "example_notification" {
  bucket_name = "my-b2-bucket"
  bucket_type = "allPublic"
}
