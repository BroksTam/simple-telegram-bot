local https = require("ssl.https")
local json = require("dkjson")

-- تحميل الإعدادات إذا موجودة
local config_file = "config.lua"
local config = {}

local function save_config()
    local file = io.open(config_file, "w")
    file:write("return {\n")
    file:write(string.format("  token = '%s',\n", config.token))
    file:write(string.format("  owner_id = %d\n", config.owner_id))
    file:write("}\n")
    file:close()
end

local function load_config()
    local file = io.open(config_file, "r")
    if file then
        config = dofile(config_file)
        file:close()
        return true
    end
    return false
end

-- إذا ماكو إعدادات، يطلبها من المستخدم
if not load_config() then
    io.write("ادخل توكن البوت: ")
    config.token = io.read()
    io.write("ادخل آيدي المطور: ")
    config.owner_id = tonumber(io.read())
    save_config()
    print("✅ تم حفظ الإعدادات في config.lua")
end

-- فحص التوكن
print("🚀 جارٍ تشغيل البوت...")
local api_url = "https://api.telegram.org/bot" .. config.token

local function getMe()
    local res, code = https.request(api_url .. "/getMe")
    if code ~= 200 then
        print("❌ خطأ في الاتصال بـ Telegram API. كود الحالة: " .. tostring(code))
        os.exit()
    end
    local data = json.decode(res)
    if not data.ok then
        print("❌ التوكن غير صحيح أو البوت معطل.")
        os.exit()
    end
    print("✅ البوت يعمل الآن. الاسم: @" .. data.result.username)
end

getMe()

-- جلب التحديثات
local offset = 0
while true do
    local res, code = https.request(api_url .. "/getUpdates?timeout=30&offset=" .. offset)
    if code ~= 200 then
        print("⚠️ خطأ في جلب التحديثات. كود الحالة: " .. tostring(code))
    else
        local data = json.decode(res)
        if data and data.ok then
            for _, update in ipairs(data.result) do
                offset = update.update_id + 1
                if update.message then
                    local chat_id = update.message.chat.id
                    local text = update.message.text or ""
                    local from = update.message.from.first_name or "مجهول"
                    print("📩 رسالة من " .. from .. ": " .. text)

                    if text == "/start" then
                        -- رد الفحص
                        local reply = { chat_id = chat_id, text = "✅ البوت شغال وجاهز للعمل" }
                        local body = json.encode(reply)
                        https.request(api_url .. "/sendMessage", body)
                    else
                        -- رد تلقائي على أي رسالة ثانية
                        local reply = { chat_id = chat_id, text = "📬 استلمت رسالتك: " .. text }
                        local body = json.encode(reply)
                        https.request(api_url .. "/sendMessage", body)
                    end
                end
            end
        end
    end
end
