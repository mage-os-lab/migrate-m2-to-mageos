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

echo -e "${GREEN}Ready to migrate from Magento to Mage-OS${NC}"

# Get the Magento version
echo "Checking your Magento version"
VERSION_OUTPUT=$($PHP_CMD bin/magento --version 2>&1)
MAGENTO_VERSION=$(printf "%s" "$VERSION_OUTPUT" | awk '{
    for (i=1; i<=NF; i++) {
        token = $i
        gsub(/^[^0-9]*/, "", token)
        gsub(/[^0-9A-Za-z.\-].*$/, "", token)
        if (token ~ /^2\.4\.8/) {
            print token
            exit
        }
    }
}')

if [[ -z "$MAGENTO_VERSION" ]]; then
    echo -e "${RED}Error: This script only supports Magento 2.4.8${NC}"
    echo -e "${RED}Version output:${NC} $VERSION_OUTPUT"
    echo -e "${YELLOW}It is important to upgrade your store to the latest Magento version before upgrading to Mage-OS.${NC}"
    exit 1
fi

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

#########################################################################################################
# Below this block are the following commands executed. They are idempotent, so it may be hard to read. #
#########################################################################################################
#
# composer config repositories.mage-os composer https://repo.mage-os.org/ --no-interaction
# composer config repositories.mage-os composer https://repo.mage-os.org/ --no-interaction
# composer require allure-framework/allure-phpunit:* magento/magento2-functional-testing-framework:* phpstan/phpstan:* phpunit/phpunit:* sebastian/phpcpd:* --dev --no-update --no-interaction
# composer remove magento/product-community-edition magento/composer-dependency-version-audit-plugin magento/composer-root-update-plugin --no-update --no-interaction
# composer update --no-plugins --with-all-dependencies --no-interaction
#
#########################################################################################################

# Helper function to check if a package exists in composer.json
package_exists() {
    local package=$1
    local dev_flag=${2:-""}

    if [[ "$dev_flag" == "--dev" ]]; then
        grep -q "\"$package\"" composer.json && grep -A 999 "\"require-dev\"" composer.json | grep -m 1 -B 999 "}" | grep -q "\"$package\""
    else
        grep -q "\"$package\"" composer.json && grep -A 999 "\"require\"" composer.json | grep -m 1 -B 999 "}" | grep -q "\"$package\""
    fi
}

# Helper function to extract values from env.php
get_env_config() {
    local key_path=$1

    $PHP_CMD -r "
        \$config = require 'app/etc/env.php';
        \$keys = explode('.', '${key_path}');
        \$value = \$config;
        foreach (\$keys as \$key) {
            if (isset(\$value[\$key])) {
                \$value = \$value[\$key];
            } else {
                \$value = ''; break;
            }
        }
        echo is_array(\$value) ? json_encode(\$value) : \$value;
    " 2>/dev/null
}

# Helper function to flush Redis database using PHP
flush_redis_db() {
    local server=$1
    local port=$2
    local password=$3
    local db=$4
    local db_name=$5

    # Return if no server configured
    if [ -z "${server}" ]; then
        return 0
    fi

    echo "Flushing Redis ${db_name} (${server}:${port:-socket}, db: ${db})..."

    # Use PHP to flush Redis
    $PHP_CMD -r "
        if (!extension_loaded('redis')) {
            echo 'Redis extension not available, skipping flush\n';
            exit(0);
        }

        \$redis = new Redis();
        try {
            // Connect to Redis (socket or TCP)
            if ('${port}' === '' || '${port}' === '0') {
                \$connected = \$redis->connect('${server}');
            } else {
                \$connected = \$redis->connect('${server}', ${port});
            }

            if (!\$connected) {
                echo 'Failed to connect to Redis\n';
                exit(1);
            }

            // Authenticate if password is provided
            if ('${password}' !== '') {
                \$redis->auth('${password}');
            }

            // Select database
            if ('${db}' !== '') {
                \$redis->select(${db});
            }

            // Flush the database
            \$redis->flushDB();
            echo 'Successfully flushed Redis ${db_name}' . PHP_EOL;
            \$redis->close();
        } catch (Exception \$e) {
            echo 'Error flushing Redis: ' . \$e->getMessage() . PHP_EOL;
            exit(1);
        }
    " 2>&1
}

# Add the Mage-OS repository, so Composer know where to download the packages from
$COMPOSER_CMD config repositories.mage-os composer https://repo.mage-os.org/ --no-interaction

