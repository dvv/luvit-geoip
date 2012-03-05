#!/usr/bin/env luvit

local Geo = require('geoip')()
-- Russian Federation info
p(Geo.countries.RU)
--Geo.byIP('79.171.11.94', print)
Geo.ipaddr('79.171.11.94', function (err, ip32) print('1', ip32) end)
Geo.ipaddr('ya.ru', function (err, ip32) print('2', ip32) end)
