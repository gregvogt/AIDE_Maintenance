#!/bin/bash

# This is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this. If not, see <https://www.gnu.org/licenses/>.
#
# @package AIDE Maintenance Script
# @author  Greg Vogt <contact@gregvogt.net>
# @license https://www.gnu.org/licenses/gpl-3.0.html GNU General Public License v3.0
# @link    https://gregvogt.net/projects

# Security hardening
set -euo pipefail # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'       # Secure Internal Field Separator

# Initialize variables with defaults
LOG_DIR=""
EMAIL=""
SMTP_SERVER=""
SMTP_PORT="25"
SMTP_USER=""
SMTP_PASS=""
SLEEP_TIME=""
SEND_DB_ATTACHMENT="false"
INSTALL_CRON="false"
QUIET="false"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# Path variables (ensure these are always gzip for AIDE compatibility)
OLD_DB="/var/lib/aide/aide.db.gz"
NEW_DB="/var/lib/aide/aide.db.new.gz"
DECOMPRESS="gzip -d -c"

# Function to sanitize input
sanitize_input() {
    local input="$1"
    # Remove potentially dangerous characters
    echo "$input" | sed "s/[;&|\`\$(){}[\]<>]//g" | tr -d '\000-\037\177-\377'
}

# Function to validate email
validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        echo "Invalid email address: $email" >&2
        return 1
    fi
    return 0
}

# Function to validate directory path
validate_directory() {
    local dir="$1"
    # Check for path traversal attempts
    if [[ "$dir" =~ \.\./|\.\. ]]; then
        echo "Path traversal attempt detected in directory: $dir" >&2
        return 1
    fi
    # Check for absolute path
    if [[ ! "$dir" =~ ^/ ]]; then
        echo "Directory must be an absolute path: $dir" >&2
        return 1
    fi
    return 0
}

# Function to validate port number
validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "Invalid port number: $port" >&2
        return 1
    fi
    return 0
}

# Function to show usage
show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -l, --log-dir DIR           Directory to store log files (required)
    -e, --email EMAIL           Email address for notifications
    -s, --smtp-server SERVER    SMTP server for email notifications
    -p, --smtp-port PORT        SMTP server port (default: 25)
    -u, --smtp-user USER        SMTP username
    -P, --smtp-pass PASS        SMTP password
    -t, --sleep-time SECONDS    Sleep time before starting (default: random 10-300)
    -a, --attach-db             Send current database as email attachment
    -c, --install-cron          Install as daily cron job at 12:00 AM
    -q, --quiet                 Suppress non-error output
    -h, --help                  Show this help message

Examples:
    $0 -l /var/log/aide -e admin@example.com
    $0 -l /var/log/aide -e admin@example.com -s smtp.example.com -p 587 -u user -P pass -a
    $0 -l /var/log/aide -e admin@example.com -c

EOF
}

# Function to parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        -l | --log-dir)
            LOG_DIR="$(sanitize_input "$2")"
            shift 2
            ;;
        -e | --email)
            EMAIL="$(sanitize_input "$2")"
            shift 2
            ;;
        -s | --smtp-server)
            SMTP_SERVER="$(sanitize_input "$2")"
            shift 2
            ;;
        -p | --smtp-port)
            SMTP_PORT="$(sanitize_input "$2")"
            shift 2
            ;;
        -u | --smtp-user)
            SMTP_USER="$(sanitize_input "$2")"
            shift 2
            ;;
        -P | --smtp-pass)
            SMTP_PASS="$2" # Don't sanitize password
            shift 2
            ;;
        -t | --sleep-time)
            SLEEP_TIME="$(sanitize_input "$2")"
            shift 2
            ;;
        -a | --attach-db)
            SEND_DB_ATTACHMENT="true"
            shift
            ;;
        -c | --install-cron)
            INSTALL_CRON="true"
            shift
            ;;
        -q | --quiet)
            QUIET="true"
            shift
            ;;
        -h | --help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_usage
            exit 1
            ;;
        esac
    done
}

# Function to validate all arguments
validate_args() {
    if [[ -z "$LOG_DIR" ]]; then
        echo "Error: Log directory is required" >&2
        show_usage
        exit 1
    fi

    if ! validate_directory "$LOG_DIR"; then
        exit 1
    fi

    if [[ -n "$EMAIL" ]] && ! validate_email "$EMAIL"; then
        exit 1
    fi

    if [[ -n "$SMTP_PORT" ]] && ! validate_port "$SMTP_PORT"; then
        exit 1
    fi

    if [[ -n "$SLEEP_TIME" ]] && ! [[ "$SLEEP_TIME" =~ ^[0-9]+$ ]]; then
        echo "Error: Sleep time must be a positive integer" >&2
        exit 1
    fi

    # If sending email attachments, email must be provided
    if [[ "$SEND_DB_ATTACHMENT" == "true" && -z "$EMAIL" ]]; then
        echo "Error: Email address required when sending database attachments" >&2
        exit 1
    fi
}

