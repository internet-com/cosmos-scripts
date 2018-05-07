#!/bin/bash -ex

# Current source of documentation: https://cosmos.network/validators/tutorial
# Requires Amazon Linux 2

# The git tag from https://github.com/cosmos/cosmos-sdk
RELEASETAG="v0.16.0-rc0"

# The testnet to join (https://github.com/cosmos/testnets/)
TESTNET="gaia-5000"

MONIKER="XXX"

# Debug logging
exec > /var/log/gaia-setup.log
exec 2>&1

# Update packages - we'll reboot later on in case a this includes a kernel update
yum update -y

# Install dependencies
yum install -y git awslogs

# Configure awslogs to use our region
echo "[plugins]
cwlogs = cwlogs
[default]
region = eu-central-1" > /etc/awslogs/awscli.conf

# Log Gaia output separately as it is in a custom date/time format
touch /var/log/gaia.log
echo "[/var/log/gaia.log]
datetime_format = I[%m-%d|%H:%M:%S.%f]
file = /var/log/gaia.log
log_stream_name = {instance_id}
log_group_name = /var/log/gaia.log" > /etc/awslogs/config/gaia.conf
systemctl enable awslogsd.service

# Install Go 1.9.2
cd /tmp
wget https://storage.googleapis.com/golang/go1.9.2.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.9.2.linux-amd64.tar.gz
export GOPATH=/opt/gopath
export PATH=$GOPATH/bin:/usr/local/go/bin:$PATH

# Install Gaia 0.5.0
go get github.com/cosmos/cosmos-sdk || true
cd "$GOPATH/src/github.com/cosmos/cosmos-sdk"
git fetch --all
git checkout -qf $RELEASETAG
make get_tools
make get_vendor_deps
make install

# Log installed versions
echo "gaiad version :" $(gaiad version)
echo "gaiacli version :" $(gaiacli version)


# Get testnet configuration
git clone https://github.com/cosmos/testnets /opt/testnets

# Create gaia-daemon user and set permissions
useradd --system --shell /usr/sbin/nologin gaia-daemon
chown -R gaia-daemon:gaia-daemon /opt/testnets /var/log/gaia.log

# TODO Move this to /opt/testnets/
mkdir -p /opt/gaiad/config
cp -a /opt/testnets/gaia-5000/. /opt/gaiad/config/gentx

gaiad unsafe_reset_all --home=/opt/gaiad/
gaiad init --gen-txs -o --chain-id=gaia-5000 --home=/opt/gaiad/

chown -R gaia-daemon:gaia-daemon /opt/gaiad/

# Create gaia.service
echo "[Unit]
Description=Cosmos Gaia Node
After=network-online.target

[Service]
User=gaia-daemon

# Need systemd 236 or later for the below
# ExecStart=/opt/gopath/bin/gaia node start --home=/opt/testnets/gaia-2/gaia
# StandardOutput=file:/var/log/gaia.log
# StandardError=file:/var/log/gaia.log

# .. so use this workaround instead:
# ExecStart=/bin/sh -c '/opt/gopath/bin/gaia node start --home=/opt/testnets/gaia-2/gaia 2>&1 > /var/log/gaia.log'
# ExecStart=/bin/sh -c '/opt/gopath/bin/gaiad node start --home=/opt/ testnets/gaia-2/gaia 2>&1 > /var/log/gaia.log'
ExecStart=/bin/sh -c '/opt/gopath/bin/gaiad start --home=/opt/gaiad/ 2>&1 > /var/log/gaia.log'

[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/gaia.service
systemctl enable gaia.service

# Finally reboot
reboot
