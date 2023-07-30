#!/bin/bash -vx
#
# Install, configure and start a new Foundry server
# This supports Ubuntu and Amazon Linux 2 flavors of Linux (maybe/probably others but not tested).

set -e

# Determine linux distro
if [ -f /etc/os-release ]; then
    # freedesktop.org and systemd
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
    # linuxbase.org
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
    # For some versions of Debian/Ubuntu without lsb_release command
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    # Older Debian/Ubuntu/etc.
    OS=Debian
    VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSe-release ]; then
    # Older SuSE/etc.
    ...
elif [ -f /etc/redhat-release ]; then
    # Older Red Hat, CentOS, etc.
    ...
else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    OS=$(uname -s)
    VER=$(uname -r)
fi

# Update OS and install start script
ubuntu_linux_setup() {
  export SSH_USER="ubuntu"
  export DEBIAN_FRONTEND=noninteractive
  /usr/bin/apt-get update
  /usr/bin/apt-get -yq install -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" wget awscli jq libssl-dev atool net-tools
  /usr/bin/curl -sL https://deb.nodesource.com/setup_18.x | sudo bash -
  /usr/bin/apt-get install -y nodejs


  /bin/cat <<"__UPG__" > /etc/apt/apt.conf.d/10periodic
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
__UPG__

  # Init script for starting, stopping
  cat <<INIT > /etc/init.d/foundry
#!/bin/bash
### BEGIN INIT INFO
# Provides:          foundry
# Required-Start:    $local_fs $network
# Required-Stop:     $local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start/stop foundry server
### END INIT INFO

start() {
  echo "Starting foundry server from /home/foundry..."
  start-stop-daemon --start --quiet  --pidfile ${foundry_root}/foundry-server/foundry.pid -m -b -c $SSH_USER -d ${foundry_root}/foundry-server --exec /usr/bin/node -- $MAIN_JS --dataPath=${foundry_root}/userdata --port=${foundry_port} 
}

stop() {
  echo "Stopping foundry server..."
  start-stop-daemon --stop --pidfile ${foundry_root}/foundry-server/foundry.pid
}

case \$1 in
  start)
    start
    ;;
  stop)
    stop
    ;;
  restart)
    stop
    sleep 5
    start
    ;;
esac
exit 0
INIT

  # Start up on reboot
  /bin/chmod +x /etc/init.d/foundry
  /usr/sbin/update-rc.d foundry defaults

}

# Update OS and install start script
amazon_linux_setup() {
    export SSH_USER="ec2-user"
    /usr/bin/yum install yum-cron wget awscli jq openssl-devel atool net-tools -y
    /bin/sed -i -e 's/update_cmd = default/update_cmd = security/'\
                -e 's/apply_updates = no/apply_updates = yes/'\
                -e 's/emit_via = stdio/emit_via = email/' /etc/yum/yum-cron.conf
    /usr/bin/curl --silent --location https://rpm.nodesource.com/setup_18.x | sudo bash -
    /usr/bin/yum install -y nodejs
    chkconfig yum-cron on
    service yum-cron start
    /usr/bin/yum upgrade -y

    cat <<SYSTEMD > /etc/systemd/system/foundry.service
[Unit]
Description=Foundry Server
After=network.target

[Service]
Type=simple
User=$SSH_USER
WorkingDirectory=${foundry_root}/foundry-server
ExecStart=/usr/bin/node $MAIN_JS --dataPath=${foundry_root}/userdata --port=${foundry_port} 
Restart=on-abort

[Install]
WantedBy=multi-user.target
SYSTEMD

  # Start on boot
  /usr/bin/systemctl enable foundry

}

download_foundry_server() {
  cd ${foundry_root}
 
  WGET=$(which wget)

  $WGET -O foundryvtt.zip "${foundry_url}"
  /usr/bin/unzip foundryvtt.zip -d ${foundry_root}/foundry-server
}

create_and_setup_dynv6_updater() {
  # Create dynv6 updater script
  cat <<DYNV6 > ${foundry_root}/foundry-server/dynv6-updater.sh
#!/bin/bash

# Get current IP address from AWS
IP=\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Update dynv6.net with current IP address
echo "IPv4 adress has changed -> update ..."
curl -s "https://ipv4.dynv6.com/api/update?hostname=${hostname_dynv6}&token=${token_dynv6}&ipv4=\$IP"
echo "---"


DYNV6
  
  /bin/chmod +x ${foundry_root}/foundry-server/dynv6-updater.sh

  # Init script for starting, stopping
  cat <<INIT > /etc/init.d/dynv6-updater
#!/bin/bash
### BEGIN INIT INFO
# Provides:          dynv6-updater
# Required-Start:    $local_fs $network
# Required-Stop:     $local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start dynv6-updater
### END INIT INFO

start() {
  echo "Starting dynv6-updater..."
  start-stop-daemon --start --background --chdir ${foundry_root}/foundry-server --exec ${foundry_root}/foundry-server/dynv6-updater.sh
}

stop() {
  echo "Nothing to todo"
}

case \$1 in
  start)
    start
    ;;
  stop)
    stop
    ;;
  restart)
    start
    ;;
