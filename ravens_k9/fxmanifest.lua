fx_version 'cerulean'
game 'gta5'

name        "Raven's K9 System"
author      'Raven'
description 'Advanced player K9 system — certifications, detection, tracking, ox_target integration'
version     '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/rk9_config.lua',
    'shared/rk9_cert_utils.lua',
}

client_scripts {
    'client/rk9_cl_core.lua',
    'client/rk9_cl_menus.lua',
    'client/rk9_cl_detection.lua',
    'client/rk9_cl_target.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/rk9_sv_core.lua',
    'server/rk9_sv_certs.lua',
    'server/rk9_sv_admin.lua',
}

dependencies {
    'ox_lib',
    'ox_target',
    'oxmysql',
    'qb-core',
}
