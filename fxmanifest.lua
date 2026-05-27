fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Poud'
description 'ESX garage system with vehicle shop bridge support'
version '1.0.0'

shared_scripts {
    '@es_extended/imports.lua',
    'config.lua',
    'locales/en.lua',
    'locales/cs.lua',
    'locales/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'es_extended',
    'oxmysql',
    'ox_target'
}
