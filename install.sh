#!/bin/bash
sudo apt update && sudo apt upgrade -y
sudo apt install lua5.3 luarocks git curl unzip -y
sudo luarocks install luasocket
sudo luarocks install luasec
sudo luarocks install dkjson

lua run.lua
