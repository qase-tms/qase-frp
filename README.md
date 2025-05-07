# qase-frp

This repository contains scripts that allow you to create a tunnel to your private website for cloud testing in Qase. It uses the FRP client to create a tunnel to your private website. The script creates a configuration file for the FRP client and runs it.

> **Windows Users**: For Windows-specific instructions, please see the [Windows README](README_WINDOWS.md).

## Step-by-step Guide to Setting Up Qase FRP Tunnel

### Step 1: Download and Install FRP Script

Run the following command in your terminal to download and prepare the FRP script:

```shell
wget -O frp.sh https://raw.githubusercontent.com/qase-tms/qase-frp/refs/heads/main/script/frp.sh && chmod +x frp.sh
```

### Step 2: Generate Authentication Token

- Visit the [Qase Personal Settings page](https://app.qase.io/user/api/token).
- Generate a new authentication token and copy it for use in the next step.

### Step 3: Run FRP Script to Create Tunnel

Execute the following command from the directory where you downloaded frp.sh:

```shell
./frp.sh -l private.website.local:80 -a "your_auth_token"
```

Replace:

- `private.website.local:80` with your local website's domain and port.
- `your_auth_token` with the token you generated in Step 2.

Optional:
To specify a custom tunnel name (should be unique), use the -t option:

```shell
./frp.sh -l private.website.local:80 -a "your_auth_token" -t custom_tunnel_name
```

If omitted, the script will generate a random name.

### Step 4: Obtain FRP URL

After the launch, the script outputs a URL, like `http://${project_name}.srv.frps.qase.dev`. 

**Important:**

- This URL could be opened only within the Qase internal network and will
not work locally. It is specifically required for the cloud test generator and runner in Qase.
- The link is valid only while the script is running. If the script is stopped, the link will become invalid.

### Step 5: Configure Environment in Qase

- Log into your Qase project.
- Create a new environment or edit an existing one.
- Set the **Host** parameter to the URL obtained in Step 4.

**Important:**
When creating test cases, if you use a URL such as `ourhost.com` within a test step, Qase automatically replaces it
with the URL specified in the environment's **Host** variable. Ensure you set the environment **Host** variable to
the FRP-generated URL to direct tests appropriately.

### Step 6: Run Cloud Tests

- Initiate a cloud test run in Qase.
- Select the configured environment from Step 5.
- Run your tests.

## Manual configuration

Step for manual configuration are available [here](doc/manual.md).