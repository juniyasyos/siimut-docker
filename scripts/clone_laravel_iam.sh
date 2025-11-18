#!/bin/bash

set -e

REPO_URL="https://github.com/juniyasyos/laravel-iam.git"
TARGET_DIR="./site/laravel-iam"

echo "🔄 Cloning Laravel-IAM repository..."

if [ -d "$TARGET_DIR" ]; then
    echo "⚠️  Directory $TARGET_DIR already exists."
    read -p "Do you want to remove it and clone again? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️  Removing existing directory..."
        rm -rf "$TARGET_DIR"
    else
        echo "❌ Aborted."
        exit 1
    fi
fi

echo "📥 Cloning repository from $REPO_URL..."
git clone "$REPO_URL" "$TARGET_DIR"

echo "✅ Laravel-IAM has been cloned successfully to $TARGET_DIR"

# Copy .env.example to .env if it exists
if [ -f "$TARGET_DIR/.env.example" ]; then
    echo "📝 Creating .env file from .env.example..."
    cp "$TARGET_DIR/.env.example" "$TARGET_DIR/.env"
    echo "✅ .env file created"
else
    echo "⚠️  .env.example not found. You may need to create .env manually."
fi

echo ""
echo "🎉 Setup complete!"
echo "Next steps:"
echo "  1. Configure $TARGET_DIR/.env with your database settings"
echo "  2. Run: docker-compose up -d"
echo "  3. Run: docker exec -it iam-app bash"
echo "  4. Inside container: composer install && php artisan key:generate && php artisan migrate"