# Function to create directories if they don't exist
create_directories() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        if ! mkdir -p "$dir"; then
            echo "Error: Failed to create directory: $dir" >&2
            exit 1
        fi
        [[ "$QUIET" != "true" ]] && echo "Created directory: $dir"
    fi
}

# Function to install cron job
install_cron_job() {
    local script_path
    script_path="$(realpath "$0")"
    local cron_cmd="$script_path"

    # Add all arguments except --install-cron
    [[ -n "$LOG_DIR" ]] && cron_cmd="$cron_cmd -l '$LOG_DIR'"
    [[ -n "$EMAIL" ]] && cron_cmd="$cron_cmd -e '$EMAIL'"
    [[ -n "$SMTP_SERVER" ]] && cron_cmd="$cron_cmd -s '$SMTP_SERVER'"
    [[ -n "$SMTP_PORT" && "$SMTP_PORT" != "25" ]] && cron_cmd="$cron_cmd -p '$SMTP_PORT'"
    [[ -n "$SMTP_USER" ]] && cron_cmd="$cron_cmd -u '$SMTP_USER'"
    [[ -n "$SMTP_PASS" ]] && cron_cmd="$cron_cmd -P '$SMTP_PASS'"
    [[ -n "$SLEEP_TIME" ]] && cron_cmd="$cron_cmd -t '$SLEEP_TIME'"
    [[ "$SEND_DB_ATTACHMENT" == "true" ]] && cron_cmd="$cron_cmd -a"
    [[ "$QUIET" == "true" ]] && cron_cmd="$cron_cmd -q"

    local cron_entry="0 0 * * * $cron_cmd"

    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "aide_maintenance.sh"; then
        echo "Cron job already exists. Removing old entry..."
        crontab -l 2>/dev/null | grep -v "aide_maintenance.sh" | crontab -
    fi

    # Add new cron job
    (
        crontab -l 2>/dev/null
        echo "$cron_entry"
    ) | crontab -
    echo "Cron job installed successfully:"
    echo "$cron_entry"
    exit 0
}

# Parse command line arguments
parse_args "$@"

# Validate arguments
validate_args

# Install cron job if requested
if [[ "$INSTALL_CRON" == "true" ]]; then
    install_cron_job
fi

# Create log directory
create_directories "$LOG_DIR"

# Set up log file
LOG_FILE="$LOG_DIR/aide-check-$TIMESTAMP.log"

# Function to center text
center() {
    local width
    width=$(tput cols 2>/dev/null || echo 80)
    awk -v w="$width" '{ l=length($0); if (l<w) { printf "%*s%s\n", int((w-l)/2), "", $0 } else { print } }'
}

# Display banner
if [[ "$QUIET" != "true" ]]; then
    cat <<"EOF" | tee -a "$LOG_FILE"
 $$$$$$\  $$$$$$\ $$$$$$$\  $$$$$$$$\       $$$$$$$\                                           $$\
$$  __$$\ \_$$  _|$$  __$$\ $$  _____|      $$  __$$\                                          $$ |
$$ /  $$ |  $$ |  $$ |  $$ |$$ |            $$ |  $$ | $$$$$$\   $$$$$$\   $$$$$$\   $$$$$$\ $$$$$$\
$$$$$$$$ |  $$ |  $$ |  $$ |$$$$$\          $$$$$$$  |$$  __$$\ $$  __$$\ $$  __$$\ $$  __$$\\_$$  _|
$$  __$$ |  $$ |  $$ |  $$ |$$  __|         $$  __$$< $$$$$$$$ |$$ /  $$ |$$ /  $$ |$$ |  \__| $$ |
$$ |  $$ |  $$ |  $$ |  $$ |$$ |            $$ |  $$ |$$   ____|$$ |  $$ |$$ |  $$ |$$ |       $$ |$$\
$$ |  $$ |$$$$$$\ $$$$$$$  |$$$$$$$$\       $$ |  $$ |\$$$$$$$\ $$$$$$$  |\$$$$$$  |$$ |       \$$$$  |
\__|  \__|\______|\_______/ \________|      \__|  \__| \_______|$$  ____/  \______/ \__|        \____/
                                                                $$ |
                                                                $$ |
                                                                \__|
