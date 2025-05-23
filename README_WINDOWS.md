# Qase FRP for Windows

This document provides instructions for setting up the Qase FRP tunnel on Windows systems.

## Step-by-step Guide to Setting Up Qase FRP Tunnel on Windows

### Step 1: Download and Prepare the FRP Script

Run the following command in your terminal to download and prepare the FRP script:

```shell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/qase-tms/qase-frp/refs/heads/main/script/frp.ps1" -OutFile "frp.ps1"
```

### Step 2: Generate Authentication Token

- Visit the [Qase Personal Settings page](https://app.qase.io/user/api/token).
- Generate a new authentication token and copy it for use in the next step.

### Step 3: Run FRP PowerShell Script to Create Tunnel

Open PowerShell and execute the following command from the directory where you downloaded the repository:

```powershell
.\frp.ps1 -LocalHostname private.website.local:80 -AuthToken "your_auth_token"
```

Replace:

- `private.website.local:80` with your local website's domain and port.
- `your_auth_token` with the token you generated in Step 2.

Optional:
To specify a custom tunnel name (should be unique), use the -TunnelName option:

```powershell
.\frp.ps1 -LocalHostname private.website.local:80 -AuthToken "your_auth_token" -TunnelName custom_tunnel_name
```

If omitted, the script will generate a random name.

### Step 4: Troubleshooting Antivirus Issues

If you encounter errors related to virus detection or Windows Defender blocking frpc.exe:

1. **Add an Exception in Windows Defender**:
   - Open Windows Security
   - Go to Virus & threat protection
   - Under Virus & threat protection settings, click on Manage settings
   - Scroll down to Exclusions and click Add or remove exclusions
   - Add an exclusion for the frpc.exe file or the entire qase-frp directory

2. **Temporarily Disable Antivirus**:
   - This is recommended only if you trust the source of the frpc.exe file
   - The frpc binaries are downloaded directly from the official [fatedier/frp](https://github.com/fatedier/frp) GitHub repository

3. **Use Existing Binary**:
   - The script will automatically use an existing frpc.exe if found in the windows directory

### Step 5: Obtain FRP URL

After the launch, the script outputs a URL, like https://.qase.frp/.

**Important:**

- This URL could be opened only within the Qase internal network and will not work locally. It is specifically required for the cloud test generator and runner in Qase.
- The link is valid only while the script is running. If the script is stopped, the link will become invalid.

### Step 6: Configure Environment in Qase

- Log into your Qase project.
- Create a new environment or edit an existing one.
- Set the **Host** parameter to the URL obtained in Step 5.

### Step 7: Run Cloud Tests

- Initiate a cloud test run in Qase.
- Select the configured environment from Step 6.
- Run your tests.

## Troubleshooting IPv6/IPv4 Issues

If you encounter connection errors like "No connection could be made because the target machine actively refused it":

1. Make sure your local service is actually running on the specified port
2. Try using `127.0.0.1` explicitly instead of `localhost` in the `LocalHostname` parameter
3. The script has built-in handling to prefer IPv4 connections over IPv6 for better compatibility

## PowerShell Execution Policy

If you encounter restrictions running PowerShell scripts, you may need to adjust your execution policy:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

This sets the execution policy to bypass for the current PowerShell session only.
