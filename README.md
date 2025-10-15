# SSL Certificate Expiration Checker

A bash script that reads a JSON file containing hostnames and checks their SSL certificate expiration dates using OpenSSL.

## Features

- ✅ Reads hostnames from JSON files
- ✅ Checks SSL certificate expiration dates
- ✅ Shows days remaining until expiration
- ✅ Color-coded output (green for valid, yellow for expiring soon, red for expired)
- ✅ Configurable port and timeout settings
- ✅ Cross-platform compatibility (macOS, Linux, Unix)
- ✅ POSIX shell compatibility (works with `sh` on any Unix-like system)
- ✅ Error handling for network issues and invalid certificates

## Requirements

### Option 1: Docker (Recommended)

- Docker and Docker Compose installed on your system
- No additional dependencies required

### Option 2: Local Installation

- `sh` (POSIX shell - available on all Unix-like systems)
- `openssl` (for SSL certificate checking)
- `jq` (for JSON parsing)
- `date` command (for date calculations)

#### Installation on macOS

```bash
# Install jq if not already installed
brew install jq

# Install coreutils for timeout command (optional)
brew install coreutils
```

**Note**: The script uses POSIX `sh` which is available by default on macOS. No additional shell installation is required.

#### Installation on Ubuntu/Debian

```bash
# Install required packages
sudo apt-get update
sudo apt-get install openssl jq coreutils
```

**Note**: The script uses POSIX `sh` which is available by default on Ubuntu/Debian. No additional shell installation is required.

#### Installation on CentOS/RHEL

```bash
# Install required packages
sudo yum install openssl jq coreutils
```

**Note**: The script uses POSIX `sh` which is available by default on CentOS/RHEL. No additional shell installation is required.

## Usage

### Docker Usage (Recommended)

#### Quick Start with Docker Compose

```bash
# Build and run with sample data
docker-compose up --build

# Run with your own JSON file
docker-compose run --rm ssl-checker /app/data/your_hostnames.json

# Run with custom options
docker-compose run --rm ssl-checker /app/data/your_hostnames.json -p 8443 -t 30
```

#### Manual Docker Commands

```bash
# Build the Docker image
docker build -t ssl-checker .

# Run with sample data
docker run --rm -v $(pwd):/app/data ssl-checker /app/data/sample_hostnames.json

# Run with your own JSON file
docker run --rm -v $(pwd):/app/data ssl-checker /app/data/your_hostnames.json

# Run with custom options
docker run --rm -v $(pwd):/app/data ssl-checker /app/data/your_hostnames.json -p 8443 -t 30

# Interactive shell for debugging
docker run --rm -it -v $(pwd):/app/data ssl-checker /bin/bash
```

### Local Usage

#### Basic Usage

```bash
./ssl_checker.sh <json_file>
```

#### Advanced Usage

```bash
./ssl_checker.sh <json_file> [options]

Options:
  -h, --help     Show help message
  -p, --port     Specify port number (default: 443)
  -t, --timeout  Specify timeout in seconds (default: 10)
```

#### Examples

```bash
# Check certificates on default port 443
./ssl_checker.sh hostnames.json

# Check certificates on port 8443 with 30-second timeout
./ssl_checker.sh hostnames.json -p 8443 -t 30

# Show help
./ssl_checker.sh --help
```

## JSON File Format

The JSON file should contain a root object with global settings and a `hostnames` array. This structure allows you to define common fields (like Teams URL and owner) once for all hostnames:

```json
{
  "teams_url": "https://teams.microsoft.com/l/channel/...",
  "owner": "IT Security Team",
  "hostnames": [
    {
      "hostname": "example.com",
      "description": "Main website",
      "category": "production",
      "priority": "high",
      "environment": "production"
    },
    {
      "hostname": "api.example.com",
      "description": "API server",
      "category": "production",
      "priority": "medium",
      "environment": "production"
    },
    {
      "hostname": "test.example.com",
      "description": "Test environment",
      "category": "testing",
      "priority": "low",
      "environment": "staging"
    }
  ]
}
```

### Field Descriptions

#### Global Fields (at root level)
| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `teams_url` | ❌ No | Microsoft Teams channel URL (shared by all hostnames) | `"https://teams.microsoft.com/l/channel/..."` |
| `owner` | ❌ No | Team or person responsible (shared by all hostnames) | `"IT Security Team"` |

