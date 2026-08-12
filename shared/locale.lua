Locales = Locales or {}

function Locale(key, ...)
    local lang = Config and Config.Locale or 'en'
    local pack = Locales[lang] or Locales['en'] or {}
    local str = pack[key] or (Locales['en'] and Locales['en'][key]) or key

    if select('#', ...) > 0 then
        return string.format(str, ...)
    end

    return str
end

---@return table
function GetUiLocales()
    return {
        prefix = Config.ShowNynPrefix and Locale('ui_prefix') or '',
        title = Locale('ui_title'),
        off = Locale('ui_off'),
        stream_error = Locale('ui_stream_error'),
        footer = Locale('ui_footer', Config.Keybind or 'Q'),
        close = Locale('ui_close'),

        plus_tab_stations = Locale('plus_tab_stations'),
        plus_tab_playlists = Locale('plus_tab_playlists'),
        plus_tab_now = Locale('plus_tab_now'),
        plus_tab_search = Locale('plus_tab_search'),
        plus_status_paused = Locale('plus_status_paused'),
        plus_status_playing = Locale('plus_status_playing'),
        plus_status_idle = Locale('plus_status_idle'),
        plus_missing_title = Locale('plus_missing_title'),
        plus_missing_body = Locale('plus_missing_body'),
        plus_no_stations_title = Locale('plus_no_stations_title'),
        plus_no_stations_body = Locale('plus_no_stations_body'),
        plus_station = Locale('plus_station'),
        plus_live_stream = Locale('plus_live_stream'),
        plus_back = Locale('plus_back'),
        plus_tracks_count = Locale('plus_tracks_count'),
        plus_play = Locale('plus_play'),
        plus_remove = Locale('plus_remove'),
        plus_no_tracks = Locale('plus_no_tracks'),
        plus_add = Locale('plus_add'),
        plus_playlist_name_ph = Locale('plus_playlist_name_ph'),
        plus_new = Locale('plus_new'),
        plus_playlists_count = Locale('plus_playlists_count'),
        plus_tracks_n = Locale('plus_tracks_n'),
        plus_open = Locale('plus_open'),
        plus_delete = Locale('plus_delete'),
        plus_rename = Locale('plus_rename'),
        plus_duplicate = Locale('plus_duplicate'),
        plus_save = Locale('plus_save'),
        plus_cancel = Locale('plus_cancel'),
        plus_renamed = Locale('plus_renamed'),
        plus_duplicated = Locale('plus_duplicated'),
        plus_copy_suffix = Locale('plus_copy_suffix'),
        plus_no_playlists = Locale('plus_no_playlists'),
        plus_nothing = Locale('plus_nothing'),
        plus_pick_hint = Locale('plus_pick_hint'),
        plus_volume = Locale('plus_volume'),
        plus_resume = Locale('plus_resume'),
        plus_pause = Locale('plus_pause'),
        plus_stop = Locale('plus_stop'),
        plus_skip = Locale('plus_skip'),
        plus_queue = Locale('plus_queue'),
        plus_queued = Locale('plus_queued'),
        plus_queue_hint = Locale('plus_queue_hint'),
        plus_queue_now = Locale('plus_queue_now'),
        plus_queue_next = Locale('plus_queue_next'),
        plus_queue_empty = Locale('plus_queue_empty'),
        plus_url_ph = Locale('plus_url_ph'),
        plus_need_url = Locale('plus_need_url'),
        plus_playing = Locale('plus_playing'),
        plus_err_limit_playlists = Locale('plus_err_limit_playlists'),
        plus_err_limit_tracks = Locale('plus_err_limit_tracks'),
        plus_err_invalid_url = Locale('plus_err_invalid_url'),
        plus_err_empty = Locale('plus_err_empty'),
        plus_err_no_db = Locale('plus_err_no_db'),
        plus_err_forbidden = Locale('plus_err_forbidden'),
        plus_err_disabled = Locale('plus_err_disabled'),
        plus_err_timeout = Locale('plus_err_timeout'),
        plus_err_not_in_vehicle = Locale('plus_err_not_in_vehicle'),
        plus_err_missing_extension = Locale('plus_err_missing_extension'),
        plus_err_load_failed = Locale('plus_err_load_failed'),
        plus_err_play_failed = Locale('plus_err_play_failed'),
        plus_err_failed = Locale('plus_err_failed'),
        plus_err_no_xsound = Locale('plus_err_no_xsound'),
        plus_err_no_carradio = Locale('plus_err_no_carradio'),
        plus_err_play_video = Locale('plus_err_play_video'),
        plus_add_to_playlist = Locale('plus_add_to_playlist'),
        plus_pick_playlist = Locale('plus_pick_playlist'),
        plus_saved_to_playlist = Locale('plus_saved_to_playlist'),
        plus_streams_no_playlist = Locale('plus_streams_no_playlist'),
        plus_create_playlist_first = Locale('plus_create_playlist_first'),
    }
end
