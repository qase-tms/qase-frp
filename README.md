# qase-frp
This repository contains a script that allows you to create a tunnel to your private website for cloud testing in Qase. It uses the FRP client to create a tunnel to your private website. The script creates a configuration file for the FRP client and runs it. The script is written in bash and can be run on any platform that supports bash.

## Usage
You can run the script with the following command on MacOS or Linux:
```bash
wget -O frp.sh https://raw.githubusercontent.com/qase-tms/qase-frp/refs/heads/main/frp.sh && chmod +x frp.sh
./frp.sh -l private.website.local:80 -a "auth_token"
```
Auth token is a token that Qase’s support can provide. In the future, you will be able to specify your Qase API token here.

After running the script, it will create a tunnel to your private website and output the URL to access it. You can use this URL to run cloud tests in Qase.

To do it, create a new environment or update the existing one in your Qase project. Specify URL from our script as **Host** in the environment.

Run a cloud test run in Qase and specify the created/updated environment.

You can also specify -t option to specify tunnel name. It should be unique. If you don't specify it, the script will generate a random name.

## Manual configuration
1. Install FRP client.
   - MacOS: `brew install frpc`
   - For other platforms, download the binary [here](https://github.com/fatedier/frp/releases) and specify its path in your `PATH` environment variable. It will allow you to run it from anywhere
2. Create a config file `frpc.toml` in any suitable directory

    ```toml
    serverAddr = "frps.qase.dev"
    serverPort = 7002
    auth.method = "token"
    auth.token = "${auth_token}"
    transport.poolCount = 50
    transport.protocol = "quic"
    udpPacketSize = 1500
    transport.tls.enable = false
    
    [[proxies]]
    name = "${project_name}"
    type = "http"
    localIP = "${local_ip}"
    localPort = ${local_port}
    subdomain = "${project_name}"
    hostHeaderRewrite = "${project_host}"
    ```

3. Replace values:
   - `${auth_token}` - auth token, Qase’s support can provide a token. In the future, you will be able to specify your Qase API token here
   - `${project_name}` - project name, it should be unique.
   you can generate something unique with the command `cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
   - `${local_ip}` - local IP of your private website. You can get it with `ping` command
   - `${local_port}` - local port of your private website, usually 80
   - `${project_host}` - original hostname for your private website. It should be specified, for the correct working of a private website
4. Run `frpc -c frpc.toml` in the directory with created `frpc.toml`
5. Create a new environment or update the existing one in your Qase project. Specify  `http://${project_name}.srv.frps.qase.dev`  as **Host** in the environment
6. Run a cloud test run in Qase and specify the created/updated environment
