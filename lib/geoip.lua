local Table = require('table')
local Buffer = require('buffer').Buffer
local JSON = require('json')
local Utils = require('utils')
local lookup = require('dns').lookup
local Bit = require('bit')
local band = Bit.band
local lshift = Bit.lshift
local rshift = Bit.rshift

-- link libc
local FFI = require('ffi')
FFI.cdef([[
  unsigned long inet_addr(const char *);
]])
local C = FFI.C

local GEOIP,
      GEOIP_CONTINENT_NAMES,
      GEOIP_COUNTRY,
      GEOIP_COUNTRY_BEGIN,
      GEOIP_RECORD_LEN,
      GEOIP_REGION,
      GEOIP_TIMEZONES,
      GEOIP_TYPE,
      buffer,
      getLocation,
      seekCountry,
      seekCountry3,
      seekCountry4

local GEOIP_CONTINENT_NAMES = {
  AF = "Africa",
  AN = "Antarctica",
  AS = "Asia",
  EU = "Europe",
  NA = "North America",
  OC = "Oceania",
  SA = "South America"
}

local GEOIP = require("./country");

local GEOIP_TIMEZONES = require("./timezone");

local GEOIP_COUNTRY = {
}

for id, code in ipairs(GEOIP.code) do
  local rec = {
    id   = code,
    iso2 = code,
    iso3 = GEOIP.code3[id],
    name = GEOIP.name[id],
    cont = GEOIP.continent[id],
    cont_name = GEOIP_CONTINENT_NAMES[GEOIP.continent[id]],
    tz   = {}
  }
  local tz_seen = {}
  for tag, _ in pairs(GEOIP_TIMEZONES) do
    if tag == code or tag:sub(1, 2) == code then
      if not tz_seen[GEOIP_TIMEZONES[tag]] then
        rec.tz[#rec.tz + 1] = GEOIP_TIMEZONES[tag]
        tz_seen[GEOIP_TIMEZONES[tag]] = true
      end
    end
  end
  if #rec.iso3 == 3 then
    GEOIP_COUNTRY[code] = rec
  end
end

--[[require('fs').writeFileSync('geo.json', JSON.stringify(GEOIP_COUNTRY))
require('fs').writeFileSync('geo.lua', Utils.dump(GEOIP_COUNTRY))]]--

GEOIP_REGION = {}
buffer = nil
GEOIP_TYPE = 1
GEOIP_RECORD_LEN = 3
GEOIP_COUNTRY_BEGIN = 16776960

local function seekCountry3(ip32)
  local offset = 0
  local mask = 0x80000000
  for depth = 31, 0, -1 do
    local pos = 6 * offset
    if band(ip32, mask) ~= 0 then
      pos = pos + 3
    end
    offset = buffer[pos]
      + lshift(buffer[pos + 1], 8)
      + lshift(buffer[pos + 2], 16)
    if offset >= GEOIP_COUNTRY_BEGIN then
      return offset - GEOIP_COUNTRY_BEGIN
    end
    mask = rshift(mask, 1)
  end
end

local function seekCountry4(ip32)
  local offset = 0
  local mask = 0x80000000
  for depth = 31, 0, -1 do
    local pos = 8 * offset
    if band(ip32, mask) ~= 0 then
      pos = pos + 4
    end
    offset = buffer[pos]
      + lshift(buffer[pos + 1], 8)
      + lshift(buffer[pos + 2], 16)
      + lshift(buffer[pos + 3], 24)
    if offset >= GEOIP_COUNTRY_BEGIN then
      return offset - GEOIP_COUNTRY_BEGIN
    end
    mask = rshift(mask, 1)
  end
end

local function ipaddr(name_or_ip, callback)
  lookup(name_or_ip, function (err, ip)
    if err then callback(err) ; return end
    local r = C.inet_addr(ip)
    if r == 0xFFFFFFFF then
      callback(true)
    else
      callback(nil, r)
    end
  end)
end

--[[
local function getLocation(name, full)
  local b, code, e, id, ip32, n, offset, p, rc1, rc2, region_code
  ip32 = ipaddr(name)
  id = seekCountry(ip32)
  if not id then
    return
  end
  if GEOIP_TYPE > 1 then
    offset = id + (2 * GEOIP_RECORD_LEN) * GEOIP_COUNTRY_BEGIN
    id = buffer[offset]
  end
  code = GEOIP.code[id]
  if not full then
    return code
  end
  -- FIXME: GEOIP_COUNTRY?
  local record = {
    country_code = code,
    country_code3 = GEOIP.code3[id],
    country_name = GEOIP.name[id],
    continent_code = GEOIP.continent[id],
    continent_name = GEOIP_CONTINENT_NAMES[ GEOIP.continent[id] ]
  }
  if GEOIP_TYPE > 1 then
    b = offset + 1 ; e = b
    while buffer[e] ~= 0 do e = e + 1 end
    record.region_code = buffer.toString('utf8', b, e)
    if full then
      rc1 = buffer[b]
      rc2 = buffer[b + 1]
      if (48 <= rc1 and rc1 < 58) and (48 <= rc2 and rc2 < 58) then
        region_code = (rc1 - 48) * 10 + rc2 - 48
      elseif (65 <= rc1 and rc1 <= 90) or (48 <= rc1 and rc1 < 58) and (65 <= rc2 and rc2 <= 90) or (48 <= rc2 and rc2 < 58) then
        region_code = (rc1 - 48) * (65 + 26 - 48) + rc2 - 48 + 100
      end
      if region_code ~= 0 then
        record.region_name = region_code
      end
      record.tz = GEOIP_TIMEZONES[code .. record.region_code] or GEOIP_TIMEZONES[code]
    end
    e = e + 1 ; b = e
    while buffer[e] ~= 0 do e = e + 1 end
    record.city_name = buffer.toString('utf8', b, e)
    e = e + 1 ; b = e
    while buffer[e] ~= 0 do e = e + 1 end
    record.postal_code = buffer.toString('utf8', b, e)
    b = e + 1
    n = buffer[b] + (buffer[b + 1] << 8) + (buffer[b + 2] << 16)
    b = b + 3
    record.latitude = (n / 10000.0).toFixed(6) - 180
    n = buffer[b] + (buffer[b + 1] << 8) + (buffer[b + 2] << 16)
    b = b + 3
    record.longitude = (n / 10000.0).toFixed(6) - 180
    if GEOIP_TYPE == 2 then
      if record.country_code == 'US' then
        n = buffer[b] + (buffer[b + 1] << 8) + (buffer[b + 2] << 16)
        b = b + 3
        record.dma_code = record.metro_code = Math.floor(n / 1000)
        record.area_code = n % 1000
        n = buffer[b] + (buffer[b + 1] << 8) + (buffer[b + 2] << 16)
      end
    end
  end
  return record
end]]--

--------------------------------------------------------------------------------

local seekCountry = seekCountry3

return function (filename)
  filename = filename or __dirname .. '/../GeoLiteCity.dat'
  buffer = require('fs').readFileSync(filename)
  local buflen = #buffer
  print('DB ' .. filename .. ' loaded (length = ' .. buflen .. ')')
  buffer = Buffer:new(buffer)
  for i = 0, 19 do
    local pos = buflen - i - 3 + 1
    if buffer[pos] == 255
      and buffer[pos + 1] == 255
      and buffer[pos + 2] == 255
    then
      GEOIP_TYPE = buffer[pos + 3]
      if GEOIP_TYPE >= 106 then
        GEOIP_TYPE = GEOIP_TYPE - 105
      end
      if GEOIP_TYPE == 7 then
        GEOIP_COUNTRY_BEGIN = 16700000
      end
      if GEOIP_TYPE == 3 then
        GEOIP_COUNTRY_BEGIN = 16000000
      end
      if GEOIP_TYPE == 2
        or GEOIP_TYPE == 4
        or GEOIP_TYPE == 5
        or GEOIP_TYPE == 6
        or GEOIP_TYPE == 9
      then
        GEOIP_COUNTRY_BEGIN = buffer[pos + 4]
          + lshift(buffer[pos + 5], 8)
          + lshift(buffer[pos + 6], 16)
        if GEOIP_TYPE == 4 or GEOIP_TYPE == 5 then
          GEOIP_RECORD_LEN = 4
          seekCountry = seekCountry4
        end
      end
    end
  end
  return {
    lookupByIP = getLocation,
    countries = GEOIP_COUNTRY,
    ipaddr = ipaddr
  }
end