esac
exit 0
INIT

  /bin/chmod +x /etc/init.d/dynv6-updater
  /usr/sbin/update-rc.d dynv6-updater defaults

}

create_auto_shutdown() {
  # Create auto shutdown script
  cat <<SHUTDOWN > ${foundry_root}/foundry-server/auto-shutdown.sh
#!/bin/bash

# set the port and the timeout period (in seconds)
INSTANCE_ID=\$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

while true; do
    # check for active connections on the specified ports
    netstat -an | grep -E ":${foundry_port}|22" | grep ESTABLISHED
    if [ $? -ne 0 ]; then
        # if no active connections were found, start the countdown
        echo "No active connections found. Starting countdown..."
        sleep ${auto_shutdown_time}
        # after the countdown, check for active connections again
        netstat -an | grep -E ":${foundry_port}|22" | grep ESTABLISHED
        if [ $? -ne 0 ]; then
            # if still no active connections were found, initiate shutdown
            echo "No active connections found after countdown. Initiating shutdown..."
            aws ec2 stop-instances --instance-ids \$INSTANCE_ID
            break
        fi
    fi
    # if active connections were found, wait for a while before checking again
    sleep 60
done
SHUTDOWN

  /bin/chmod +x ${foundry_root}/foundry-server/auto-shutdown.sh

  # Init script for starting, stopping
  cat <<INIT > /etc/init.d/auto-shutdown
#!/bin/bash
### BEGIN INIT INFO
# Provides:          auto-shutdown
# Required-Start:    $local_fs $network
# Required-Stop:     $local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start auto-shutdown
### END INIT INFO

start() {
  echo "Starting auto-shutdown..."
  start-stop-daemon --start --background --chdir ${foundry_root}/foundry-server --exec ${foundry_root}/foundry-server/auto-shutdown.sh
}

stop() {
  echo "Nothing to todo"
}

case \$1 in
  start)
    start
    ;;
  stop)
    stop
    ;;
  restart)
    start
    ;;
esac
exit 0
INIT

  /bin/chmod +x /etc/init.d/auto-shutdown
  /usr/sbin/update-rc.d auto-shutdown defaults
}

MAIN_JS="${foundry_root}/foundry-server/resources/app/main.js"
case $OS in
  Ubuntu*)
    ubuntu_linux_setup
    ;;
  Amazon*)
    amazon_linux_setup
    ;;
  *)
    echo "$PROG: unsupported OS $OS"
    exit 1
esac

# Create mc dir, sync S3 to it and download foundry if not already there (from S3)
echo "Creating foundry directories and syncing from S3..."
/bin/mkdir -p ${foundry_root}
/bin/mkdir -p ${foundry_root}/foundry-server
/bin/mkdir -p ${foundry_root}/userdata
/usr/bin/aws s3 sync s3://${foundry_bucket} ${foundry_root}

# Download foundry server if it doesn't exist on S3 already (existing from previous install)
# To force a new server version, remove the server files from S3 bucket
if [ ! -e "${foundry_root}/$MAIN_JS" ] && [ -n "${foundry_url}" ]; then
  download_foundry_server
fi

# Cron job to sync data to S3 every five mins
echo "Setting up cron job to sync data to S3 every 10 mins..."
/bin/cat <<CRON > /etc/cron.d/foundry
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:${foundry_root}
*/${foundry_backup_freq} * * * *  $SSH_USER  /usr/bin/aws s3 sync ${foundry_root}  s3://${foundry_bucket}
CRON

# Create dynv6 updater script if dynv6.net hostname and token are provided
echo "Setting up dynv6 updater..."
if [ -n "${hostname_dynv6}" ] && [ -n "${token_dynv6}" ]; then
  create_and_setup_dynv6_updater
fi

# Dirty fix
/bin/touch ${foundry_root}/foundry-server/foundry.pid
/bin/chown $SSH_USER ${foundry_root}/foundry-server/foundry.pid
/bin/chmod 664 ${foundry_root}/foundry-server/foundry.pid
/bin/chgrp $SSH_USER ${foundry_root}/foundry-server/foundry.pid

# Not root
/bin/chown -R $SSH_USER ${foundry_root}

/bin/setcap 'cap_net_bind_service=+ep' /usr/bin/node

# Start the server
if [ -n "${foundry_url}" ]; then
  case $OS in
    Ubuntu*)
      /etc/init.d/foundry start
      /etc/init.d/dynv6-updater start
      ;;
    Amazon*)
      /usr/bin/systemctl start foundry
      ;;
  esac
fi

exit 0

