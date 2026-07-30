fx_version 'cerulean'
game 'gta5'

author 'Noyono'
description 'NYN Car Radio - vehicle radio selector with multiplayer sync'
version '1.0.0'

ui_page 'ui/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    '@nyn_lib/init.lua',
    'shared/*.lua',
    'locales/*.lua',
}

client_scripts {
    'client/*.lua',
}

server_scripts {
    'server/*.lua',
}

files {
    'ui/index.html',
    'ui/style.css',
    'ui/script.js',
    'ui/images/*.png',
}

dependencies {
    'nyn_lib',
    'ox_lib',
}

--[[
  Escrow (Cfx.re Keymaster):
  - PROTECTED: client/, server/, shared locale helper, ui code
  - OPEN (editable): config, locales, fxmanifest, README
]]
escrow_ignore {
    'fxmanifest.lua',
    'shared/config.lua',
    'locales/**/*',
    'README.md',
}

lua54 'yes'