EOF
    echo "" | tee -a "$LOG_FILE"
    date | center | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
fi

# Set sleep time (random if not specified)
if [[ -z "$SLEEP_TIME" ]]; then
    SLEEP_TIME=$((RANDOM % 291 + 10))
fi

# Sleep to offset start time
if [[ "$QUIET" != "true" ]]; then
    echo "Sleeping for $SLEEP_TIME seconds to offset start time..."
fi
sleep "$SLEEP_TIME"

# Function to determine compression tool and extension for backups
determine_compression() {
    if command -v zstd >/dev/null 2>&1; then
        [[ "$QUIET" != "true" ]] && echo "Using ZSTD for backup compression."
        COMPRESS="zstd -19 -T0 -c"
        EXT="zst"
    elif command -v brotli >/dev/null 2>&1; then
        [[ "$QUIET" != "true" ]] && echo "Using BROTLI for backup compression."
        COMPRESS="brotli -q 11 -c"
        EXT="br"
    elif command -v gzip >/dev/null 2>&1; then
        [[ "$QUIET" != "true" ]] && echo "Using GZIP for backup compression."
        COMPRESS="gzip -9 -c"
        EXT="gz"
    else
        echo "No supported compression tool (zstd, brotli, gzip) found." >&2
        exit 1
    fi
}

# Function to determine decompression command based on file extension
determine_decompression() {
    local file="$1"

    if [[ "$file" == *.zst ]]; then
        echo "zstd -d -c"
    elif [[ "$file" == *.br ]]; then
        echo "brotli -d -c"
    elif [[ "$file" == *.gz ]]; then
        echo "gzip -d -c"
    else
        echo "cat" # Fallback for uncompressed files
    fi
}

# Function to send email with enhanced capabilities
send_email() {
    local subject="$1"
    local body="$2"

    # Always use current AIDE database as attachment when attachments are requested
    local attachment_path=""
    if [[ "$SEND_DB_ATTACHMENT" == "true" ]]; then
        attachment_path="$OLD_DB"
    fi

    [[ "$QUIET" != "true" ]] && echo "Sending email: $subject"

    # Create temporary file for email content
    local temp_email
    temp_email=$(mktemp)

    # Build email headers
    {
        echo "Subject: $subject"
        echo "To: $EMAIL"
        echo "From: AIDE Maintenance <aide@$(hostname)>"
        echo "Date: $(date -R)"

        if [[ -n "$attachment_path" && -f "$attachment_path" ]]; then
            # MIME multipart email with attachment
            local boundary
            boundary="AIDE_BOUNDARY_$(date +%s)"
            echo "MIME-Version: 1.0"
            echo "Content-Type: multipart/mixed; boundary=\"$boundary\""
            echo ""
            echo "--$boundary"
            echo "Content-Type: text/plain; charset=UTF-8"
            echo "Content-Transfer-Encoding: 8bit"
            echo ""
            echo "$body"
            echo ""
            echo "--$boundary"
            echo "Content-Type: application/gzip"
            echo "Content-Transfer-Encoding: base64"
            echo "Content-Disposition: attachment; filename=\"$(basename "$attachment_path")\""
            echo ""
            base64 "$attachment_path"
            echo ""
            echo "--$boundary--"
        else
            # Simple text email
            echo ""
            echo "$body"
        fi
    } >"$temp_email"

    # Send email using available method
    local email_sent=false

    # Try modern SMTP methods first
    if [[ -n "$SMTP_SERVER" ]]; then
        if command -v curl >/dev/null 2>&1; then
            local smtp_url="smtp://$SMTP_SERVER:$SMTP_PORT"
            local curl_cmd
            curl_cmd="curl -s --url '$smtp_url' --mail-from 'aide@$(hostname)' --mail-rcpt '$EMAIL'"

            if [[ -n "$SMTP_USER" && -n "$SMTP_PASS" ]]; then
                curl_cmd="$curl_cmd --user '$SMTP_USER:$SMTP_PASS'"
            fi

            if eval "$curl_cmd --upload-file '$temp_email'"; then
                email_sent=true
            fi
        elif command -v msmtp >/dev/null 2>&1; then
            if msmtp --host="$SMTP_SERVER" --port="$SMTP_PORT" "$EMAIL" <"$temp_email"; then
                email_sent=true
            fi
        fi
    fi

    # Fallback to traditional mail methods
    if [[ "$email_sent" == false ]]; then
        if command -v mail >/dev/null 2>&1; then
            if [[ -n "$attachment_path" && -f "$attachment_path" ]]; then
                # Try to use mail with attachment support
                if mail -s "$subject" -a "$attachment_path" "$EMAIL" <<<"$body"; then
                    email_sent=true
                fi
            else
                if mail -s "$subject" "$EMAIL" <<<"$body"; then
                    email_sent=true
                fi
            fi
        elif command -v sendmail >/dev/null 2>&1; then
            if sendmail -t <"$temp_email"; then
                email_sent=true
            fi
        elif [[ -x /usr/sbin/sendmail ]]; then
            if /usr/sbin/sendmail -t <"$temp_email"; then
                email_sent=true
            fi
        fi
    fi

    # Clean up
    rm -f "$temp_email"

    if [[ "$email_sent" == false ]]; then
        echo "Failed to send email. No working mail method found." >&2
        return 1
    fi

    return 0
}

