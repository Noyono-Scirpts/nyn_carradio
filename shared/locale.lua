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

--- Vrátí UI stringy pro NUI
---@return table
function GetUiLocales()
    return {
        prefix = Config.ShowNynPrefix and Locale('ui_prefix') or '',
        title = Locale('ui_title'),
        off = Locale('ui_off'),
        stream_error = Locale('ui_stream_error'),
        footer = Locale('ui_footer', Config.Keybind or 'Q'),
        close = Locale('ui_close'),
    }
end
