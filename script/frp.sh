#!/bin/bash

set -o nounset
set -o pipefail
set -e

FRP_SERVER="${FRP_SERVER:-frps.qase.io}"
TUNNEL_HOST_SUFFIX="${TUNNEL_HOST_SUFFIX:-qase.frp}"

local_hostname=''
tunnel_name=''
auth_token=''
use_tcp=false
use_https=false

print_usage() {
  echo "Usage: $0 -l local_hostname[:local_port] [-a auth_token] [-t tunnel_name] [-c] [-s] [-h]"
  echo "Options:"
  echo "  -h  Show this help message and exit"
  echo "  -l  Local hostname and port to tunnel (e.g. private.website.local:8080)"
  echo "  -a  Authentication token for frp server. If not provided, it will be taken from frpc.toml or asked interactively."
  echo "  -t  Tunnel name to use for the hostname (default: random). It will be a part of the environment URL for Qase and it should be unique."
  echo "  -c  Use TCP protocol instead of QUIC"
  echo "  -s  Connect to backend using HTTPS (auto-detected for port 443)"
  exit 1
}

while getopts 'l:a:t:csh' flag; do
  case "${flag}" in
    l) local_hostname="${OPTARG}" ;;
    a) auth_token="${OPTARG}" ;;
    t) tunnel_name="${OPTARG}" ;;
    c) use_tcp=true ;;
    s) use_https=true ;;
    *) print_usage ;;
  esac
done

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
  if [[ -z "$tunnel_name" ]]; then
    # get random string
    uniq=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1 || true)
    # replace all characters except a-z, A-Z, 0-9, - with -
    proxy_name=$(echo -n "${hostname}" | tr -c 'a-zA-Z0-9-' '-')-$uniq
  else
    proxy_name=$tunnel_name
  fi

    # Write configuration to frpc.toml
    protocol="quic"
    server_port=7002
    if [[ "$use_tcp" == true ]]; then
        protocol="tcp"
        server_port=7000
    fi

    # Determine if we need http2https plugin (for HTTPS backends)
    if [[ "$local_port" -eq 443 ]] || [[ "$use_https" == true ]]; then
        cat > frpc.toml <<EOF
serverAddr = "${FRP_SERVER}"
serverPort = ${server_port}
metadatas.token = "${auth_token}"
transport.poolCount = 50
transport.protocol = "${protocol}"
udpPacketSize = 1500
transport.tls.enable = false

[[proxies]]
name = "${proxy_name}"
type = "http"
subdomain = "${proxy_name}"
transport.useEncryption = true
transport.useCompression = true

[proxies.plugin]
type = "http2https"
localAddr = "${local_ip}:${local_port}"
hostHeaderRewrite = "${hostname}"
requestHeaders.set.x-forwarded-host = "${hostname}"
EOF
    else
        cat > frpc.toml <<EOF
serverAddr = "${FRP_SERVER}"
serverPort = ${server_port}
metadatas.token = "${auth_token}"
transport.poolCount = 50
transport.protocol = "${protocol}"
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
transport.useEncryption = true
transport.useCompression = true
EOF
    fi

    echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
    echo "Please, specify the following URL in your Environment for Cloud Test Run: "
    echo "https://${proxy_name}.${TUNNEL_HOST_SUFFIX}/"
    echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
}

ensure_frpc

if [[ -z "$auth_token" ]]; then
  if [[ -f "frpc.toml" ]]; then
    # Fetch current auth token from frpc.toml
    auth_token=$(grep 'metadatas.token' frpc.toml | sed -E 's/.*auth\.token *= *"([^"]+)".*/\1/')
  else
    if [[ -z "$auth_token" ]]; then
      read -p "Enter your authentication token: " auth_token
    fi
  fi
fi

# Parse hostname and port
if [[ $local_hostname == *":"* ]]; then
  IFS=":" read -r hostname local_port <<< "$local_hostname"
else
  hostname=$local_hostname
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
