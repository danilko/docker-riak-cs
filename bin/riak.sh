#! /bin/sh

IP_ADDRESS=$(ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1)


# Back up data if not exist
#if [ ! -d "/apps/var/lib/riak" ];
#then
#  sudo mkdir -p /apps/var/lib

#  sudo mv /var/lib/riak /apps/var/lib
#else
#  sudo rm -rf /var/lib/riak
#fi

#sudo chmod 755 /apps
#sudo chmod 755 /apps/var
#sudo chmod 755 /apps/var/lib

#sudo mkdir -p /var/lib/riak
#sudo chown riak:riak /var/lib/riak
#sudo chmod 755 /var/lib/riak

#sudo mount --bind /apps/var/lib/riak /var/lib/riak

# Ensure correct ownership and permissions on volumes
sudo chown riak:riak /apps/var/lib/riak /var/log/riak
sudo chmod 755 /apps/var/lib/riak /var/log/riak

# Open file descriptor limit
ulimit -n 4096

# Ensure the Erlang node name is set correctly
sed -i.bak "s/127.0.0.1/${IP_ADDRESS}/" /etc/riak/vm.args

# Start Riak
exec /sbin/setuser riak "$(ls -d /usr/lib/riak/erts*)/bin/run_erl" "/tmp/riak" \
   "/var/log/riak" "exec /usr/sbin/riak console"
