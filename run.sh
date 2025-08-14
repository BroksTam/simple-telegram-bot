#!/bin/bash

echo "🛠️ إعداد البوت..."
read -p "ادخل التوكن: " token
read -p "ادخل آيدي المطور: " owner

cat > config.lua <<EOL
return {
    bot_token = "$token",
    owner_id = "$owner"
}
EOL

echo "✅ تم حفظ البيانات في config.lua"
echo "🚀 تشغيل البوت..."
lua bot.lua
