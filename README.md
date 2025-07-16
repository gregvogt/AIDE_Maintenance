# AIDE Maintenance Script

An enhanced bash script for automated AIDE (Advanced Intrusion Detection Environment) database maintenance with comprehensive security features, email notifications, and cron job support.

## Features

### Security Hardening
- **Bash hardening**: Uses `set -euo pipefail` for strict error handling
- **Input sanitization**: All user inputs are sanitized against injection attacks
- **Path validation**: Prevents path traversal attacks
- **Secure IFS**: Uses secure Internal Field Separator
- **Input validation**: Comprehensive validation of all parameters

### Enhanced Email Notifications
- **Multiple email methods**: Supports curl with SMTP, msmtp, mail, and sendmail
- **SMTP authentication**: Full SMTP server support with username/password
- **Email attachments**: Option to send current AIDE database (aide.db.gz) as attachment
- **MIME multipart emails**: Proper email formatting with base64 encoded attachments
- **Fallback methods**: Tries multiple email methods for reliability (SMTP first, then traditional)
- **Detailed reporting**: Includes AIDE exit codes, interpretation, and full log content in emails
- **Secure temporary files**: Email content files created with restrictive permissions (600)

### AIDE Exit Code Handling
- **Smart exit code interpretation**: Properly handles AIDE's non-standard exit codes
- **Change detection**: Distinguishes between file changes (codes 1-7) and fatal errors (codes 14-19)
- **Detailed reporting**: Logs and reports specific types of changes detected
- **Proper error handling**: Only fails on fatal errors, continues on change detection
- **Status tracking**: Tracks and reports both check and update results

### Command Line Interface
- **Full argument parsing**: Comprehensive command-line options
- **Validation**: All inputs are validated before processing
- **Help system**: Built-in help with examples
- **Quiet mode**: Suppress non-error output for cron jobs

### Cron Job Installation
- **Automatic installation**: Install as daily cron job at 12:00 AM
- **Argument preservation**: Saves all command-line arguments in cron job
- **Duplicate prevention**: Prevents duplicate cron entries

### Directory Management
- **Auto-creation**: Creates log directories if they don't exist
- **Path validation**: Ensures absolute paths and prevents traversal

### Compression Optimization
- **AIDE compatibility**: Keeps aide.db.gz and aide.db.new.gz as gzip (required by AIDE)
- **Backup compression**: Uses best available compression (zstd > brotli > gzip) for backups
- **Automatic detection**: Detects and uses best available compression tool
- **Safe command execution**: Uses arrays instead of eval for security
- **Proper decompression**: Handles different compression formats for log viewing

## Usage

### Basic Usage
```bash
./aide_maintenance.sh -l /var/log/aide -e admin@example.com
```

### With SMTP Server
```bash
./aide_maintenance.sh -l /var/log/aide -e admin@example.com \
  -s smtp.example.com -p 587 -u username -P password
```

### With Database Attachment
```bash
./aide_maintenance.sh -l /var/log/aide -e admin@example.com -a
```

### Install as Cron Job
```bash
./aide_maintenance.sh -l /var/log/aide -e admin@example.com -c
```

### Quiet Mode (for cron)
```bash
./aide_maintenance.sh -l /var/log/aide -e admin@example.com -q
```

## Command Line Options

| Option | Description |
|--------|-------------|
| `-l, --log-dir DIR` | Directory to store log files (required) |
| `-e, --email EMAIL` | Email address for notifications |
| `-s, --smtp-server SERVER` | SMTP server for email notifications |
| `-p, --smtp-port PORT` | SMTP server port (default: 25) |
| `-u, --smtp-user USER` | SMTP username |
| `-P, --smtp-pass PASS` | SMTP password |
| `-t, --sleep-time SECONDS` | Sleep time before starting (default: random 10-300) |
| `-a, --attach-db` | Send current AIDE database (aide.db.gz) as email attachment |
| `-c, --install-cron` | Install as daily cron job at 12:00 AM |
| `-q, --quiet` | Suppress non-error output |
| `-h, --help` | Show help message |

## Email Configuration

### Traditional Mail
The script will automatically detect and use available mail systems:
- `mail` command
- `sendmail`
- Postfix via `/usr/sbin/sendmail`

### SMTP Configuration
For advanced email features, configure SMTP settings:
```bash
# Gmail example
./aide_maintenance.sh -l /var/log/aide -e user@gmail.com \
  -s smtp.gmail.com -p 587 -u user@gmail.com -P app_password

# Corporate SMTP
./aide_maintenance.sh -l /var/log/aide -e admin@company.com \
  -s mail.company.com -p 25 -u admin -P password
```

