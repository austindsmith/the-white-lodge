provider "sonarr" {
  url     = local.sonarr_url
  api_key = local.sonarr_api_key
}

resource "sonarr_download_client_qbittorrent" "qbittorrent" {
  enable         = local.qbittorrent_enable
  priority       = local.qbittorrent_priority
  name           = local.qbittorrent_name
  host           = local.qbittorrent_host
  port           = local.qbittorrent_port
  tv_category    = "tv"
  first_and_last = local.qbittorrent_first_and_last
  username       = local.qbittorrent_username
  password       = local.qbittorrent_password
}

resource "sonarr_download_client_sabnzbd" "sabnzbd" {
  enable      = local.sabnzbd_enable
  priority    = local.sabnzbd_priority
  name        = local.sabnzbd_name
  host        = local.sabnzbd_host
  port        = local.sabnzbd_port
  api_key     = local.sabnzbd_api_key
  tv_category = "tv"

}

resource "sonarr_naming" "example" {
  rename_episodes            = true
  replace_illegal_characters = true
  multi_episode_style        = 5
  colon_replacement_format   = 4
  daily_episode_format       = "{Series Title} - {Air-Date} - {Episode Title} {Quality Full}"
  anime_episode_format       = "{Series Title} - S{season:00}E{episode:00} - {Episode Title} {Quality Full}"
  series_folder_format       = "{Series Title}"
  season_folder_format       = "Season {season}"
  specials_folder_format     = "Specials"
  standard_episode_format    = "{Series Title} - S{season:00}E{episode:00} - {Episode Title} {Quality Full}"
}

resource "sonarr_root_folder" "sonarr" {
  path = "/media/complete/tv"
}

resource "sonarr_media_management" "sonarr" {
  unmonitor_previous_episodes = true
  hardlinks_copy              = true
  create_empty_folders        = false
  delete_empty_folders        = false
  enable_media_info           = true
  import_extra_files          = true
  set_permissions             = false
  skip_free_space_check       = false
  minimum_free_space          = 1024
  recycle_bin_days            = 7
  chmod_folder                = "755"
  chown_group                 = ""
  download_propers_repacks    = "preferAndUpgrade"
  episode_title_required      = "always"
  extra_file_extensions       = "srt,info"
  file_date                   = "none"
  recycle_bin_path            = "/media/tmp/recycle-bin"
  rescan_after_refresh        = "always"
}