#### Hostname Fields (within hostnames array)
| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `hostname` | ✅ Yes | The domain name to check | `"example.com"` |
| `description` | ❌ No | Human-readable description | `"Main website"` |
| `category` | ❌ No | Category or type of service | `"production"`, `"development"`, `"testing"` |
| `priority` | ❌ No | Priority level (color-coded in output) | `"high"`, `"medium"`, `"low"` |
| `environment` | ❌ No | Environment type | `"production"`, `"staging"`, `"test"` |

### Backward Compatibility

The script also supports the old format for backward compatibility:

```json
[
  {
    "hostname": "example.com",
    "description": "Main website",
    "teams_url": "https://teams.microsoft.com/l/channel/...",
    "owner": "IT Team"
  }
]
```

**Note**: Only the `hostname` field is required. All other fields are optional and will be displayed if present in the JSON.

## Output

The script provides color-coded output:

- 🟢 **Green**: Certificate is valid and has more than 30 days remaining
- 🟡 **Yellow**: Certificate expires within 30 days (warning)
- 🔴 **Red**: Certificate has expired

### Example Output

```
SSL Certificate Expiration Checker
===================================
JSON file: hostnames.json
Port: 443
Timeout: 10s

Checking SSL certificate for: google.com
  Description: Google main site
  Category: search
  Owner: IT Security Team
  Priority: high
  Environment: production
  Teams URL: https://teams.microsoft.com/l/channel/...
  ✓ Certificate expires: Mon Dec 15 09:40:35 CET 2025
    Days remaining: 61

Checking SSL certificate for: github.com
  Description: GitHub
  Category: development
  Owner: IT Security Team
  Priority: medium
  Environment: production
  Teams URL: https://teams.microsoft.com/l/channel/...
  ✓ Certificate expires: Fri Feb  6 00:59:59 CET 2026
    Days remaining: 114

Checking SSL certificate for: expired.badssl.com
  Description: Test expired certificate
  Category: test
  Owner: IT Security Team
  Priority: high
  Environment: test
  Teams URL: https://teams.microsoft.com/l/channel/...
  ✗ Certificate expired: Mon Jan  1 00:00:00 CET 2020
    Days expired: 1234

Checked 3 hostname(s)
```

## Error Handling

The script handles various error conditions:

- **Invalid JSON format**: Shows error message and exits
- **Missing hostname fields**: Shows error message and exits
- **Network connectivity issues**: Shows detailed error message
- **Invalid hostnames**: Shows connection error
- **SSL/TLS problems**: Shows certificate retrieval error
- **Missing dependencies**: Shows installation instructions

## Troubleshooting

### Common Issues

1. **"jq command not found"**
   - Install jq using your package manager (see Requirements section)

2. **"openssl command not found"**
   - Install OpenSSL using your package manager

3. **"Could not connect to hostname:port"**
   - Check if the hostname is correct
   - Verify network connectivity
   - Check if the port is correct
   - Ensure firewall allows the connection

4. **"Invalid JSON format"**
   - Validate your JSON file using an online JSON validator
   - Ensure the file contains an array of objects with `hostname` fields

### Docker Issues

1. **"Docker command not found"**
   - Install Docker Desktop or Docker Engine on your system
   - Ensure Docker is running

2. **"Permission denied" when mounting volumes**
   - On Linux: Add your user to the docker group: `sudo usermod -aG docker $USER`
   - On macOS/Windows: Ensure Docker Desktop has proper permissions

3. **"No such file or directory" for JSON file**
   - Ensure the JSON file exists in the current directory
   - Check the file path is correct (use absolute path if needed)

4. **Container exits immediately**
   - Check if the JSON file path is correct
   - Verify the JSON file format is valid
   - Use interactive mode for debugging: `docker run --rm -it -v $(pwd):/app/data ssl-checker /bin/bash`

### Debug Mode

#### Local Debug

To debug connection issues, you can test individual hostnames manually:

```bash
# Test a single hostname
openssl s_client -connect example.com:443 -servername example.com < /dev/null 2>/dev/null | openssl x509 -noout -dates
```

#### Docker Debug

```bash
# Run interactive container for debugging
docker run --rm -it -v $(pwd):/app/data ssl-checker /bin/bash

# Inside the container, test manually
openssl s_client -connect example.com:443 -servername example.com < /dev/null 2>/dev/null | openssl x509 -noout -dates

# Test the script directly
/app/ssl_checker.sh /app/data/sample_hostnames.json
```

## License

This script is provided as-is for educational and practical purposes.

## Contributing

Feel free to submit issues and enhancement requests!