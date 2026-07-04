terraform {
  backend "local" { path = "../../.tfstate/media/terraform.tfstate" }
  required_providers {
    prowlarr = {
      source  = "devopsarr/prowlarr"
      version = "3.2.1"
    }
    radarr = {
      source  = "devopsarr/radarr"
      version = "2.4.0"
    }
    sonarr = {
      source  = "devopsarr/sonarr"
      version = "3.4.2"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "3.3.1"
    }
  }
}

provider "onepassword" {
  account = "my.1password.com"
}

data "onepassword_item" "prowlarr" {
  vault = "the-white-lodge"
  title = "prowlarr"
}
data "onepassword_item" "qbittorrent" {
  vault = "the-white-lodge"
  title = "qbittorrent"
}
data "onepassword_item" "radarr" {
  vault = "the-white-lodge"
  title = "radarr"
}
data "onepassword_item" "sabnzbd" {
  vault = "the-white-lodge"
  title = "sabnzbd"
}
data "onepassword_item" "sonarr" {
  vault = "the-white-lodge"
  title = "sonarr"
}

locals {
  prowlarr    = data.onepassword_item.prowlarr.section_map[""].field_map
  qbittorrent = data.onepassword_item.qbittorrent.section_map[""].field_map
  radarr      = data.onepassword_item.radarr.section_map[""].field_map
  sabnzbd     = data.onepassword_item.sabnzbd.section_map[""].field_map
  sonarr      = data.onepassword_item.sonarr.section_map[""].field_map

  prowlarr_api_key = local.prowlarr["PROWLARR_API_KEY"].value
  prowlarr_url     = local.prowlarr["PROWLARR_URL"].value
  prowlarr_host    = local.prowlarr["PROWLARR_HOST"].value

  qbittorrent_api_key        = local.qbittorrent["api_key"].value
  qbittorrent_url            = local.qbittorrent["url"].value
  qbittorrent_enable         = true
  qbittorrent_priority       = 1
  qbittorrent_name           = "qbittorrent"
  qbittorrent_host           = local.qbittorrent["url"].value
  qbittorrent_port           = 8080
  qbittorrent_first_and_last = true
  qbittorrent_username       = data.onepassword_item.qbittorrent.username
  qbittorrent_password       = data.onepassword_item.qbittorrent.password

  radarr_api_key = local.radarr["RADARR_API_KEY"].value
  radarr_url     = local.radarr["RADARR_URL"].value
  radarr_host    = local.radarr["RADARR_HOST"].value

  sabnzbd_enable         = true
  sabnzbd_priority       = 1
  sabnzbd_name           = "sabnzbd"
  sabnzbd_host           = local.sabnzbd["url"].value
  sabnzbd_port           = 8080
  sabnzbd_api_key        = local.sabnzbd["api_key"].value
  sabnzbd_first_and_last = true

  sonarr_api_key = local.sonarr["api_key"].value
  sonarr_url     = local.sonarr["url"].value
  sonarr_host    = local.sonarr["host"].value

}

#resource "prowlarr_notification_ntfy" "example" {
#  on_health_issue       = false
#  on_application_update = false
#
#  include_health_warnings = false
#  name                    = "Example"
#
#  priority   = 1
#  server_url = "https://ntfy.sh"
#  username   = "User"
#  password   = "Pass"
#  topics     = ["Topic1234", "Topic4321"].value
#  field_tags = ["warning", "skull"].value
#}
