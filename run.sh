#!/bin/bash

echo "🚀 جاري تشغيل البوت..."

# التحقق من وجود التوكن و ID المطور
if [ ! -f config.lua ]; then
    echo "⚠️ لم يتم العثور على ملف الإعدادات (config.lua)"
    echo "يرجى إدخال المعلومات التالية:"
    read -p "ادخل توكن البوت: " TOKEN
    read -p "ادخل ID المطور: " SUDO
    echo "return { token = \"$TOKEN\", sudo = $SUDO }" > config.lua
fi

# تشغيل البوت
lua bot.lua
