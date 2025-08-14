local https = require("ssl.https")
local json = require("dkjson")

-- تحميل التوكن و ID المطور من ملف config.json
local configFile = io.open("config.json", "r")
if not configFile then
    print("❌ ملف config.json غير موجود!")
    os.exit()
end
local config = json.decode(configFile:read("*a"))
configFile:close()

local BOT_TOKEN = config.token
local ADMIN_ID = tostring(config.admin_id)

local BASE_URL = "https://api.telegram.org/bot" .. BOT_TOKEN

-- دالة إرسال رسالة
local function sendMessage(chat_id, text)
    local url = BASE_URL .. "/sendMessage?chat_id=" .. chat_id .. "&text=" .. text
    https.request(url)
end

print("✅ البوت يعمل الآن ...")

while true do
    local updates, code = https.request(BASE_URL .. "/getUpdates?timeout=10")
    if code == 200 and updates then
        local data = json.decode(updates)
        if data and data.result then
            for _, update in ipairs(data.result) do
                if update.message and update.message.text then
                    local text = update.message.text
                    local chat_id = tostring(update.message.chat.id)

                    if text == "/start" then
                        sendMessage(chat_id, "👋 أهلاً بك! البوت يعمل بنجاح ✅")
                    elseif chat_id == ADMIN_ID then
                        sendMessage(chat_id, "📩 تم استلام رسالتك: " .. text)
                    end
                end
            end
        end
    else
        print("⚠️ مشكلة في الاتصال بتليجرام...")
    end
end
