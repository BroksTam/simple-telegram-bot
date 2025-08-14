local https = require("ssl.https")
local json = require("dkjson")
local config = dofile("config.lua")

if config.bot_token == "" or config.owner_id == "" then
    print("❌ لم يتم إدخال التوكن أو آيدي المطور في config.lua")
    os.exit()
end

local BASE_URL = "https://api.telegram.org/bot" .. config.bot_token

-- دالة إرسال رسالة
local function sendMessage(chat_id, text)
    local url = BASE_URL .. "/sendMessage?chat_id=" .. chat_id .. "&text=" .. text
    https.request(url)
end

-- جلب التحديثات
local offset = 0
while true do
    local resp, code = https.request(BASE_URL .. "/getUpdates?offset=" .. offset)
    if code == 200 and resp then
        local data = json.decode(resp)
        if data and data.result then
            for _, update in ipairs(data.result) do
                offset = update.update_id + 1
                if update.message and update.message.text then
                    local chat_id = update.message.chat.id
                    local text = update.message.text

                    if text == "/start" then
                        sendMessage(chat_id, "👋 أهلاً! البوت شغال 100% ✅")
                    else
                        sendMessage(chat_id, "📩 استلمت رسالتك: " .. text)
                    end
                end
            end
        else
            print("⚠️ لا توجد بيانات من API")
        end
    else
        print("❌ خطأ في الاتصال بـ Telegram API")
        os.execute("sleep 5")
    end
end
