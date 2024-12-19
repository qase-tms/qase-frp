#!/bin/bash

set -o nounset
set -o pipefail
set -e

FRP_SERVER="${FRP_SERVER:-frps.qase.io}"
TUNNEL_HOST_SUFFIX="${TUNNEL_HOST_SUFFIX:-qase.frp}"

# Function to fetch the latest frp download URL dynamically
get_latest_frpc_url() {
    local os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    local arch="$(uname -m)"

    case "$arch" in
        x86_64) arch="amd64" ;;
        arm64|aarch64) arch="arm64" ;;
        arm*) arch="arm" ;;
        *) echo "Unsupported architecture: $arch"; exit 1 ;;
    esac

    # Use GitHub API to fetch the latest release assets
    local api_url="https://api.github.com/repos/fatedier/frp/releases/latest"

    # Fetch the download URL for the correct OS and arch
    download_url=$(curl -s $api_url | grep -o "https://.*frp_.*_${os}_${arch}.tar.gz" | head -n 1)

    if [[ -z "$download_url" ]]; then
        echo "Error: Could not fetch the latest release URL for frp."
        exit 1
    fi

    echo "$download_url"
}

# Function to check if a parameter exists in a list of arguments
has_param() {
    local term="$1"
    shift
    for arg; do
        if [[ $arg == "$term" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to ensure frpc binary is downloaded
ensure_frpc() {
  # Check if frpc exists and download it if not
  if [[ ! -f "frpc" ]]; then
      echo "frpc binary not found. Downloading the latest release..."

      # Fetch latest frp URL
      release_url=$(get_latest_frpc_url)
      echo "Downloading frpc from: $release_url"

      # Download and extract the frpc binary
      curl -L -o frp.tar.gz "$release_url"
      tar -tzf frp.tar.gz | grep '/frpc$' | xargs -I {} tar -xzf frp.tar.gz --strip-components=1 {}
      rm frp.tar.gz

      # Make the binary executable
      chmod +x frpc
      echo "frpc downloaded and ready to use!"
  fi
}

# Function to write the frpc configuration
write_fprc_config() {
  # get random string
  uniq=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1 || true)
  # replace all characters except a-z, A-Z, 0-9, - with -
  proxy_name=$(echo -n "${hostname}" | tr -c 'a-zA-Z0-9-' '-')-$uniq

    # Write configuration to frpc.toml
    cat > frpc.toml <<EOF
serverAddr = "${FRP_SERVER}"
serverPort = 7002
auth.method = "token"
auth.token = "${auth_token}"
transport.poolCount = 50
transport.protocol = "quic"
udpPacketSize = 1500
transport.tls.enable = false

[[proxies]]
name = "${proxy_name}"
type = "http"
localIP = "${local_ip}"
localPort = ${local_port}
subdomain = "${proxy_name}"
hostHeaderRewrite = "${hostname}"
requestHeaders.set.x-forwarded-host = "${hostname}"
EOF

    echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
    echo "Please, specify the following URL in your Environment for Cloud Test Run: "
    echo "https://${proxy_name}.${TUNNEL_HOST_SUFFIX}/"
    echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
}

# Show help if no arguments provided
if [[ $# -eq 0 ]]; then
    echo "Usage: ./frp.sh hostname:port [auth_token]"
    echo "  hostname - your private website hostname"
    echo "  port - your private website port, you can skip it if it's 80"
    echo "  auth_token - your authentication token, you can skip it if you already have frpc.toml"
    echo "Options:"
    echo "  --help    Show this help message"
    exit 1
fi

ensure_frpc

if [[ -f "frpc.toml" ]]; then
  # Fetch current auth token from frpc.toml
  auth_token=$(grep 'auth.token' frpc.toml | sed -E 's/.*auth\.token *= *"([^"]+)".*/\1/')
else
  auth_token=${2:-}
  if [[ -z "$auth_token" ]]; then
    read -p "Enter your authentication token: " auth_token
  fi
fi

# Parse hostname and port
hostname_port=$1
if [[ $hostname_port == *":"* ]]; then
  IFS=":" read -r hostname local_port <<< "$hostname_port"
else
  hostname=$hostname_port
  local_port=80
fi

# Check if hostname is an IP address
if [[ $hostname =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  local_ip=$hostname
else
  # Find IP address of the hostname
  local_ip=$(awk -v host="$hostname" '$2 == host { print $1 }' /etc/hosts | head -n 1)
  if [[ -z "$local_ip" ]]; then
    local_ip=$(host $hostname | awk '/has address/ { print $4 ; exit }' || true)
  fi
  if [[ -z "$local_ip" ]]; then
    echo "Error: Could not resolve the IP address of the hostname: $hostname"
    exit 1
  fi
fi

# Write frpc configuration
write_fprc_config

# Run frpc
echo "Starting frpc with frpc.toml... Use Ctrl+C to stop."
./frpc -c frpc.toml
