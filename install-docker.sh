#!/bin/bash

# ===============================
# 🐳 Docker & Docker Compose Installer
# Versi: 1.2
# ===============================
# Author: ChatGPT & Kamu 😎
# Untuk: Setup Docker di VPS atau WSL/Linux
# ===============================

set -e
clear

echo "=============================="
echo "🔧 Memulai proses installasi Docker..."
echo "=============================="
sleep 1

# 🔍 Cek apakah Docker sudah terinstall
if command -v docker &> /dev/null; then
  echo "✅ Docker sudah terinstall: $(docker --version)"
else
  echo "📦 Melakukan update paket sistem..."
  sudo apt update -y
  sudo apt upgrade -y

  echo "🧰 Menginstall dependensi pendukung..."
  sudo apt install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      software-properties-common \
      lsb-release \
      gnupg

  echo "🔐 Menambahkan GPG key Docker..."
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

  echo "➕ Menambahkan repository Docker..."
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  echo "🔄 Memperbarui kembali daftar paket..."
  sudo apt update -y

  echo "🐳 Menginstall Docker Engine..."
  sudo apt install -y docker-ce docker-ce-cli containerd.io

  echo "🚀 Menjalankan Docker daemon..."
  sudo systemctl enable docker
  sudo systemctl start docker

  echo "✅ Docker berhasil terinstall: $(docker --version)"
fi

# ===============================
# 🔍 Mengecek Docker Compose
# ===============================

echo ""
echo "🔍 Mengecek Docker Compose..."

if command -v docker-compose &> /dev/null; then
  echo "✅ Docker Compose (legacy) ditemukan: $(docker-compose --version)"
elif docker compose version &> /dev/null; then
  echo "✅ Docker Compose (modern) ditemukan: $(docker compose version)"
else
  echo "⚠️  Docker Compose tidak ditemukan."

  if grep -qi microsoft /proc/version; then
    echo "💡 Deteksi WSL: Kamu menjalankan script ini di WSL."
    echo "👉 Silakan aktifkan WSL Integration di Docker Desktop:"
    echo "   1. Buka Docker Desktop"
    echo "   2. Masuk ke Settings → Resources → WSL Integration"
    echo "   3. Aktifkan untuk distro ini"
    echo "   4. Apply & Restart"
  else
    echo "📥 Mengunduh Docker Compose (standalone)..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
      -o /usr/local/bin/docker-compose

    sudo chmod +x /usr/local/bin/docker-compose

    echo "✅ Docker Compose berhasil diinstal: $(docker-compose --version)"
  fi
fi

# ===============================
# 🎉 Penutup
# ===============================
echo ""
echo "=============================="
echo "🎉 Semua beres!"
echo "Docker dan Docker Compose siap digunakan!"
echo "Sekarang kamu bisa menjalankan container Laravel kamu 🚀"
echo "Contoh: docker compose up -d"
echo "=============================="
