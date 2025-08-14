#!/bin/bash
# Simple installer and runner
echo -n "Bot Token: "
read TOKEN
echo -n "Your ID: "
read SUDO
cat <<EOF > config.lua
return {
  bot_token = "$TOKEN",
  sudo_users = {$SUDO},
}
EOF

echo "Installing dependencies..."
apt update -y && apt install -y lua5.3 lua-socket lua-sec lua-dkjson

echo "Starting bot..."
lua5.3 bot.lua
