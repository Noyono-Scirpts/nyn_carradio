Config = {}

-- Locale pack: 'en' | 'cs' (see locales/)
Config.Locale = 'en'
Config.Debug = false

-- Show "NYN" prefix in the NUI brand
Config.ShowNynPrefix = true

-- Enable Car Radio+ UI bridge (command/keybind live in nyn_carradio_plus)
Config.EnableExtension = true

-- Remappable in FiveM Settings → Key Bindings → FiveM
Config.Keybind = 'Q'

-- Disable in emergency vehicles (class 18)
Config.DisableInEmergency = true

-- true = any seat; false = driver + front passenger only (separate from Plus)
Config.AllowRearSeatControl = true

Config.NotifyOnBlocked = true

-- 'nyn_lib' | 'ox_lib'
Config.Notify = 'nyn_lib'

-- Station types: "off" | "native" | "stream" (URL via HTML Audio)
Config.Stations = {
    {
        name = "Radio Off",
        type = "off",
        value = nil,
        image = "OFF.png",
        icon = "OFF"
    },
    {
        name = "Los Santos Rock Radio",
        type = "native",
        value = "RADIO_01_CLASS_ROCK",
        image = "RADIO_01_CLASS_ROCK.png",
        icon = "ROCK"
    },
    {
        name = "Non-Stop-Pop FM",
        type = "native",
        value = "RADIO_02_POP",
        image = "RADIO_02_POP.png",
        icon = "POP"
    },
    {
        name = "Radio Los Santos",
        type = "native",
        value = "RADIO_03_HIPHOP_NEW",
        image = "RADIO_03_HIPHOP_NEW.png",
        icon = "RLS"
    },
    {
        name = "Channel X",
        type = "native",
        value = "RADIO_04_PUNK",
        image = "RADIO_04_PUNK.png",
        icon = "CHNX"
    },
    {
        name = "West Coast Talk Radio",
        type = "native",
        value = "RADIO_05_TALK_01",
        image = "RADIO_05_TALK_01.png",
        icon = "WCTR"
    },
    {
        name = "Rebel Radio",
        type = "native",
        value = "RADIO_06_COUNTRY",
        image = "RADIO_06_COUNTRY.png",
        icon = "REBEL"
    },
    {
        name = "Soulwax FM",
        type = "native",
        value = "RADIO_07_DANCE_01",
        image = "RADIO_07_DANCE_01.png",
        icon = "SOUL"
    },
    {
        name = "East Los FM",
        type = "native",
        value = "RADIO_08_MEXICAN",
        image = "RADIO_08_MEXICAN.png",
        icon = "ELOS"
    },
    {
        name = "West Coast Classics",
        type = "native",
        value = "RADIO_09_HIPHOP_OLD",
        image = "RADIO_09_HIPHOP_OLD.png",
        icon = "WCC"
    },
    {
        name = "Blaine County Talk Radio",
        type = "native",
        value = "RADIO_11_TALK_02",
        image = "RADIO_11_TALK_02.png",
        icon = "BCR"
    },
    {
        name = "Blue Ark",
        type = "native",
        value = "RADIO_12_REGGAE",
        image = "RADIO_12_REGGAE.png",
        icon = "ARK"
    },
    {
        name = "Worldwide FM",
        type = "native",
        value = "RADIO_13_JAZZ",
        image = "RADIO_13_JAZZ.png",
        icon = "WWFM"
    },
    {
        name = "FlyLo FM",
        type = "native",
        value = "RADIO_14_DANCE_02",
        image = "RADIO_14_DANCE_02.png",
        icon = "FLYLO"
    },
    {
        name = "The Lowdown 91.1",
        type = "native",
        value = "RADIO_15_MOTOWN",
        image = "RADIO_15_MOTOWN.png",
        icon = "LOW"
    },
    {
        name = "Radio Mirror Park",
        type = "native",
        value = "RADIO_16_SILVERLAKE",
        image = "RADIO_16_SILVERLAKE.png",
        icon = "RMP"
    },
    {
        name = "Space 103.2",
        type = "native",
        value = "RADIO_17_FUNK",
        image = "RADIO_17_FUNK.png",
        icon = "SPACE"
    },
    {
        name = "Vinewood Boulevard Radio",
        type = "native",
        value = "RADIO_18_90S_ROCK",
        image = "RADIO_18_90S_ROCK.png",
        icon = "VBR"
    },
    {
        name = "The Lab",
        type = "native",
        value = "RADIO_20_THELAB",
        image = "RADIO_20_THELAB.png",
        icon = "LAB"
    },
    {
        name = "Blonded Los Santos 97.8 FM",
        type = "native",
        value = "RADIO_21_DLC_XM17",
        image = "RADIO_21_DLC_XM17.png",
        icon = "BLND"
    },
    {
        name = "Los Santos Underground Radio",
        type = "native",
        value = "RADIO_22_DLC_BATTLE_MIX1_RADIO",
        image = "RADIO_22_DLC_BATTLE_MIX1_RADIO.png",
        icon = "LSUR"
    },
}