## Security Features

### Input Validation
- Email addresses are validated against RFC-compliant regex
- Directory paths must be absolute and are checked for traversal attempts
- Port numbers are validated (1-65535)
- All user inputs are sanitized

### Path Security
- Prevents `../` and `..` path traversal attempts
- Requires absolute paths for directories
- Validates file existence before operations
- Checks for empty database files

### Bash Hardening
- `set -euo pipefail` for strict error handling
- Secure IFS to prevent word splitting attacks
- Proper quoting and variable expansion
- Error handling with cleanup on exit
- Safe command execution using arrays instead of eval to prevent injection
- Temporary file permissions set to 600 for security
- Comprehensive input sanitization against command injection

### AIDE Exit Code Security
- Proper handling of AIDE's non-zero exit codes
- Distinguishes between expected changes and actual errors
- Prevents script termination on normal AIDE change detection
- Comprehensive logging of all exit codes and their meanings

## File Locations

### AIDE Database Files
- **Current DB**: `/var/lib/aide/aide.db.gz` (always gzip for AIDE compatibility)
- **New DB**: `/var/lib/aide/aide.db.new.gz` (always gzip for AIDE compatibility)
- **Backup DB**: `/var/lib/aide/aide-TIMESTAMP.db.EXT` (best compression available)

### Log Files
- **Uncompressed**: `LOG_DIR/aide-check-TIMESTAMP.log` (temporary)
- **Compressed**: `LOG_DIR/aide-check-TIMESTAMP.log.EXT` (final)

## Compression Support

The script uses the best available compression for backup files:
1. **zstd** - Best compression ratio and speed
2. **brotli** - Good compression ratio
3. **gzip** - Universal compatibility

AIDE database files (`.db.gz` and `.db.new.gz`) are always kept as gzip since AIDE requires this format.

## Cron Installation

When installing as a cron job, the script:
1. Removes any existing AIDE maintenance cron jobs
2. Preserves all command-line arguments except `--install-cron`
3. Installs the job to run daily at 12:00 AM
4. Shows the installed cron entry

Example cron entry:
```
0 0 * * * /path/to/aide_maintenance.sh -l '/var/log/aide' -e 'admin@example.com' -q
```

## Error Handling

The script includes comprehensive error handling:
- Validates all inputs before processing
- Checks for required tools and files
- Provides detailed error messages
- Sends failure notifications via email
- Cleans up temporary files on exit
- Properly interprets AIDE exit codes
- Continues execution on file changes, fails only on fatal errors

## AIDE Exit Code Handling

The script properly handles AIDE's unique exit code system:

### Change Detection Codes (Non-Fatal)
- **0**: No changes detected
- **1**: New files detected
- **2**: Removed files detected
- **3**: New and removed files detected
- **4**: Changed files detected
- **5**: New and changed files detected
- **6**: Removed and changed files detected
- **7**: New, removed, and changed files detected

### Fatal Error Codes
- **14**: Error writing error
- **15**: Invalid argument error
- **16**: Unimplemented function error
- **17**: Invalid configuration line error
- **18**: IO error
- **19**: Version mismatch error

The script will continue execution and send notifications for change detection codes (1-7) but will fail and send error notifications for fatal error codes (14-19).

## Requirements

### Required
- `bash` (version 4.0+)
- `aide` (Advanced Intrusion Detection Environment)
- `gzip` (for AIDE database compatibility)

### Optional (for enhanced features)
- `zstd` or `brotli` (for optimal backup compression)
- `mail`, `sendmail`, or `msmtp` (for email notifications)
- `curl` (for modern SMTP email support - preferred method)
- `base64` (for email attachments - usually included in coreutils)
- `crontab` (for cron job installation)

## Examples

### Basic Setup
```bash
# Simple setup with email notifications
./aide_maintenance.sh -l /var/log/aide -e admin@example.com

# Install as cron job
./aide_maintenance.sh -l /var/log/aide -e admin@example.com -c
```

### Advanced Setup
```bash
# Full featured setup with SMTP and database attachment
./aide_maintenance.sh \
  -l /var/log/aide \
  -e security@company.com \
  -s smtp.company.com \
  -p 587 \
  -u monitoring \
  -P secure_password \
  -a \
  -t 60

# Install with all features
./aide_maintenance.sh \
  -l /var/log/aide \
  -e security@company.com \
  -s smtp.company.com \
  -p 587 \
  -u monitoring \
  -P secure_password \
  -a \
  -q \
  -c
```

## License

This script is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