# Function to handle failures
fail() {
    local msg="$1"
    echo "$msg" >&2
    if [[ -n "$EMAIL" ]]; then
        send_email "AIDE check failed" "AIDE maintenance script failed with the following error:

$msg

Host: $(hostname)
Time: $(date)
Script: $0"
    fi
    exit 1
}

# Determine compression for backups
determine_compression

# Set up backup database path
BACKUP_DB="/var/lib/aide/aide-$TIMESTAMP.db.$EXT"
COMPRESSED_LOG_FILE="$LOG_FILE.$EXT"

# Main execution
[[ "$QUIET" != "true" ]] && echo "Running AIDE check..."
{
    echo ""
    echo "===================== AIDE Check Log - $(date) ===================="
    echo ""
} >>"$LOG_FILE"

aide --check >>"$LOG_FILE" 2>&1 || true

{
    echo ""
    echo "===================== AIDE Update Log - $(date) ===================="
    echo ""
} >>"$LOG_FILE"

[[ "$QUIET" != "true" ]] && echo "Updating AIDE database..."

# # Update database
aide --update >>"$LOG_FILE" 2>&1 || true

[[ "$QUIET" != "true" ]] && echo "AIDE database check and update complete."

# Compress log file
[[ "$QUIET" != "true" ]] && echo "Compressing log file..."
if ! eval "$COMPRESS" "'$LOG_FILE'" >"$COMPRESSED_LOG_FILE"; then
    fail "Failed to compress log file."
fi
rm -f "$LOG_FILE"

[[ "$QUIET" != "true" ]] && echo "Compressed log saved to $COMPRESSED_LOG_FILE"

# Backup old database
[[ "$QUIET" != "true" ]] && echo "Backing up old database..."
if [[ -f "$OLD_DB" ]]; then
    # Decompress and recompress to ensure backup uses current compression
    if ! eval "$DECOMPRESS" "'$OLD_DB'" | eval "$COMPRESS" >"$BACKUP_DB"; then
        fail "Failed to backup old DB (recompress)."
    fi
    [[ "$QUIET" != "true" ]] && echo "Old database backed up to $BACKUP_DB"
else
    fail "Old DB not found."
fi

# Check if new database exists
if [[ ! -f "$NEW_DB" ]]; then
    fail "New DB not found."
fi

# Replace old database with new database
[[ "$QUIET" != "true" ]] && echo "Replacing old database with new database..."
if ! mv "$NEW_DB" "$OLD_DB"; then
    fail "Failed to move new DB to current."
fi

# Email results
if [[ -n "$EMAIL" ]]; then
    [[ "$QUIET" != "true" ]] && echo "Preparing to email results to $EMAIL"

    # Build email body
    email_body="AIDE maintenance script completed successfully.

Host: $(hostname)
Time: $(date)
Script: $0
Log File: $COMPRESSED_LOG_FILE
Backup DB: $BACKUP_DB

"
    # Get log content for email body
    decompress_cmd="$(determine_decompression "$COMPRESSED_LOG_FILE")"
    log_content="$(eval "$decompress_cmd" "'$COMPRESSED_LOG_FILE'" 2>/dev/null || echo "Failed to decompress log.")"
    email_body="${email_body}Log Content:
$log_content"

    # Send email (attachment will be included automatically if SEND_DB_ATTACHMENT is true)
    send_email "AIDE check completed" "$email_body"
fi

[[ "$QUIET" != "true" ]] && echo "AIDE check and update completed successfully."
[[ "$QUIET" != "true" ]] && echo "Log: $COMPRESSED_LOG_FILE"
[[ "$QUIET" != "true" ]] && echo "Old DB backed up to: $BACKUP_DB"
