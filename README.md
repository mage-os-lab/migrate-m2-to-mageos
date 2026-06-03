# Migrate Magento 2 to Mage-OS

This repository contains a migration script to help you migrate from Magento 2 Community Edition to Mage-OS.

## Requirements

Before running this migration script, ensure your environment meets the following requirements:

- **Magento Version**: 2.4.9 (including all patch versions like 2.4.9-p1, 2.4.9-p2, etc.)
- **Magento Mode**: Developer mode (the script will verify this)
- **Environment**: Local or staging environment (**DO NOT run on production**)

## How to Execute

### Option 1: Direct Execution (Recommended)

Run the script directly from the repository:

```bash
bash <(curl -s https://raw.githubusercontent.com/mage-os-lab/migrate-m2-to-mageos/refs/heads/main/migrate-to-mage-os.sh)
```

### Option 2: Download and Execute

Download the script first, then execute it:

```bash
# Download the script
curl -O https://raw.githubusercontent.com/mage-os-lab/migrate-m2-to-mageos/refs/heads/main/migrate-to-mage-os.sh

# Make it executable
chmod +x migrate-to-mage-os.sh

# Run the script
./migrate-to-mage-os.sh
```

### Options

- `--no-security-blocking`: lets the `composer update` step proceed past composer security advisories instead of halting on them. By default the migration respects advisories; only add this flag when an advisory is expected and you have reviewed it. If the update fails because of an advisory, the script detects it and reminds you of this option.

```bash
# Direct execution
bash <(curl -s https://raw.githubusercontent.com/mage-os-lab/migrate-m2-to-mageos/refs/heads/main/migrate-to-mage-os.sh) --no-security-blocking

# Downloaded script
./migrate-to-mage-os.sh --no-security-blocking
```

## After Migration

Make sure to check your installation thoroughly before deploying to production.

## Important Notes

- **This script is intended for local and staging environments only**
- **Always backup your database and files before running the migration**
- **Ensure you're running Magento 2.4.9 before starting the migration**
- **DO NOT run on production**
- The script will prompt you to accept Mage-OS Composer plugins during execution

## Support Mage-OS

Thank you for upgrading to Mage-OS! We are always looking for members, maintainers, and sponsors.

For more information, please visit: https://mage-os.org/about/mage-os-membership/

## Contributing

If you encounter any issues or have suggestions for improvements, please open an issue or submit a pull request.
