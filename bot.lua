-- Simple Telegram Bot in Lua
local config = require("config")
local https = require("ssl.https")
local json = require("dkjson")

local TOKEN = config.bot_token
local SUDO = config.sudo_users[1]

local function request(method, data)
  local url = "https://api.telegram.org/bot" .. TOKEN .. "/" .. method
  if data then url = url .. "?" .. data end
  local res, code = https.request(url)
  if not res then return {} end
  return json.decode(res)
end

local offset = 0
while true do
  local resp = request("getUpdates", "timeout=30&offset=" .. offset)
  for _, upd in ipairs(resp.result or {}) do
    offset = upd.update_id + 1
    local msg = upd.message
    local chat_id = msg.chat.id
    local text = msg.text or ""

    if text == "/start" then
      request("sendMessage", "chat_id="..chat_id.."&text=Welcome!")
    elseif text == "/id" then
      request("sendMessage", "chat_id="..chat_id.."&text=Your ID: "..msg.from.id)
    end
  end
end