# Ensure composer.json name matches Mage-OS
$PHP_CMD -r '
    $path = "composer.json";
    if (!file_exists($path)) {
        fwrite(STDERR, "composer.json not found\n");
        exit(1);
    }

    $composer = json_decode(file_get_contents($path), true);
    if ($composer === null || json_last_error() !== JSON_ERROR_NONE) {
        fwrite(STDERR, "Unable to parse composer.json\n");
        exit(1);
    }

    $current = $composer["name"] ?? "";
    if ($current === "magento/project-community-edition") {
        $composer["name"] = "mage-os/project-community-edition";
        file_put_contents(
            $path,
            json_encode($composer, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL
        );
        echo "Updated composer.json name to mage-os/project-community-edition\n";
    } else {
        echo "composer.json name already set to: " . ($current === "" ? "(none)" : $current) . "\n";
    }
'

# Convert magento/* entries in composer.json replace to mage-os/*
$PHP_CMD -r '
    $path = "composer.json";
    if (!file_exists($path)) {
        fwrite(STDERR, "composer.json not found\n");
        exit(1);
    }

    $composer = json_decode(file_get_contents($path), true);
    if (!is_array($composer)) {
        fwrite(STDERR, "Unable to parse composer.json\n");
        exit(1);
    }

    if (empty($composer["replace"]) || !is_array($composer["replace"])) {
        echo "No replace section in composer.json\n";
        exit(0);
    }

    $removed = 0;
    $added = 0;
    foreach (array_keys($composer["replace"]) as $package) {
        if (strpos($package, "magento/") !== 0) {
            continue;
        }

        $mageOsPackage = "mage-os/" . substr($package, strlen("magento/"));
        if (!isset($composer["replace"][$mageOsPackage])) {
            $composer["replace"][$mageOsPackage] = $composer["replace"][$package];
            $added++;
        }

        unset($composer["replace"][$package]);
        $removed++;
    }

    if ($removed > 0 || $added > 0) {
        if ($composer["replace"] === []) {
            unset($composer["replace"]);
        }
        file_put_contents(
            $path,
            json_encode($composer, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL
        );
        echo "Converted {$removed} magento/* entries to mage-os/* (added {$added}, removed {$removed})\n";
    } else {
        echo "No magento/* entries found in composer.json replace\n";
    }
'

# This actually installs Mage-OS
if ! package_exists "mage-os/product-community-edition"; then
    echo "Adding mage-os/product-community-edition to composer.json"
    $COMPOSER_CMD require mage-os/product-community-edition --no-update --no-interaction
else
    echo "mage-os/product-community-edition already exists in composer.json, skipping"
fi

# Remove version constraints to prevent update issues
# Check if any of the dev packages are missing
DEV_PACKAGES=(
    "allure-framework/allure-phpunit"
    "magento/magento2-functional-testing-framework"
    "phpstan/phpstan"
    "phpunit/phpunit"
    "sebastian/phpcpd"
)
MISSING_DEV_PACKAGES=false
for pkg in "${DEV_PACKAGES[@]}"; do
    if ! package_exists "$pkg" "--dev"; then
        MISSING_DEV_PACKAGES=true
        break
    fi
done

if [ "$MISSING_DEV_PACKAGES" = true ]; then
    echo "Configuring dev dependencies version constraints"
    $COMPOSER_CMD require allure-framework/allure-phpunit:* magento/magento2-functional-testing-framework:* phpstan/phpstan:* phpunit/phpunit:* sebastian/phpcpd:* --dev --no-update --no-interaction
else
    echo "Dev dependencies already configured, skipping"
fi

# We don't need these packages anymore
PACKAGES_TO_REMOVE=(
    "magento/product-community-edition"
    "magento/composer-dependency-version-audit-plugin"
    "magento/composer-root-update-plugin"
)
PACKAGES_NEED_REMOVAL=false
for pkg in "${PACKAGES_TO_REMOVE[@]}"; do
    if package_exists "$pkg"; then
        PACKAGES_NEED_REMOVAL=true
        break
    fi
done

if [ "$PACKAGES_NEED_REMOVAL" = true ]; then
    echo "Removing Magento packages"
    $COMPOSER_CMD remove magento/product-community-edition magento/composer-dependency-version-audit-plugin magento/composer-root-update-plugin --no-update --no-interaction
else
    echo "Magento packages already removed, skipping"
fi

# Actually run the update.
UPDATE_SUCCESS=false
while [ "$UPDATE_SUCCESS" = false ]; do
    echo "Running composer update..."
    if $COMPOSER_CMD update --no-plugins --with-all-dependencies --no-interaction; then
        UPDATE_SUCCESS=true
        echo -e "${GREEN}Composer update completed successfully${NC}"
    else
        echo ""
        echo -e "${RED}=========================================${NC}"
        echo -e "${RED}Composer update failed${NC}"
        echo -e "${RED}=========================================${NC}"
        echo ""
        echo -e "${YELLOW}It seems that the \`composer update\` command failed.${NC}"
        echo -e "${YELLOW}Please take a look at the errors reported, see if you can fix them and try again.${NC}"
        echo ""
        echo -e "${YELLOW}If you need help with this step you can always ask for help at the Mage-OS Discord channel:${NC}"
        echo -e "${YELLOW}https://mage-os.org/discord-channel/${NC}"
        echo ""

        read -p "Would you like to retry the composer update? (Yes/no): " -r
        echo ""
        if [[ -z "$REPLY" || "$REPLY" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            echo "Retrying composer update..."
        else
            echo -e "${RED}Migration cancelled.${NC}"
            exit 1
        fi
    fi
done

echo ""
echo "Verifying Mage-OS installation..."
echo "Note: You may be prompted to accept Mage-OS plugins. Please review and accept them."
echo ""

# Verify installation and allow plugin prompts
$COMPOSER_CMD show mage-os/product-community-edition

echo ""
echo -e "${GREEN}Mage-OS installation verified successfully${NC}"
echo ""

# Clean up caches and generated files
echo "Cleaning up caches and generated files..."

# Extract Redis cache configuration
redisCacheServer=$(get_env_config "cache.frontend.default.backend_options.server")
redisCachePort=$(get_env_config "cache.frontend.default.backend_options.port")
redisCachePassword=$(get_env_config "cache.frontend.default.backend_options.password")
redisCacheDB=$(get_env_config "cache.frontend.default.backend_options.database")

# Extract Redis page cache configuration
redisPageCacheServer=$(get_env_config "cache.frontend.page_cache.backend_options.server")
redisPageCachePort=$(get_env_config "cache.frontend.page_cache.backend_options.port")
redisPageCachePassword=$(get_env_config "cache.frontend.page_cache.backend_options.password")
redisPageCacheDB=$(get_env_config "cache.frontend.page_cache.backend_options.database")

# Extract Redis session configuration
redisSessionServer=$(get_env_config "session.redis.host")
redisSessionPort=$(get_env_config "session.redis.port")
redisSessionPassword=$(get_env_config "session.redis.password")
redisSessionDB=$(get_env_config "session.redis.database")

# Flush Redis caches if configured
REDIS_FLUSHED=false
if [ -n "${redisCacheServer}" ]; then
    flush_redis_db "${redisCacheServer}" "${redisCachePort}" "${redisCachePassword}" "${redisCacheDB}" "cache"
    REDIS_FLUSHED=true
fi

if [ -n "${redisPageCacheServer}" ] && [ "${redisPageCacheServer}" != "${redisCacheServer}" ]; then
    flush_redis_db "${redisPageCacheServer}" "${redisPageCachePort}" "${redisPageCachePassword}" "${redisPageCacheDB}" "page_cache"
    REDIS_FLUSHED=true
fi

if [ -n "${redisSessionServer}" ]; then
    flush_redis_db "${redisSessionServer}" "${redisSessionPort}" "${redisSessionPassword}" "${redisSessionDB}" "session"
    REDIS_FLUSHED=true
fi

# Remove file-based cache if Redis wasn't flushed
if [ "$REDIS_FLUSHED" = false ]; then
    echo "No Redis configuration found"
fi

# Remove generated static files
echo "Removing generated static and cache files..."
rm -rf pub/static/adminhtml pub/static/frontend generated/* var/cache/*

echo -e "${GREEN}Cache and generated files cleaned successfully${NC}"
echo ""

# Run setup:upgrade
echo "Running setup:upgrade to complete the migration..."
echo ""
if $PHP_CMD bin/magento setup:upgrade; then
    echo ""
    echo -e "${GREEN}Setup:upgrade completed successfully${NC}"
else
    echo ""
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}Setup upgrade failed${NC}"
    echo -e "${RED}=========================================${NC}"
    echo ""
    echo -e "${YELLOW}The migration process completed, but setup:upgrade failed.${NC}"
    echo -e "${YELLOW}Please review the errors above and run the following command manually:${NC}"
    echo -e "${YELLOW}  bin/magento setup:upgrade${NC}"
    echo ""
    echo -e "${YELLOW}If you need help, ask at the Mage-OS Discord channel:${NC}"
    echo -e "${YELLOW}https://mage-os.org/discord-channel/${NC}"
    echo ""
    exit 1
fi

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
