#!/bin/bash

# Docblock
: <<'DOCBLOCK'
= Script: network_monitor.sh

== Description:
This script is designed to monitor the connectivity to specified IP addresses within a local network.
It pings the IPs at configurable intervals and sends notifications via Telegram for status changes.

== Usage:
- Make the script executable: `chmod +x pingdong.sh`
- Run in the background: `nohup ./pingdong.sh &`
- Configuration is set via environment variables in `.env` file.

== Environment Variables (in .env):
- PING_INTERVAL: Time in seconds between each ping attempt.
- IP_ADDRESSES: Space-separated list of IP addresses to ping.
- TELEGRAM_BOT_TOKEN: The token for your Telegram bot.
- TELEGRAM_CHAT_ID: The chat ID where notifications will be sent.
- DEBUG_MODE: Boolean for debug output (true or false).

== Functions:
- notify_telegram: Sends a message to Telegram using the bot API.
- monitor_ip: Performs the actual monitoring and notification logic.

== Notes:
- Ensure `jq` is installed for JSON parsing in the Telegram notification function.
- This script assumes it runs with sufficient permissions to execute ping and other commands.
DOCBLOCK

# Source the environment variables
if [[ -f .env ]]; then
    source .env
else
    echo "Error: Configuration file .env not found. Exiting."
    exit 1
fi

# Array to store IP addresses
declare -a ip_addresses=($IP_ADDRESSES)

# State variables for each IP address
declare -A ip_status

# Function to monitor an IP address
monitor_ip() {
    local ip=$1
    if ping -c 1 -w 3 "$ip" &> /dev/null; then
        if [[ ${ip_status[$ip]} == "down" ]]; then
            ip_status[$ip]="up"
            notify_telegram "✅ Connectivity restored to IP: $ip"
        fi
    else
        if [[ ${ip_status[$ip]} != "down" ]]; then
            ip_status[$ip]="down"
            notify_telegram "❌ Lost connectivity to IP: $ip"
        fi
    fi
}

# Function to periodically check all IPs and send status updates
check_ips() {
    local now=$(date +%s)
    for ip in "${ip_addresses[@]}"; do
        monitor_ip "$ip"
    done

    # Check if 24 hours have passed since last notification
    if [[ -z $LAST_NOTIFICATION_TIME ]] || (( now - LAST_NOTIFICATION_TIME > 86400 )); then
        notify_telegram "✅ Monitoring is active. All IPs are being checked every $PING_INTERVAL seconds."
        LAST_NOTIFICATION_TIME=$now
    fi
}

# Function to send a notification to a Telegram bot
notify_telegram() {
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
        local message="$1"
        local header='<pre style="background-color: #f0f0f0; color: #333; padding: 10px; border-left: 5px solid #007bff; font-weight: bold;">🚀 MiniLaunch Notification</pre>'
        local full_message="${header}${message}"
        local url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
        local params="chat_id=${TELEGRAM_CHAT_ID}&text=$(echo "${full_message}" | jq -sRr @uri)&parse_mode=HTML"
        local response=$(curl -s -X POST "${url}" -d "${params}")
        if [ "$DEBUG_MODE" = true ]; then
            if [[ $(echo "$response" | jq -r '.ok') == "true" ]]; then
                echo "Telegram notification sent successfully."
            else
                echo "Failed to send Telegram notification. Error: $(echo "$response" | jq -r '.description')"
            fi
        fi
    fi
}

# Initial notification
notify_telegram "🔍 Starting network monitoring for IPs: ${ip_addresses[*]}"

# Set initial status for all IPs
for ip in "${ip_addresses[@]}"; do
    ip_status[$ip]="up"
done

# Main loop to keep the script running
while true; do
    check_ips
    sleep $PING_INTERVAL
done

# Note: This script will run indefinitely until terminated with a signal (like SIGINT or SIGTERM)