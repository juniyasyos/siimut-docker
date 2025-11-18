#!/bin/bash

set -e

TARGET_DIR="./site/client-iiam"

echo "🚀 Setting up CLIENT-IIAM project..."

if [ -d "$TARGET_DIR" ]; then
    echo "⚠️  Directory $TARGET_DIR already exists."
    read -p "Do you want to continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Aborted."
        exit 1
    fi
else
    echo "📁 Creating directory $TARGET_DIR..."
    mkdir -p "$TARGET_DIR"
fi

echo ""
echo "✅ Directory created successfully!"
echo ""
echo "Next steps:"
echo "  1. Place your CLIENT-IIAM Laravel application in $TARGET_DIR"
echo "  2. Or create a new Laravel project:"
echo "     docker run --rm -v \$(pwd)/site:/app composer create-project laravel/laravel client-iiam"
echo "  3. Configure $TARGET_DIR/.env with your database settings"
echo "  4. Run: docker-compose up -d"
echo "  5. Access at: http://localhost:8082"
