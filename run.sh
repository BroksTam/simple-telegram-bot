while true do
    local ok, err = pcall(function()
        dofile("bot.lua")
    end)

    if not ok then
        print("\27[31m❌ خطأ في تشغيل البوت: " .. tostring(err) .. "\27[0m")
        print("\27[33m⏳ إعادة التشغيل بعد 5 ثواني...\27[0m")
        os.execute("sleep 5")
    end
end
