#!/bin/sh

# SSL Certificate Expiration Checker
# This script reads a JSON file containing hostnames and checks their SSL certificate expiration dates

set -eu

if [ -z "${CI_COMMIT_BRANCH}" ]; then
    # Running in a pipeline so no colors
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
else
    # Colors for output
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
fi

# Function to print usage
usage() {
    echo "Usage: $0 <json_file> [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -p, --port     Specify port number (default: 443)"
    echo "  -t, --timeout  Specify timeout in seconds (default: 10)"
    echo ""
    echo "JSON file format:"
    echo "  The JSON file should contain an array of objects with 'hostname' field"
    echo "  Example:"
    echo "  [{\"hostname\": \"example.com\", \"description\": \"Main site\"}, {\"hostname\": \"api.example.com\"}]"
    exit 1
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to send Microsoft Teams notification
send_teams_notification() {
    local teams_url="$1"
    local expiring_certs="$2"
    local owner="$3"
    
    if [ -z "$teams_url" ] || [ "$teams_url" = "null" ] || [ "$teams_url" = "" ]; then
        echo "${YELLOW}Warning: No Teams URL configured, skipping notification${NC}"
        return 0
    fi
    
    # Check if curl is available
    if ! command_exists curl; then
        echo "${RED}Error: curl command not found. Please install curl to send Teams notifications.${NC}"
        return 1
    fi
    
    # Create JSON payload for Teams
    local json_payload
    json_payload=$(cat <<EOF
{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "FF6B6B",
    "summary": "SSL Certificate Expiration Alert",
    "sections": [{
        "activityTitle": "🚨 SSL Certificate Expiration Alert",
        "activitySubtitle": "The following certificates are expiring in less than 30 days",
        "facts": [
            {
                "name": "Alert Time",
                "value": "$(date)"
            },
            {
                "name": "Owner",
                "value": "${owner:-Not specified}"
            },
            {
                "name": "Total Certificates",
                "value": "$(echo "$expiring_certs" | wc -l)"
            }
        ],
        "text": "**Expiring Certificates:**\n\n$expiring_certs",
        "markdown": true
    }]
}
EOF
)
    
    # Send notification to Teams
    echo "${BLUE}Sending Teams notification...${NC}"
    if curl -s -X POST -H "Content-Type: application/json" -d "$json_payload" "$teams_url" >/dev/null 2>&1; then
        echo "${GREEN}✓ Teams notification sent successfully${NC}"
    else
        echo "${RED}✗ Failed to send Teams notification${NC}"
        return 1
    fi
}

# Function to get certificate details for Teams notification
get_certificate_details() {
    local hostname="$1"
    local port="${2:-443}"
    local timeout="${3:-10}"
    local description="$4"
    local category="$5"
    local priority="$6"
    local environment="$7"
    
    # Get certificate information using openssl
    local cert_info
    if command_exists gtimeout; then
        cert_info=$(gtimeout "$timeout" openssl s_client -connect "$hostname:$port" -servername "$hostname" < /dev/null 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
    else
        cert_info=$(openssl s_client -connect "$hostname:$port" -servername "$hostname" -verify_return_error < /dev/null 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
    fi
    
    if [ -n "$cert_info" ]; then
        # Extract notAfter date
        local not_after
        not_after=$(echo "$cert_info" | grep "notAfter" | cut -d= -f2)
        
        if [ -n "$not_after" ]; then
            # Convert to epoch time for calculation
            local expiry_epoch
            expiry_epoch=$(date -d "$not_after" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" +%s 2>/dev/null)
            
            if [ -n "$expiry_epoch" ]; then
                current_epoch=$(date +%s)
                days_left=$(expr \( $expiry_epoch - $current_epoch \) / 86400)
                formatted_date=$(date -d "$not_after" 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" 2>/dev/null)
                
                # Return certificate details if expiring in less than 30 days
                if [ $days_left -le 30 ]; then
                    local cert_details="• **$hostname**"
                    if [ -n "$description" ] && [ "$description" != "null" ]; then
                        cert_details="$cert_details - $description"
                    fi
                    if [ $days_left -gt 0 ]; then
                        cert_details="$cert_details\n  - ⚠️ Expires in $days_left days ($formatted_date)"
                    else
                        local days_expired=$(expr 0 - $days_left)
                        cert_details="$cert_details\n  - ❌ EXPIRED $days_expired days ago ($formatted_date)"
                    fi
                    if [ -n "$priority" ] && [ "$priority" != "null" ]; then
                        cert_details="$cert_details\n  - Priority: $priority"
                    fi
                    if [ -n "$environment" ] && [ "$environment" != "null" ]; then
                        cert_details="$cert_details\n  - Environment: $environment"
                    fi
                    echo "$cert_details"
                fi
            fi
        fi
    fi
}

# Function to check SSL certificate expiration
check_ssl_expiration() {
    local hostname="$1"
    local port="${2:-443}"
    local timeout="${3:-10}"
    local description="$4"
    local category="$5"
    local teams_url="$6"
    local owner="$7"
    local priority="$8"
    local environment="$9"
    
    # Validate hostname
    if [ -z "$hostname" ] || [ "$hostname" = "" ]; then
        echo "${RED}Error: Empty or invalid hostname${NC}"
        return 1
    fi
    
    # Check if openssl is available
    if ! command_exists openssl; then
        echo "${RED}Error: openssl command not found. Please install OpenSSL.${NC}"
        return 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command_exists jq; then
        echo "${RED}Error: jq command not found. Please install jq for JSON parsing.${NC}"
        return 1
    fi
    
    echo "${BLUE}Checking SSL certificate for: ${hostname}${NC}"
    
    # Display additional information if available
    if [ -n "$description" ] && [ "$description" != "null" ]; then
        echo "  ${BLUE}Description: ${description}${NC}"
    fi
    if [ -n "$category" ] && [ "$category" != "null" ]; then
        echo "  ${BLUE}Category: ${category}${NC}"
    fi
    if [ -n "$owner" ] && [ "$owner" != "null" ]; then
        echo "  ${BLUE}Owner: ${owner}${NC}"
    fi
    if [ -n "$priority" ] && [ "$priority" != "null" ]; then
        # Color code priority
        case "$priority" in
            "high")
                echo "  ${RED}Priority: ${priority}${NC}"
                ;;
            "medium")
                echo "  ${YELLOW}Priority: ${priority}${NC}"
                ;;
            "low")
                echo "  ${GREEN}Priority: ${priority}${NC}"
                ;;
            *)
                echo "  ${BLUE}Priority: ${priority}${NC}"
                ;;
        esac
    fi
    if [ -n "$environment" ] && [ "$environment" != "null" ]; then
        echo "  ${BLUE}Environment: ${environment}${NC}"
    fi
    if [ -n "$teams_url" ] && [ "$teams_url" != "null" ]; then
        echo "  ${BLUE}Teams URL: ${teams_url}${NC}"
    fi
    
    # Get certificate information using openssl
    local cert_info
    # Use gtimeout if available (from coreutils), otherwise use a different approach
    if command_exists gtimeout; then
        cert_info=$(gtimeout "$timeout" openssl s_client -connect "$hostname:$port" -servername "$hostname" < /dev/null 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
    else
        # Fallback: use openssl with built-in timeout handling
        cert_info=$(openssl s_client -connect "$hostname:$port" -servername "$hostname" -verify_return_error < /dev/null 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
    fi
    
    if [ -n "$cert_info" ]; then
        # Extract notAfter date
        local not_after
        not_after=$(echo "$cert_info" | grep "notAfter" | cut -d= -f2)
        
        if [ -n "$not_after" ]; then
            # Convert to epoch time for calculation
            local expiry_epoch
            expiry_epoch=$(date -d "$not_after" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" +%s 2>/dev/null)
            
            if [ -n "$expiry_epoch" ]; then
                current_epoch=$(date +%s)
                
                # Calculate days left using expr for POSIX compatibility
                days_left=$(expr \( $expiry_epoch - $current_epoch \) / 86400)
                
                # Format the expiry date for display
                formatted_date=$(date -d "$not_after" 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" 2>/dev/null)
                
                if [ $days_left -gt 30 ]; then
                    echo "  ${GREEN}✓ Certificate expires: $formatted_date${NC}"
                    echo "  ${GREEN}  Days remaining: $days_left${NC}"
                    # Return 0 for non-expiring certificates
                    return 0
                elif [ $days_left -gt 0 ]; then
                    echo "  ${YELLOW}⚠ Certificate expires: $formatted_date${NC}"
                    echo "  ${YELLOW}  Days remaining: $days_left (WARNING: Expires soon!)${NC}"
                    # Return 1 for expiring certificates (less than 30 days)
                    return 1
                else
                    # Calculate days expired (positive number)
                    days_expired=$(expr 0 - $days_left)
                    echo "  ${RED}✗ Certificate expired: $formatted_date${NC}"
                    echo "  ${RED}  Days expired: $days_expired${NC}"
                    # Return 1 for expired certificates
                    return 1
                fi
            else
                echo "  ${RED}Error: Could not parse expiry date${NC}"
            fi
        else
            echo "  ${RED}Error: Could not extract expiry date from certificate${NC}"
        fi
    else
        echo "  ${RED}Error: Could not connect to $hostname:$port or retrieve certificate${NC}"
        echo "  ${RED}  This could be due to:${NC}"
        echo "  ${RED}    - Invalid hostname${NC}"
        echo "  ${RED}    - Network connectivity issues${NC}"
        echo "  ${RED}    - SSL/TLS connection problems${NC}"
        echo "  ${RED}    - Firewall blocking the connection${NC}"
    fi
    echo ""
}

# Function to extract global data (teams_url, owner) from JSON
extract_global_data() {
    local json_file="$1"
    
    if [ ! -f "$json_file" ]; then
        echo "${RED}Error: JSON file '$json_file' not found${NC}"
        exit 1
    fi
    
    # Check if jq is available
    if ! command_exists jq; then
        echo "${RED}Error: jq command not found. Please install jq for JSON parsing.${NC}"
        echo "${RED}  On macOS: brew install jq${NC}"
        echo "${RED}  On Ubuntu/Debian: sudo apt-get install jq${NC}"
        echo "${RED}  On CentOS/RHEL: sudo yum install jq${NC}"
        exit 1
    fi
    
    # Extract global data
    local global_data
    if ! global_data=$(jq -r '[.teams_url // "", .owner // ""] | @tsv' "$json_file" 2>/dev/null); then
        echo "${RED}Error: Invalid JSON format${NC}"
        echo "${RED}Expected JSON format with 'teams_url' and 'owner' at root level${NC}"
        exit 1
    fi
    
    echo "$global_data"
}

# Function to extract hostnames from JSON
extract_hostnames() {
    local json_file="$1"
    
    # Extract hostnames from JSON (support both old and new format)
    local hostnames
    if ! hostnames=$(jq -r '.hostnames[]?.hostname // .[]?.hostname // empty' "$json_file" 2>/dev/null); then
        echo "${RED}Error: Invalid JSON format or no 'hostname' fields found${NC}"
        echo "${RED}Expected JSON format with 'hostnames' array or direct array of objects${NC}"
        exit 1
    fi
    
    if [ -z "$hostnames" ]; then
        echo "${RED}Error: No hostnames found in JSON file${NC}"
        exit 1
    fi
    
    echo "$hostnames"
}

# Function to extract all data for a specific hostname
extract_hostname_data() {
    local json_file="$1"
    local hostname="$2"
    
    # Extract all fields for the specific hostname (support both old and new format)
    jq -r --arg hostname "$hostname" '
        (.hostnames[]? // .[]?) | 
        select(.hostname == $hostname) | 
        [
            .hostname // "",
            .description // "",
            .category // "",
            .priority // "",
            .environment // ""
        ] | @tsv
    ' "$json_file" 2>/dev/null
}

# Main function
main() {
    local json_file=""
    local port=443
    local timeout=10
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -p|--port)
                port="$2"
                shift 2
                ;;
            -t|--timeout)
                timeout="$2"
                shift 2
                ;;
            -*)
                echo -e "${RED}Error: Unknown option $1${NC}"
                usage
                ;;
            *)
                if [[ -z "$json_file" ]]; then
                    json_file="$1"
                else
                    echo -e "${RED}Error: Multiple JSON files specified${NC}"
                    usage
                fi
                shift
                ;;
        esac
    done
    
    # Check if JSON file is provided
    if [ -z "$json_file" ]; then
        echo "${RED}Error: JSON file not specified${NC}"
        usage
    fi
    
    # Validate port number (using case for POSIX compatibility)
    case "$port" in
        ''|*[!0-9]*) 
            echo "${RED}Error: Invalid port number. Must be between 1 and 65535${NC}"
            exit 1
            ;;
    esac
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "${RED}Error: Invalid port number. Must be between 1 and 65535${NC}"
        exit 1
    fi
    
    # Validate timeout
    case "$timeout" in
        ''|*[!0-9]*)
            echo "${RED}Error: Invalid timeout. Must be a positive integer${NC}"
            exit 1
            ;;
    esac
    if [ "$timeout" -lt 1 ]; then
        echo "${RED}Error: Invalid timeout. Must be a positive integer${NC}"
        exit 1
    fi
    
    echo "${BLUE}SSL Certificate Expiration Checker${NC}"
    echo "${BLUE}===================================${NC}"
    echo "JSON file: $json_file"
    echo "Port: $port"
    echo "Timeout: ${timeout}s"
    echo ""
    
    # Extract global data (teams_url, owner)
    global_data=$(extract_global_data "$json_file")
    IFS='	' read -r global_teams_url global_owner <<EOF
$global_data
EOF
    
    # Extract and process hostnames
    local hostnames
    hostnames=$(extract_hostnames "$json_file")
    
    # Variables to track expiring certificates
    local expiring_certs=""
    local has_expiring_certs=false
    local count=0
    
    while IFS= read -r hostname; do
        if [ -n "$hostname" ] && [ "$hostname" != "null" ]; then
            # Extract all data for this hostname
            hostname_data=$(extract_hostname_data "$json_file" "$hostname")
            
            if [ -n "$hostname_data" ]; then
                # Parse the TSV data
                IFS='	' read -r hname description category priority environment <<EOF
$hostname_data
EOF
                
                # Call the check function with all parameters (including global data)
                if ! check_ssl_expiration "$hname" "$port" "$timeout" "$description" "$category" "$global_teams_url" "$global_owner" "$priority" "$environment"; then
                    # Certificate is expiring or expired (return code 1)
                    has_expiring_certs=true
                    # Get certificate details for Teams notification
                    cert_details=$(get_certificate_details "$hname" "$port" "$timeout" "$description" "$category" "$priority" "$environment")
                    if [ -n "$cert_details" ]; then
                        if [ -n "$expiring_certs" ]; then
                            expiring_certs="$expiring_certs\n\n$cert_details"
                        else
                            expiring_certs="$cert_details"
                        fi
                    fi
                fi
            else
                # Fallback to basic check if data extraction fails
                if ! check_ssl_expiration "$hostname" "$port" "$timeout" "" "" "$global_teams_url" "$global_owner" "" ""; then
                    # Certificate is expiring or expired (return code 1)
                    has_expiring_certs=true
                    # Get certificate details for Teams notification
                    cert_details=$(get_certificate_details "$hostname" "$port" "$timeout" "" "" "" "")
                    if [ -n "$cert_details" ]; then
                        if [ -n "$expiring_certs" ]; then
                            expiring_certs="$expiring_certs\n\n$cert_details"
                        else
                            expiring_certs="$cert_details"
                        fi
                    fi
                fi
            fi
            count=$(expr $count + 1)
        fi
    done <<EOF
$hostnames
EOF
    
    echo "${BLUE}Checked $count hostname(s)${NC}"
    
    # Send Teams notification if there are expiring certificates
    if [ "$has_expiring_certs" = true ] && [ -n "$expiring_certs" ]; then
        echo ""
        echo "${YELLOW}⚠️  Found certificates expiring in less than 30 days!${NC}"
        send_teams_notification "$global_teams_url" "$expiring_certs" "$global_owner"
    else
        echo ""
        echo "${GREEN}✓ All certificates are valid for more than 30 days${NC}"
    fi
}

# Run main function with all arguments
main "$@"
