fx_version 'cerulean'
game 'gta5'

author 'FiveM Banking Script'
description 'Simple standalone banking system with cash and bank balances'
version '1.0.0'

lua54 'yes'

server_scripts {
    'server/main.lua'
}

client_scripts {
    'client/main.lua'
}

ui_page 'html/index.html'

files {
    'data/accounts.json',
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

escrow_ignore {
    'data/accounts.json'
}
