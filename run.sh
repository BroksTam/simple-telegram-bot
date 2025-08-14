#!/bin/bash

echo "🚀 جاري تشغيل البوت..."

# إذا ماكو ملف config.json أنشئه واطلب البيانات
if [ ! -f config.json ]; then
    echo "⚠️ لم يتم العثور على ملف الإعدادات (config.json)"
    read -p "ادخل توكن البوت: " TOKEN
    read -p "ادخل ID المطور: " ADMIN_ID
    echo "{
    \"token\": \"$TOKEN\",
    \"admin\": $ADMIN_ID
}" > config.json
    echo "✅ تم إنشاء config.json"
fi

# تشغيل البوت
lua bot.lua
