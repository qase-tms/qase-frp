# Manual configuration

1. Install FRP client.
   - MacOS: `brew install frpc`
   - For other platforms, download the binary [here](https://github.com/fatedier/frp/releases) and specify its path in your `PATH` environment variable. It will allow you to run it from anywhere

2. Create a config file `frpc.toml` in any suitable directory

    ```toml
    serverAddr = "frps.qase.io"
    serverPort = 7002
    metadatas.token = "<auth_token>"
    transport.poolCount = 50
    transport.protocol = "quic"
    transport.tls.enable = false
    udpPacketSize = 1500
    
    [[proxies]]
    name = "<project_name>"
    type = "http"
    localIP = "<local_ip>"
    localPort = 80
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
