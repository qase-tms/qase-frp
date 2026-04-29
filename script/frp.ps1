param(
    [Parameter(Mandatory=$false)][string]$LocalHostname,
    [Parameter(Mandatory=$false)][string]$AuthToken,
    [Parameter(Mandatory=$false)][string]$TunnelName,
    [Parameter(Mandatory=$false)][switch]$UseTcp,
    [Parameter(Mandatory=$false)][switch]$UseHttps,
    [Parameter(Mandatory=$false)][switch]$RunDiagnose,
    [Parameter(Mandatory=$false)][switch]$Help
)

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
    Write-Host "Usage: .\frp.ps1 -LocalHostname local_hostname[:local_port] [-AuthToken auth_token] [-TunnelName tunnel_name] [-UseTcp] [-UseHttps] [-RunDiagnose]"
    Write-Host "Options:"
    Write-Host "  -LocalHostname   Local hostname and port to tunnel (e.g. private.website.local:8080)"
    Write-Host "  -AuthToken       Authentication token for frp server. If not provided, it will be taken from frpc.toml or asked interactively."
    Write-Host "  -TunnelName      Tunnel name to use for the hostname (default: random). It will be a part of the environment URL for Qase and it should be unique."
    Write-Host "  -UseTcp          Use TCP protocol instead of QUIC"
    Write-Host "  -UseHttps        Connect to backend using HTTPS (auto-detected for port 443)"
    Write-Host "  -RunDiagnose     Run pre-flight connectivity diagnostics and save a log file (default: off). Use this when frpc fails to forward traffic."
    exit 1
}

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
    # Check if frpc.exe exists locally, or in the script folder
    if (Test-Path "frpc.exe") {
        Write-Host "Using existing frpc.exe in current directory"
        return
    }
    
    $script_frpc = Join-Path (Get-Location).Path "script\frpc.exe"
    if (Test-Path $script_frpc) {
        Write-Host "Using existing frpc.exe from script folder"
        Copy-Item -Path $script_frpc -Destination "frpc.exe" -Force
        return
    }

    Write-Host "frpc binary not found. Downloading the latest release..."

    # Fetch latest frp URL
    $release_url = Get-LatestFrpcUrl
    Write-Host "Downloading frpc from: $release_url"

    try {
        # Create a temporary directory
        $temp_dir = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
        New-Item -ItemType Directory -Path $temp_dir -Force | Out-Null
        
        # Download and extract the frpc binary
        $zip_file = "$temp_dir\frp.zip"
        Write-Host "Downloading to: $zip_file"
        
        # Use TLS 1.2 to avoid security issues
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $release_url -OutFile $zip_file -UseBasicParsing
        
        if (-not (Test-Path $zip_file)) {
            throw "Failed to download the zip file to $zip_file"
        }
        
        Write-Host "Download complete. Extracting..."
        
        # Try alternative extraction method to avoid antivirus issues
        try {
            # Try extraction method 1: .NET ZipFile
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zip_file, $temp_dir)
        } catch {
            Write-Host "First extraction method failed, trying alternative method..."
            
            try {
                # Try extraction method 2: external command
                $shell = New-Object -ComObject Shell.Application
                $zip = $shell.NameSpace($zip_file)
                $destination = $shell.NameSpace($temp_dir)
                $destination.CopyHere($zip.Items())
            } catch {
                Write-Host "Second extraction method failed. Trying final method..."
                
                # Try extraction method 3: PowerShell command with -Force
                Expand-Archive -Path $zip_file -DestinationPath $temp_dir -Force
            }
        }
        
        # Find the frpc.exe in the extracted directory
        $frpc_files = Get-ChildItem -Path $temp_dir -Recurse -Filter "frpc.exe" -ErrorAction SilentlyContinue
        
        if ($frpc_files -and $frpc_files.Count -gt 0) {
            $frpc_path = $frpc_files[0].FullName
            if (Test-Path $frpc_path) {
                # Copy frpc.exe to the current directory
                Copy-Item -Path $frpc_path -Destination "frpc.exe" -Force
                Write-Host "frpc downloaded and ready to use!"
            } else {
                throw "frpc.exe was found but the path is not valid: $frpc_path"
            }
        } else {
            throw "Could not find frpc.exe in the extracted files"
        }
    } catch {
        Write-Host "Error: Failed to download or extract frpc. $_"
        Write-Host ""
        Write-Host "This could be due to your antivirus or Windows Defender blocking the file."
        Write-Host "Please consider the following options:"
        Write-Host "1. Temporarily disable your antivirus and try again"
        Write-Host "2. Add an exception for frpc.exe in your antivirus settings"
        Write-Host "3. Download frpc manually from https://github.com/fatedier/frp/releases"
        Write-Host "   and place it in the same directory as this script"
        exit 1
    } finally {
        # Clean up
        if (Test-Path $temp_dir) {
            Remove-Item -Path $temp_dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Connectivity diagnostic: runs before frpc starts so support has data when something fails.
# Each section explains WHAT it tests and HOW to interpret the result.
function Invoke-FrpcDiagnostics {
    param(
        [string]$TargetHost,
        [int]$TargetPort,
        [string]$TargetIp
    )

    # Native commands (curl.exe) emit stderr lines that PowerShell wraps as ErrorRecord;
    # with EAP=Stop the first one aborts the function. Switch to Continue locally so all
    # sections run, then restore.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    $logFile = "frp-diagnose-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $transcriptStarted = $false
    try { Start-Transcript -Path $logFile -Force | Out-Null; $transcriptStarted = $true } catch { }

    try {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "FRP backend connectivity diagnostic" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "Target:   ${TargetHost}:${TargetPort} (resolved -> $TargetIp)"
    Write-Host "Host:     $env:COMPUTERNAME"
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        Write-Host "OS:       $($os.Caption) ($($os.Version))"
        Write-Host "ProductType: $($os.ProductType)  (1=Workstation, 2=DC, 3=Server)"
    } catch { Write-Host "OS:       (unavailable)" }
    Write-Host "Date:     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host ""
    Write-Host "Each section below explains WHAT it tests and HOW to read the result." -ForegroundColor DarkGray
    Write-Host "If frpc fails to forward traffic, send the saved log to support." -ForegroundColor DarkGray

    # ---- 1. Source IP & route -----------------------------------------------
    Write-Host ""
    Write-Host "[1/7] Source IP and route to target" -ForegroundColor Cyan
    Write-Host "  Why: shows which local IP and gateway this machine uses to reach the" -ForegroundColor DarkGray
    Write-Host "       backend. Compare with the working machine - a different source IP" -ForegroundColor DarkGray
    Write-Host "       often means a different firewall rule applies." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Local IPv4 addresses:"
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceAlias -notmatch "Loopback|Pseudo" } |
        Select-Object IPAddress, InterfaceAlias, PrefixLength |
        Format-Table -AutoSize | Out-String | Write-Host
    Write-Host "Route to ${TargetIp}:"
    try {
        Find-NetRoute -RemoteIPAddress $TargetIp -ErrorAction Stop |
            Select-Object IPAddress, InterfaceAlias, NextHop, RouteMetric |
            Format-Table -AutoSize | Out-String | Write-Host
    } catch {
        Write-Host "  Find-NetRoute failed: $_" -ForegroundColor Red
    }

    # ---- 2. DNS configuration -----------------------------------------------
    Write-Host "[2/7] DNS configuration" -ForegroundColor Cyan
    Write-Host "  Why: if two machines use different DNS servers, they may resolve the" -ForegroundColor DarkGray
    Write-Host "       same hostname to different IPs and end up talking to different" -ForegroundColor DarkGray
    Write-Host "       backends. Compare resolution and DNS servers across machines." -ForegroundColor DarkGray
    Write-Host ""
    try {
        Resolve-DnsName -Name $TargetHost -ErrorAction Stop |
            Format-Table -AutoSize | Out-String | Write-Host
    } catch {
        Write-Host "  Resolve-DnsName failed: $_" -ForegroundColor Red
    }
    Write-Host "Configured DNS servers:"
    Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object ServerAddresses |
        Select-Object InterfaceAlias, ServerAddresses |
        Format-Table -AutoSize | Out-String | Write-Host
    Write-Host "Hosts file entries for ${TargetHost}:"
    $hostsFile = "$env:windir\System32\drivers\etc\hosts"
    $hostsMatch = Get-Content $hostsFile -ErrorAction SilentlyContinue | Select-String -Pattern ([regex]::Escape($TargetHost))
    if ($hostsMatch) { $hostsMatch | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Yellow } }
    else { Write-Host "  (no entries)" }

    # ---- 3. TCP reachability ------------------------------------------------
    Write-Host ""
    Write-Host "[3/7] TCP reachability ${TargetIp}:${TargetPort}" -ForegroundColor Cyan
    Write-Host "  Why: pure layer-4 test. If TCP cannot establish, no firewall rule allows" -ForegroundColor DarkGray
    Write-Host "       this server to talk to the backend on this port. If TCP succeeds but" -ForegroundColor DarkGray
    Write-Host "       later layers fail, the issue is above TCP (TLS, EDR, proxy)." -ForegroundColor DarkGray
    Write-Host ""
    try {
        $tcpResult = Test-NetConnection -ComputerName $TargetIp -Port $TargetPort -WarningAction SilentlyContinue
        $tcpResult | Format-List | Out-String | Write-Host
        if ($tcpResult.TcpTestSucceeded) {
            Write-Host "  RESULT: TCP $TargetPort open" -ForegroundColor Green
        } else {
            Write-Host "  RESULT: TCP $TargetPort UNREACHABLE - likely firewall/route" -ForegroundColor Red
        }
    } catch {
        Write-Host "  Test-NetConnection failed: $_" -ForegroundColor Red
    }

    # ---- 4. Plain HTTPS via curl --------------------------------------------
    Write-Host ""
    Write-Host "[4/7] Plain HTTPS request via curl.exe (decisive test)" -ForegroundColor Cyan
    Write-Host "  Why: bypasses frpc entirely. This is the decisive test." -ForegroundColor DarkGray
    Write-Host "       - curl works -> network path is fine, issue is frpc-specific" -ForegroundColor DarkGray
    Write-Host "       - curl fails with same 'connection forcibly closed' as frpc" -ForegroundColor DarkGray
    Write-Host "         -> NOT an FRP bug. Network/security stack between this server" -ForegroundColor DarkGray
    Write-Host "            and the backend is RST-ing TLS sessions. Look at step 6/7." -ForegroundColor DarkGray
    Write-Host ""
    $curlCmd = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curlCmd) {
        & curl.exe -v --max-time 10 -o NUL "https://${TargetHost}:${TargetPort}/" 2>&1 |
            ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "  curl.exe not present (Windows pre-1803). Falling back to Invoke-WebRequest." -ForegroundColor Yellow
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $r = Invoke-WebRequest -Uri "https://${TargetHost}:${TargetPort}/" -UseBasicParsing -TimeoutSec 10
            Write-Host "  HTTP $($r.StatusCode) ($($r.RawContentLength) bytes)" -ForegroundColor Green
        } catch {
            Write-Host "  FAIL: $_" -ForegroundColor Red
        }
    }

    # ---- 5. Raw TLS handshake -----------------------------------------------
    Write-Host ""
    Write-Host "[5/7] Raw TLS handshake (no HTTP layer)" -ForegroundColor Cyan
    Write-Host "  Why: tests if TLS itself completes. If TCP works (step 3) but TLS fails" -ForegroundColor DarkGray
    Write-Host "       here, the issue is at the TLS layer: missing root CA, cipher" -ForegroundColor DarkGray
    Write-Host "       mismatch, or a TLS-inspecting middlebox MITM-ing the connection." -ForegroundColor DarkGray
    Write-Host ""
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect($TargetIp, $TargetPort)
        $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, { param($s,$cert,$chain,$errors) $true })
        $ssl.AuthenticateAsClient($TargetHost)
        Write-Host "  TLS handshake OK" -ForegroundColor Green
        Write-Host "  Protocol: $($ssl.SslProtocol)"
        Write-Host "  Cipher:   $($ssl.CipherAlgorithm) ($($ssl.CipherStrength) bits)"
        if ($ssl.RemoteCertificate) {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $ssl.RemoteCertificate
            Write-Host "  Subject:  $($cert.Subject)"
            Write-Host "  Issuer:   $($cert.Issuer)"
            Write-Host "  Valid:    $($cert.NotBefore) -> $($cert.NotAfter)"
        }
        $ssl.Close(); $tcp.Close()
    } catch {
        Write-Host "  TLS handshake FAIL: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.InnerException) {
            Write-Host "  Inner: $($_.Exception.InnerException.Message)" -ForegroundColor Red
        }
    }

    # ---- 6. Security software / NDIS filters -------------------------------
    Write-Host ""
    Write-Host "[6/7] Security software that can intercept TLS" -ForegroundColor Cyan
    Write-Host "  Why: enterprise EDR/AV often MITM outbound HTTPS. They allow signed" -ForegroundColor DarkGray
    Write-Host "       apps (curl, browsers) but RST connections from unknown processes" -ForegroundColor DarkGray
    Write-Host "       like frpc.exe. If listed software differs from the working machine," -ForegroundColor DarkGray
    Write-Host "       that delta is a strong suspect." -ForegroundColor DarkGray
    Write-Host ""
    $secPattern = "defender|symantec|crowdstrike|mcafee|trellix|sophos|sentinel|zscaler|netskope|cisco|kaspersky|eset|bitdefender|cylance|carbon|tanium|fortinet|paloalto|avast|avg|f-secure|fsecure|forcepoint|webroot"
    $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Running" -and $_.DisplayName -match $secPattern }
    if ($svc) {
        $svc | Select-Object Name, DisplayName | Format-Table -AutoSize | Out-String | Write-Host
    } else {
        Write-Host "  No common security agents detected by name." -ForegroundColor Yellow
        Write-Host "  (Custom-branded agents may still be present - confirm with IT.)" -ForegroundColor DarkGray
    }
    Write-Host "Network adapter filter drivers (NDIS, non-Microsoft):"
    Get-NetAdapterBinding -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled -and $_.ComponentID -notmatch "ms_(tcpip|tcpip6|netbt|server|msclient|lltdio|rspndr|implat|bridge|ndiscap|pacer)" } |
        Select-Object Name, DisplayName, ComponentID |
        Format-Table -AutoSize | Out-String | Write-Host

    # ---- 7. System proxy ----------------------------------------------------
    Write-Host "[7/7] System proxy configuration" -ForegroundColor Cyan
    Write-Host "  Why: frpc inherits Go's proxy lookup, which respects HTTP_PROXY /" -ForegroundColor DarkGray
    Write-Host "       HTTPS_PROXY env vars. A corporate proxy may break TLS to internal" -ForegroundColor DarkGray
    Write-Host "       hosts. The working laptop may bypass proxy for internal sites; the" -ForegroundColor DarkGray
    Write-Host "       server may not." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "WinHTTP proxy:"
    netsh winhttp show proxy
    Write-Host ""
    Write-Host "Environment proxy variables:"
    foreach ($var in @("HTTP_PROXY","HTTPS_PROXY","NO_PROXY","http_proxy","https_proxy","no_proxy")) {
        $v = [Environment]::GetEnvironmentVariable($var)
        if ($v) { Write-Host "  $var = $v" -ForegroundColor Yellow }
        else    { Write-Host "  $var = (unset)" }
    }
    Write-Host ""
    Write-Host "WinINET / IE proxy (HKCU):"
    $ie = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
    if ($ie) {
        Write-Host "  ProxyEnable:   $($ie.ProxyEnable)"
        Write-Host "  ProxyServer:   $($ie.ProxyServer)"
        Write-Host "  ProxyOverride: $($ie.ProxyOverride)"
        Write-Host "  AutoConfigURL: $($ie.AutoConfigURL)"
    }

    # ---- Interpretation guide ----------------------------------------------
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "How to read these results" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  Step 3 FAIL                         -> Network firewall blocks the route."
    Write-Host "                                         Hand to network team."
    Write-Host "  Step 3 OK + step 4 FAIL with same   -> NOT an FRP bug. Something between"
    Write-Host "    'connection reset' as frpc           this host and the backend RSTs TLS."
    Write-Host "                                         Look at step 6 (EDR/AV) and step 7"
    Write-Host "                                         (proxy)."
    Write-Host "  Steps 3-5 OK, frpc still fails      -> frpc-specific. Capture pktmon and"
    Write-Host "                                         compare frpc TLS ClientHello vs curl."
    Write-Host "  Step 5 cert error                   -> Internal CA missing from this"
    Write-Host "                                         server's trust store."
    Write-Host "  Step 6 lists software the working   -> That delta is the likely cause."
    Write-Host "    laptop does NOT run                  Add frpc.exe exception in the EDR/AV."
    Write-Host "  Step 7 shows a proxy on server but  -> Set NO_PROXY for the backend host,"
    Write-Host "    not on the working laptop            or have IT bypass proxy for it."
    Write-Host ""

    } finally {
        if ($transcriptStarted) {
            try { Stop-Transcript | Out-Null } catch { }
        }
        if (Test-Path $logFile) {
            Write-Host "Diagnostic log saved to: $((Get-Item $logFile).FullName)" -ForegroundColor Green
        }
        Write-Host ""
        $ErrorActionPreference = $prevEAP
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
    $protocol = if ($UseTcp) { "tcp" } else { "quic" }
    $serverPort = if ($UseTcp) { 7000 } else { 7002 }
    
    # Determine if we need http2https plugin (for HTTPS backends)
    $useHttpsBackend = ($local_port -eq 443) -or $UseHttps

    if ($useHttpsBackend) {
        $config = @"
serverAddr = "$FRP_SERVER"
serverPort = $serverPort
metadatas.token = "$auth_token"
transport.poolCount = 50
transport.protocol = "$protocol"
udpPacketSize = 1500
transport.tls.enable = false

[[proxies]]
name = "$proxy_name"
type = "http"
subdomain = "$proxy_name"
transport.useEncryption = true
transport.useCompression = true

[proxies.plugin]
type = "http2https"
localAddr = "${local_ip}:${local_port}"
hostHeaderRewrite = "$hostname"
requestHeaders.set.x-forwarded-host = "$hostname"
"@
    } else {
        $config = @"
serverAddr = "$FRP_SERVER"
serverPort = $serverPort
metadatas.token = "$auth_token"
transport.poolCount = 50
transport.protocol = "$protocol"
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
    }

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

# Handle localhost explicitly to avoid IPv6 issues
if ($hostname -eq "localhost") {
    $local_ip = "127.0.0.1"
}
# Check if hostname is an IP address
elseif ($hostname -match '^\d+\.\d+\.\d+\.\d+$') {
    $local_ip = $hostname
} else {
    # Try to resolve the hostname
    try {
        $local_ip = (Resolve-DnsName -Name $hostname -ErrorAction Stop).IPAddress
        if (-not $local_ip) {
            throw "No IP address found"
        }
        if ($local_ip -is [array]) {
            # Prefer IPv4 over IPv6
            $ipv4 = $local_ip | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
            if ($ipv4) {
                $local_ip = $ipv4
            } else {
                $local_ip = $local_ip[0]
            }
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

# Run pre-flight diagnostics on demand so support has data when frpc fails.
if ($RunDiagnose) {
    try {
        Invoke-FrpcDiagnostics -TargetHost $hostname -TargetPort $local_port -TargetIp $local_ip
    } catch {
        Write-Host "Diagnostic step failed (continuing with frpc): $_" -ForegroundColor Yellow
    }
}

# Write frpc configuration
Write-FrpcConfig -hostname $hostname -local_ip $local_ip -local_port $local_port

# Run frpc
Write-Host "Starting frpc with frpc.toml... Press Ctrl+C to stop."
& .\frpc.exe -c frpc.toml