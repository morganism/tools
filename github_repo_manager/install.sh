#!/usr/bin/env bash
# GitHub Repository Manager - Installation Script

set -e

echo "╔═══════════════════════════════════════╗"
echo "║  GitHub Repository Manager Install    ║"
echo "╚═══════════════════════════════════════╝"
echo ""

# Check for Ruby
if ! command -v ruby &> /dev/null; then
    echo "❌ Ruby not found. Please install Ruby >= 3.0.0"
    exit 1
fi

RUBY_VERSION=$(ruby -e 'puts RUBY_VERSION')
echo "✓ Found Ruby $RUBY_VERSION"

# Check for Git
if ! command -v git &> /dev/null; then
    echo "❌ Git not found. Please install Git"
    exit 1
fi

echo "✓ Found Git"

# Make executable
chmod +x github-repo-manager
echo "✓ Made executable"

# Create .env if it doesn't exist
if [ ! -f .env ]; then
    cp .env.example .env
    echo "✓ Created .env file"
    echo ""
    echo "📝 Please edit .env and add your GitHub token:"
    echo "   GITHUB_TOKEN=ghp_your_token_here"
    echo ""
    echo "   Get a token at: https://github.com/settings/tokens"
    echo "   Required scope: repo"
    echo ""
fi

# Optional: Install gems globally
read -p "Install gems globally with bundle? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if ! command -v bundle &> /dev/null; then
        echo "Installing bundler..."
        gem install bundler
    fi
    bundle install
    echo "✓ Gems installed"
else
    echo "ℹ️  Gems will be installed automatically on first run (bundler inline)"
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "Run the tool with:"
echo "  ./github-repo-manager"
echo ""
echo "Or install globally:"
echo "  sudo ln -s $(pwd)/github-repo-manager /usr/local/bin/github-repo-manager"
echo ""
