provider "prowlarr" {
  url     = local.prowlarr_url
  api_key = local.prowlarr_api_key
}

resource "prowlarr_download_client_qbittorrent" "qbittorrent" {
  enable   = local.qbittorrent_enable
  priority = local.qbittorrent_priority
  name     = local.qbittorrent_name
  host     = local.qbittorrent_url
  port     = local.qbittorrent_port
  username = local.qbittorrent_username
  password = local.qbittorrent_password
}

resource "prowlarr_download_client_sabnzbd" "sabnzbd" {
  enable   = local.sabnzbd_enable
  priority = local.sabnzbd_priority
  name     = local.sabnzbd_name
  host     = local.sabnzbd_host
  port     = local.sabnzbd_port
  api_key  = local.sabnzbd_api_key
}


resource "prowlarr_application_radarr" "radarr" {
  name         = "Radarr"
  sync_level   = "fullSync"
  base_url     = local.radarr_host
  prowlarr_url = local.prowlarr_host
  api_key      = local.radarr_api_key
  #sync_categories = [2000, 2010, 2030, 2040, 2045]
}

resource "prowlarr_application_sonarr" "sonarr" {
  name         = "Sonarr"
  sync_level   = "fullSync"
  base_url     = local.sonarr_host
  prowlarr_url = local.prowlarr_host
  api_key      = local.sonarr_api_key
  #sync_categories       = [5000, 5010, 5030, 5040, 5045]
  #anime_sync_categories = [5070]
}

resource "prowlarr_sync_profile" "primary" {
  name                      = "Primary"
  minimum_seeders           = 1
  enable_rss                = true
  enable_automatic_search   = true
  enable_interactive_search = true
}

#resource "prowlarr_indexer" "example" {
#  enable          = true
#  name            = "HDBits"
#  implementation  = "HDBits"
#  config_contract = "HDBitsSettings"
#  protocol        = "torrent"
#  app_profile_id  = 1
#  priority        = 1
#  tags            = [1, 2, 5]
#
#  fields = [
#    {
#      name       = "username"
#      text_value = "test"
#    },
#    {
#      name       = "apiKey"
#      text_value = "test"
#    },
#    {
#      name      = "codecs"
#      set_value = [1, 5]
#    },
#    {
#      name      = "mediums"
#      set_value = [1, 3]
#    },
#    {
#      name         = "torrentBaseSettings.seedRatio"
#      number_value = 0.5
#    },
#    {
#      name         = "torrentBaseSettings.seedTime"
#      number_value = 5
#    },
#  ]
#}
