local https = require("ssl.https")
local json = require("dkjson")

-- قراءة الإعدادات
local config_file = io.open("config.json", "r")
if not config_file then
    print("❌ لم يتم العثور على config.json — شغل run.sh أولاً")
    os.exit()
end
local config_content = config_file:read("*a")
config_file:close()
local config = json.decode(config_content)

local BOT_TOKEN = config.token
local SUDO_ID = tonumber(config.sudo_id)
local PROXY = config.proxy ~= "" and config.proxy or nil

-- إعدادات الاتصال مع البروكسي
local function make_request(url)
    local request = require("socket.http")
    if PROXY then
        request.PROXY = PROXY
    end
    return request.request(url)
end

-- جلب تحديثات البوت
local last_update_id = 0
while true do
    local url = string.format("https://api.telegram.org/bot%s/getUpdates?offset=%d", BOT_TOKEN, last_update_id + 1)
    local res, code = https.request(url)
    if code == 200 and res then
        local updates = json.decode(res)
        if updates and updates.result then
            for _, update in ipairs(updates.result) do
                last_update_id = update.update_id
                if update.message and update.message.text then
                    local chat_id = update.message.chat.id
                    local text = update.message.text

                    if text == "/start" then
                        local send_url = string.format("https://api.telegram.org/bot%s/sendMessage?chat_id=%d&text=🚀 البوت شغال!", BOT_TOKEN, chat_id)
                        https.request(send_url)
                    elseif chat_id == SUDO_ID then
                        local send_url = string.format("https://api.telegram.org/bot%s/sendMessage?chat_id=%d&text=📩 رسالتك: %s", BOT_TOKEN, chat_id, text)
                        https.request(send_url)
                    end
                end
            end
        end
    else
        print("⚠️ خطأ في الاتصال، إعادة المحاولة بعد 5 ثواني...")
        os.execute("sleep 5")
    end
end
