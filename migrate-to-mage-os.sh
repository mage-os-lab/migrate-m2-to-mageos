#!/bin/bash

# Exit on error, undefined variables, and pipe failures
set -euo pipefail
#set -x

# Color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# WARNING: Do not execute this script on a production environment
if [[ -z "${CI:-}" ]]; then
    echo -e "${YELLOW}==========================================${NC}"
    echo -e "${YELLOW}WARNING: Mage-OS Migration Script${NC}"
    echo -e "${YELLOW}==========================================${NC}"
    echo ""
    echo -e "${YELLOW}Do not execute this script on a production environment!${NC}"
    echo -e "${YELLOW}Only run this on a local or staging environment.${NC}"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]
    then
        echo -e "${RED}Migration cancelled.${NC}"
        exit 1
    fi
fi

# Validate that this is a Magento installation
if [[ ! -f "app/etc/env.php" || ! -f "bin/magento" ]]; then
    echo -e "${RED}Error: This does not appear to be a valid Magento installation.${NC}"
    echo -e "${RED}Required files not found: app/etc/env.php and/or bin/magento${NC}"
    echo -e "${RED}Please run this script from the root directory of your Magento installation.${NC}"
    exit 1
fi

echo -e "${GREEN}Valid Magento installation detected${NC}"

# Check if PHP is available
if command -v php &> /dev/null; then
    PHP_CMD="php"
elif [ -f "/usr/local/bin/php" ]; then
    PHP_CMD="/usr/local/bin/php"
elif [ -f "/usr/bin/php" ]; then
    PHP_CMD="/usr/bin/php"
else
    echo -e "${RED}Error: Unable to detect your PHP executable.${NC}"
    echo -e "${RED}Could it be that you need to run this script inside your Docker environment?${NC}"
    exit 1
fi

echo "Using PHP: $PHP_CMD"

# Check if composer is available
if command -v composer &> /dev/null; then
    COMPOSER_CMD="composer"
elif [ -f "/usr/local/bin/composer" ]; then
    COMPOSER_CMD="/usr/local/bin/composer"
elif [ -f "/usr/bin/composer" ]; then
    COMPOSER_CMD="/usr/bin/composer"
elif [ -f "composer.phar" ]; then
    COMPOSER_CMD="$PHP_CMD composer.phar"
elif [ -f "../composer.phar" ]; then
    COMPOSER_CMD="$PHP_CMD ../composer.phar"
else
    echo -e "${RED}Error: Unable to detect your composer executable.${NC}"
    echo -e "${RED}Could it be that you need to run this script inside your Docker environment?${NC}"
    exit 1
fi

echo "Using composer: $COMPOSER_CMD"

# Check if migration has already been run
echo "Checking if migration has already been run"

if $COMPOSER_CMD show magento/product-community-edition --no-interaction &> /dev/null; then
    HAS_MAGENTO=true
else
    HAS_MAGENTO=false
fi

if $COMPOSER_CMD show mage-os/product-community-edition --no-interaction &> /dev/null; then
    HAS_MAGEOS=true
else
    HAS_MAGEOS=false
fi

if [[ "$HAS_MAGENTO" == "false" && "$HAS_MAGEOS" == "true" ]]; then
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "${YELLOW}Migration already completed${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    echo ""
    echo -e "${GREEN}This store has already been migrated to Mage-OS.${NC}"
    echo "No further action is needed."
    exit 0
elif [[ "$HAS_MAGENTO" == "false" && "$HAS_MAGEOS" == "false" ]]; then
    echo -e "${RED}Error: Neither magento/product-community-edition nor mage-os/product-community-edition found.${NC}"
    echo -e "${RED}This does not appear to be a valid Magento Community Edition installation.${NC}"
    exit 1
fi

echo -e "${GREEN}Ready to migrate from Magento to Mage-OS${NC}"

# Get the Magento version
echo "Checking your Magento version"
MAGENTO_VERSION=$($PHP_CMD bin/magento --version 2>&1 | grep -oP 'Magento CLI \K[0-9]+\.[0-9]+\.[0-9]+')

# Check if version is 2.4.8
if [[ "$MAGENTO_VERSION" != 2.4.8* ]]; then
    echo -e "${RED}Error: This script only supports Magento 2.4.8${NC}"
    echo -e "${RED}Your version: $MAGENTO_VERSION${NC}"
    echo -e "${YELLOW}It is important to upgrade your store to the latest Magento version before upgrading to Mage-OS.${NC}"
    exit 1
fi

echo -e "${GREEN}Magento version $MAGENTO_VERSION detected - proceeding with migration${NC}"

# Check if store is in developer mode
echo "Checking Magento mode"
MAGENTO_MODE=$($PHP_CMD bin/magento deploy:mode:show 2>&1)

if [[ "$MAGENTO_MODE" != *"developer"* ]]; then
    echo -e "${RED}Error: This script requires Magento to be in developer mode.${NC}"
    echo -e "${RED}Current mode: $MAGENTO_MODE${NC}"
    echo -e "${YELLOW}Please switch to developer mode first using: bin/magento deploy:mode:set developer${NC}"
    exit 1
fi

echo -e "${GREEN}Developer mode confirmed${NC}"
echo ""
echo ""

# Add the Mage-OS repository, so Composer know where to download the packages from
$COMPOSER_CMD config repositories.mage-os composer https://repo.mage-os.org/ --no-interaction

# This actually installs Mage-OS
$COMPOSER_CMD require mage-os/product-community-edition --no-update --no-interaction

# Remove version constraints to prevent update issues
$COMPOSER_CMD require allure-framework/allure-phpunit:* magento/magento2-functional-testing-framework:* phpstan/phpstan:* phpunit/phpunit:* sebastian/phpcpd:* --dev --no-update --no-interaction

# We don't need these packages anymore
$COMPOSER_CMD remove magento/product-community-edition magento/composer-dependency-version-audit-plugin magento/composer-root-update-plugin --no-update --no-interaction

# Actually run the update.
$COMPOSER_CMD update --no-plugins --with-all-dependencies --no-interaction

echo ""
echo "Verifying Mage-OS installation..."
echo "Note: You may be prompted to accept Mage-OS plugins. Please review and accept them."
echo ""

# Verify installation and allow plugin prompts
$COMPOSER_CMD show mage-os/product-community-edition

echo ""
echo -e "${GREEN}Mage-OS installation verified successfully${NC}"
echo ""

# Remove generated static files
rm -rf pub/static/adminhtml and pub/static/frontend generated/*

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Migration completed successfully!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "${GREEN}Thank you for upgrading to Mage-OS, we really appreciate it.${NC}"
echo ""
echo "We are always looking for members, maintainers and sponsors."
echo "For more information about that, please visit:"
echo "https://mage-os.org/about/mage-os-membership/"
echo ""
echo -e "${YELLOW}IMPORTANT: Next steps to complete the migration:${NC}"
echo -e "${YELLOW}1. Flush your cache directly, not through Magento.${NC}"
echo -e "${YELLOW}   - Flush Redis or remove the contents of the 'var/cache' folder${NC}"
echo -e "${YELLOW}2. Run: bin/magento setup:upgrade${NC}"
echo ""
