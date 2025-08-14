#!/bin/bash

# فحص وجود ملف config.json
if [ ! -f config.json ]; then
    echo "🚀 أول تشغيل — راح نطلب منك الإعدادات."
    read -p "ادخل التوكن: " TOKEN
    read -p "ادخل ID المطور: " SUDO
    read -p "ادخل رابط بروكسي (SOCKS5 أو HTTP — اتركه فارغ إذا ما تريد): " PROXY

    echo "{
        \"token\": \"$TOKEN\",
        \"sudo_id\": \"$SUDO\",
        \"proxy\": \"$PROXY\"
    }" > config.json
    echo "✅ تم حفظ الإعدادات في config.json"
fi

# تشغيل البوت
while true; do
    lua5.3 bot.lua
    echo "⚠️ البوت توقف — إعادة التشغيل خلال 5 ثواني..."
    sleep 5
done
