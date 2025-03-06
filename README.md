# qase-frp
This repository contains a script that allows you to create a tunnel to your private website for cloud testing in Qase. It uses the FRP client to create a tunnel to your private website. The script creates a configuration file for the FRP client and runs it. The script is written in bash and can be run on any platform that supports bash.

## Usage

Initial preparation:

```shell
wget -O frp.sh https://raw.githubusercontent.com/qase-tms/qase-frp/refs/heads/main/frp.sh && chmod +x frp.sh
```

After the installation, you can run the script from the same directory with the following command on MacOS or Linux:

```bash
./frp.sh -l private.website.local:80 -a "auth_token"
```

You can generate authentication token on the [Qase personal settings page](https://app.qase.io/user/api/token).

After running the script, it will create a tunnel to your private website and output the URL to access it. You can use this URL to run cloud tests in Qase.

To do it, create a new environment or update the existing one in your Qase project. Specify URL from our script as **Host** in the environment.

Run a cloud test run in Qase and specify the created/updated environment.

You can also specify -t option to specify tunnel name. It should be unique. If you don't specify it, the script will generate a random name.

## Manual configuration

Step for manual configuration are available [here](doc/manual.md).