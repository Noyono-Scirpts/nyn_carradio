fx_version 'cerulean'
game 'gta5'

author 'nc_carradio'
description 'nc_carradio - Advanced vehicle radio selector UI with multiplayer synchronization'
version '1.0.0'

ui_page 'ui/index.html'

shared_script 'config.lua'

client_script 'client.lua'

server_script 'server.lua'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/script.js',
    'ui/images/*.png'
}
