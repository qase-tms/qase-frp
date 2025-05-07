# FRP tunnel setup script for Windows
# PowerShell equivalent of frp.sh

# Set error action preference to stop on errors
$ErrorActionPreference = "Stop"

# Default settings
$FRP_SERVER = if ($env:FRP_SERVER) { $env:FRP_SERVER } else { "frps.qase.io" }
$TUNNEL_HOST_SUFFIX = if ($env:TUNNEL_HOST_SUFFIX) { $env:TUNNEL_HOST_SUFFIX } else { "qase.frp" }

# Initialize variables
$local_hostname = ""
$tunnel_name = ""
$auth_token = ""

function Print-Usage {
    Write-Host "Usage: .\frp.ps1 -LocalHostname local_hostname[:local_port] [-AuthToken auth_token] [-TunnelName tunnel_name]"
    Write-Host "Options:"
    Write-Host "  -LocalHostname   Local hostname and port to tunnel (e.g. private.website.local:8080)"
    Write-Host "  -AuthToken       Authentication token for frp server. If not provided, it will be taken from frpc.toml or asked interactively."
    Write-Host "  -TunnelName      Tunnel name to use for the hostname (default: random). It will be a part of the environment URL for Qase and it should be unique."
    exit 1
}

# Parse command line arguments
param(
    [Parameter(Mandatory=$false)][string]$LocalHostname,
    [Parameter(Mandatory=$false)][string]$AuthToken,
    [Parameter(Mandatory=$false)][string]$TunnelName,
    [Parameter(Mandatory=$false)][switch]$Help
)

if ($Help) {
    Print-Usage
}

if (-not $LocalHostname) {
    Print-Usage
}

$local_hostname = $LocalHostname
if ($AuthToken) { $auth_token = $AuthToken }
if ($TunnelName) { $tunnel_name = $TunnelName }

# Function to fetch the latest frp download URL dynamically
function Get-LatestFrpcUrl {
    # Determine OS and architecture
    $os = "windows"
    $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "386" }
    
    # Check for ARM architecture
    if ($env:PROCESSOR_ARCHITECTURE -like '*ARM*' -or $env:PROCESSOR_IDENTIFIER -like '*ARM*') {
        if ([Environment]::Is64BitOperatingSystem) {
            $arch = "arm64"
        } else {
            $arch = "arm"
        }
    }

    # Use GitHub API to fetch the latest release assets
    $api_url = "https://api.github.com/repos/fatedier/frp/releases/latest"
    
    try {
        $response = Invoke-RestMethod -Uri $api_url -ErrorAction Stop
        $assets = $response.assets | Where-Object { $_.browser_download_url -like "*frp_*_${os}_${arch}.zip" }
        
        if ($assets) {
            return $assets[0].browser_download_url
        } else {
            Write-Host "Error: Could not find frp release for $os $arch"
            exit 1
        }
    } catch {
        Write-Host "Error: Could not fetch the latest release URL for frp. $_"
        exit 1
    }
}

# Function to ensure frpc binary is downloaded
function Ensure-Frpc {
    # Check if frpc.exe exists and download it if not
    if (-not (Test-Path "frpc.exe")) {
        Write-Host "frpc binary not found. Downloading the latest release..."

        # Fetch latest frp URL
        $release_url = Get-LatestFrpcUrl
        Write-Host "Downloading frpc from: $release_url"

        # Create a temporary directory
        $temp_dir = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
        New-Item -ItemType Directory -Path $temp_dir -Force | Out-Null
        
        # Download and extract the frpc binary
        $zip_file = "$temp_dir\frp.zip"
        Invoke-WebRequest -Uri $release_url -OutFile $zip_file
        
        # Extract the ZIP file
        Expand-Archive -Path $zip_file -DestinationPath $temp_dir
        
        # Find the frpc.exe in the extracted directory
        $frpc_path = Get-ChildItem -Path $temp_dir -Recurse -Filter "frpc.exe" | Select-Object -First 1 -ExpandProperty FullName
        
        # Copy frpc.exe to the current directory
        Copy-Item -Path $frpc_path -Destination "frpc.exe"
        
        # Clean up
        Remove-Item -Path $temp_dir -Recurse -Force
        
        Write-Host "frpc downloaded and ready to use!"
    }
}

# Function to write the frpc configuration
function Write-FrpcConfig {
    param (
        [string]$hostname,
        [string]$local_ip,
        [int]$local_port
    )

    if (-not $tunnel_name) {
        # Generate a random string for the proxy name
        $random = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
        # Replace all characters except a-z, A-Z, 0-9, - with -
        $hostname_clean = $hostname -replace '[^a-zA-Z0-9-]', '-'
        $proxy_name = "$hostname_clean-$random"
    } else {
        $proxy_name = $tunnel_name
    }

    # Write configuration to frpc.toml
    $config = @"
serverAddr = "$FRP_SERVER"
serverPort = 7002
metadatas.token = "$auth_token"
transport.poolCount = 50
transport.protocol = "quic"
udpPacketSize = 1500
transport.tls.enable = false

[[proxies]]
name = "$proxy_name"
type = "http"
localIP = "$local_ip"
localPort = $local_port
subdomain = "$proxy_name"
hostHeaderRewrite = "$hostname"
requestHeaders.set.x-forwarded-host = "$hostname"
transport.useEncryption = true
transport.useCompression = true
"@

    Set-Content -Path "frpc.toml" -Value $config

    Write-Host ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
    Write-Host "Please, specify the following URL in your Environment for Cloud Test Run: "
    Write-Host "https://$proxy_name.$TUNNEL_HOST_SUFFIX/"
    Write-Host ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
}

# Main script execution
Ensure-Frpc

if (-not $auth_token) {
    if (Test-Path "frpc.toml") {
        # Fetch current auth token from frpc.toml
        $toml_content = Get-Content "frpc.toml" -Raw
        if ($toml_content -match 'metadatas\.token\s*=\s*"([^"]+)"') {
            $auth_token = $matches[1]
        }
    }
    
    if (-not $auth_token) {
        $auth_token = Read-Host "Enter your authentication token"
    }
}

# Parse hostname and port
if ($local_hostname -match '(.+):(\d+)') {
    $hostname = $matches[1]
    $local_port = [int]$matches[2]
} else {
    $hostname = $local_hostname
    $local_port = 80
}

# Check if hostname is an IP address
if ($hostname -match '^\d+\.\d+\.\d+\.\d+$') {
    $local_ip = $hostname
} else {
    # Try to resolve the hostname
    try {
        $local_ip = (Resolve-DnsName -Name $hostname -ErrorAction Stop).IPAddress
        if (-not $local_ip) {
            throw "No IP address found"
        }
        if ($local_ip -is [array]) {
            $local_ip = $local_ip[0]
        }
    } catch {
        # Try to get the IP from the hosts file
        $hosts_file = "$env:windir\System32\drivers\etc\hosts"
        if (Test-Path $hosts_file) {
            $hosts_content = Get-Content $hosts_file
            foreach ($line in $hosts_content) {
                if ($line -match "^\s*(\d+\.\d+\.\d+\.\d+)\s+$hostname\s*") {
                    $local_ip = $matches[1]
                    break
                }
            }
        }
        
        if (-not $local_ip) {
            Write-Host "Error: Could not resolve the IP address of the hostname: $hostname"
            exit 1
        }
    }
}

# Write frpc configuration
Write-FrpcConfig -hostname $hostname -local_ip $local_ip -local_port $local_port

# Run frpc
Write-Host "Starting frpc with frpc.toml... Press Ctrl+C to stop."
& .\frpc.exe -c frpc.toml 