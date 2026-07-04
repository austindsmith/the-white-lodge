provider "radarr" {
  url     = local.radarr_url
  api_key = local.radarr_api_key
  extra_headers = [
    {
      name  = "exampleName"
      value = "exanpleValue"
    }
  ]
}

resource "radarr_download_client_qbittorrent" "qbittorrent" {
  enable         = local.qbittorrent_enable
  priority       = local.qbittorrent_priority
  name           = local.qbittorrent_name
  host           = local.qbittorrent_host
  port           = local.qbittorrent_port
  movie_category = "movies"
  first_and_last = local.qbittorrent_first_and_last
  username       = local.qbittorrent_username
  password       = local.qbittorrent_password
}

resource "radarr_download_client_sabnzbd" "sabnzbd" {
  enable         = local.sabnzbd_enable
  priority       = local.sabnzbd_priority
  name           = local.sabnzbd_name
  host           = local.sabnzbd_host
  port           = local.sabnzbd_port
  api_key        = local.sabnzbd_api_key
  movie_category = "movies"

}

resource "radarr_naming" "example" {
  rename_movies              = true
  replace_illegal_characters = true
  colon_replacement_format   = "smart"
  standard_movie_format      = "{Movie Title} ({Release Year})"
  movie_folder_format        = "{Movie Title} ({Release Year})"
}

resource "radarr_root_folder" "radarr" {
  path = "/media/complete/movies"
}


resource "radarr_media_management" "radarr" {
  auto_unmonitor_previously_downloaded_movies = true
  recycle_bin                                 = "/media/tmp/recycle-bin"
  recycle_bin_cleanup_days                    = 7
  download_propers_and_repacks                = "doNotPrefer"
  create_empty_movie_folders                  = false
  delete_empty_folders                        = false
  file_date                                   = "none"
  rescan_after_refresh                        = "afterManual"
  auto_rename_folders                         = true
  paths_default_static                        = false
  set_permissions_linux                       = false
  chmod_folder                                = 755
  chown_group                                 = ""
  skip_free_space_check_when_importing        = false
  minimum_free_space_when_importing           = 1024
  copy_using_hardlinks                        = true
  import_extra_files                          = true
  extra_file_extensions                       = "srt"
  enable_media_info                           = true
}
