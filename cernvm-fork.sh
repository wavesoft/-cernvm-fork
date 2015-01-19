#!/bin/bash
#
# CernVM Environment Fork Utility 
# Copyright (C) 2014-2015  Ioannis Charalampidis, PH-SFT, CERN

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#

# Configuration
CONFIG_RW_DIR=/mnt/.rw/containers
CONFIG_CERNVM_RO=/mnt/.ro/cvm3
CONFIG_CERNVM_PERSISTENT=/mnt/.rw/persistent
CONFIG_IP_SUFFIX=192.168.25
CONFIG_IP_GATEWAY=192.168.25.1
CONFIG_IP_BRIDGE=lxcbr0

# Show usage helper
function usage {
	echo "CernVM Environment Fork Script"
	echo "Usage:"
	echo ""
	echo " $1 <name> [-n|--new] [-c|--nonic] [-d|--daemon]"
	echo "           [-r|--run=<script>] [-t|--tty=<number>]"
	echo "           [-a|--admin=<username>[:<password>]]"
	echo "           [--init=<script>] [--cvmfs=<repos>]"
	echo " $1 <name> -C [-t|--tty=<number>]"
	echo " $1 <name> -D"
	echo ""
	echo "Options:"
	echo "  -h|--help         This help screen"
	echo "  -n|--new          Don't clone, start a new one"
	echo "  -d|--daemon       Don't attach console, deamonize"
	echo "  -c|--nonic        Don't add a network card"
	echo "  -r|--run=<script> Run the given script upon boot"
	echo "  -a|--admin=<user> Create a user with sudo privileges"
	echo "  -t|--tty=<number> The TTY to connect the console to"
	echo "  --init=<script>   Custom init script to use for booting"
	echo "  --ip=<address>    The IP address of the new container"
	echo "  --log=<file>      Where to log debug information"
	echo "  --cvmfs=<repos>   CVMFS repositories to mount from host"
	echo ""
	echo "Commands:"
	echo "  -D|--destroy      Destroy the fork instance"
	echo "  -C|--console      Open a console to the given instance"
	echo ""
}

###################
### ENTRY POINT ###
###################

# Require first parameter
NAME=$1
[ "$NAME" == "-h" -o "$NAME" == "--help" ] && usage && exit 1
[ -z "$NAME" ] && echo "ERROR: Please specify an environment name! (Use --help for more info)" && exit 1
[ "${NAME:0:1}" == "-" ] && echo "ERROR: Expecting fork name as first parameter! (Use --help for more info)" && exit 1

# Get options from command-line
options=$(getopt -o hDCt:ncdra: -l help,destroy,console,tty:,new,nonic,daemon,admin:,cvmfs:,run:,init:,ip:,log: -- "$@")
if [ $? -ne 0 ]; then
		usage $(basename $0)
	exit 1
fi
eval set -- "$options"

# Prepare defaults
F_DAEMON=0
F_NEW=0
F_NONIC=0
RUN_SCRIPT=""
INIT_SCRIPT="/sbin/init"
CVMFS_REPOS=""
IP_ADDR=""
LOG_FILE=""
ADMIN_USER=""
ADMIN_PWD=""
COMMAND="create"
CONSOLE_TTY="1"

# Process options
while true
do
	case "$1" in
		-h|--help)          usage $0 && exit 0;;
		-n|--new)           F_NEW=1; shift 1;;
		-d|--daemon)        F_DAEMON=1; shift 1;;
		-c|--nonic)         F_NONIC=1; shift 1;;
		-r|--run)           RUN_SCRIPT=$2; shift 2;;
		-t|--tty)			CONSOLE_TTY=$2; shift 2;;
		-a|--admin)
			ADMIN_USER=$2
			ADMIN_PWD=$(echo "${ADMIN_USER}" | awk -F':' '{print $2}')
			if [ -z "$ADMIN_PWD" ]; then
				read -p "Password for the ${ADMIN_USER} user: " -s ADMIN_PWD
				echo ""
			else
				ADMIN_USER=$(echo "${ADMIN_USER}" | awk -F':' '{print $1}')
			fi
			shift 2;;
		-D|--destroy)		COMMAND="destroy"; shift 1;;
		-C|--console)		COMMAND="console"; shift 1;;
		--cvmfs)            CVMFS_REPOS="${CVMFS_REPOS} $2"; shift 2;;
		--init)             INIT_SCRIPT=$2; shift 2;;
		--ip)               IP_ADDR=$2; shift 2;;
		--log)              LOG_FILE=$2; shift 2;;
		--)                 shift 1; break ;;
		*)                  break ;;
	esac
done

# Override init script if not defined by -r
if [ ! -z "${INIT_SCRIPT}" ]; then
	INIT_SCRIPT="$*"
fi

# Prepare directories
PROJECT_DIR=${CONFIG_RW_DIR}/${NAME}
RW_DIR=${PROJECT_DIR}/rw
RO_DIR=${CONFIG_CERNVM_RO}
MNT_DIR=${PROJECT_DIR}/root
CONSOLE_FILE=/var/run/lxc-cvmfork-${NAME}.console

# Check the command-line to use for logging
LOG_CMDLINE=""
if [ ! -z "${LOG_FILE}" ]; then
	LOG_CMDLINE="-o ${LOG_FILE} -l trace"
	echo "------------------" >> ${LOG_FILE}
	cat $LXC_CONFIG >> ${LOG_FILE}
	echo "------------------" >> ${LOG_FILE}
fi

# Cleanup function
function cleanup {

	# Stop container
	if [ $(lxc-ls | grep -c -r "^${NAME}$") -ne 0 ]; then
		echo "Stopping container..."
		lxc-stop --name=${NAME} ${LOG_CMDLINE} -k
	fi

	# Unmount lingering filesystems
	if [ -d ${MNT_DIR} ]; then
		echo "Unmounting filesystems..."
		LINGER=$(mount | grep "${MNT_DIR}" | awk '{print $3}')
		[ ! -z "$LINGER" ] && umount $LINGER
	fi

	# Destroy container if exists
	if [ $(lxc-ls | grep -c -r "^${NAME}$") -ne 0 ]; then
		echo "Destroying container..."
		lxc-destroy --name=${NAME} ${LOG_CMDLINE}
		echo "Cleaning-up config files..."
		rm -f ${LXC_CONFIG}
		rm -f ${CONSOLE_FILE}
	fi

	# Clean-up mount directory
	if [ -d ${PROJECT_DIR} ]; then
		echo "Cleaning-up scratch space..."
		rm -rf ${PROJECT_DIR}
	fi

}

########################
### COMMAND HANDLING ###
########################

# Check for priority commands
if [ "${COMMAND}" == "destroy" ]; then
	cleanup
	exit 0
elif [ "${COMMAND}" == "console" ]; then
	if [ $(lxc-ls | grep -c -r "^${NAME}$") -ne 0 ]; then
		echo "Connecting to container..."
		lxc-console --name=${NAME} ${LOG_CMDLINE} -t ${CONSOLE_TTY} || die "Unable to connect to the console"
	fi
	exit 0
fi

# If we already have project_dir, alert
if [ -d ${PROJECT_DIR} ]; then
   echo "ERROR: A fork with the same name already exists!"
   exit 2
fi

#######################
### NEW VM CREATION ###
#######################

# Create 'none' template for lxc utilities
if [ ! -f /usr/share/lxc/templates/lxc-none ]; then
	echo "#!/bin/bash" > /usr/share/lxc/templates/lxc-none
	chmod +x /usr/share/lxc/templates/lxc-none
fi

# Prepare mount point
echo -n "Preparing filesystem..."
mkdir -p ${MNT_DIR}
mkdir -p ${RW_DIR}
echo "ok"

# Clone persistent cache
if [ $F_NEW -eq 0 ]; then
   echo -n "Cloning persistent cache..."
   cp -aR ${CONFIG_CERNVM_PERSISTENT}/* ${RW_DIR}/
   echo "ok"
fi

# Mount root filesystem
echo -n "Mounting container root on ${MNT_DIR}..."
mount -t aufs -o dirs=${RW_DIR}=rw:${RO_DIR}=ro aufs-${NAME} ${MNT_DIR}
echo "ok"

# Calculate a random IP Address
if [ -z "${IP_ADDR}" ]; then
   IP_ADDR=${CONFIG_IP_SUFFIX}.$(shuf -i 2-254 -n 1)
fi
echo "The container will have IP ${IP_ADDR}"

# Create linux container file
LXC_CONFIG=${PROJECT_DIR}/config.lxc
cat <<EOF > $LXC_CONFIG
lxc.utsname=${NAME}
lxc.autodev=1
lxc.tty=12
lxc.kmsg=0
lxc.pts=1024
lxc.rootfs = ${MNT_DIR}
lxc.stopsignal = SIGKILL
lxc.console = ${CONSOLE_FILE}
EOF

# Check if we should not add network
if [ $F_NONIC -eq 1 ]; then
	cat <<EOF >> $LXC_CONFIG
lxc.network.type=empty
EOF
else
	cat <<EOF >> $LXC_CONFIG
lxc.network.type = veth
lxc.network.flags = up
lxc.network.link = ${CONFIG_IP_BRIDGE}
lxc.network.ipv4 = ${IP_ADDR}
lxc.network.ipv4.gateway = ${CONFIG_IP_GATEWAY}
lxc.network.name = eth0
lxc.network.mtu=1500
EOF

	# Get DNS nameservers
	DNS1=$(cat /etc/resolv.conf | grep nameserver | head -n1 | awk '{print $2}')
	DNS2=$(cat /etc/resolv.conf | grep nameserver | head -n2 | tail -n1 | awk '{print $2}')

	# Setup network inside the VM
	cat <<EOF > ${MNT_DIR}/etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE=eth0
BOOTPROTO=none
ONBOOT=yes
GATEWAY=${CONFIG_IP_GATEWAY}
IPADDR=${IP_ADDR}
NETMASK=255.255.255.0
DNS1=${DNS1}
DNS2=${DNS2}
EOF

fi

# Mount CVMFS repositories & prepare bind-mounts
if [ ! -z "$CVMFS_REPOS" ]; then
	echo -n "Disabling Autofs in the container..."
	chroot ${MNT_DIR} chkconfig autofs off
	echo "ok"

	echo -n "Premounting CVMFS repositories: "
	for REPOS in $CVMFS_REPOS; do
	   echo -n "${REPOS} "
	   # Let Autofs mount CVMFS repository
	   ls /cvmfs/${REPOS} 2>/dev/null >/dev/null
	   # Prepare destination inside the container
	   mkdir -p ${MNT_DIR}/cvmfs/${REPOS}
	   # Append the bind mount rule
	   echo "lxc.mount.entry = /cvmfs/${REPOS} cvmfs/${REPOS} none ro,bind,optional 0 0" >> $LXC_CONFIG
	done
	echo "ok"
fi

# Die after error function (includes cleanup)
function die {
	echo "ERROR: $1"
	cleanup
	exit 2
}

# Extend rc.local with the run script
if [ ! -z "${RUN_SCRIPT}" ]; then
	echo -n "Adding run script..."
	# Check if this is a file inside the guest
	if [ -f "${MNT_DIR}/${RUN_SCRIPT}" ]; then
		# Append to rc.local
		echo "${RUN_SCRIPT}" >> ${MNT_DIR}/etc/rc.local
	elif [ ! -f "${RUN_SCRIPT}" ]; then
		die "The specified run script '${RUN_SCRIPT}' was not found!"
	else
		# Copy to target system
		TARGET_NAME=/tmp/postinit-$(basename ${RUN_SCRIPT})
		cp ${RUN_SCRIPT} ${MNT_DIR}/${TARGET_NAME}
		# Append to rc.local
		echo "${TARGET_NAME}" >> ${MNT_DIR}/etc/rc.local
	fi
	echo "ok"
fi

# Create admin accounts if requested
if [ ! -z "${ADMIN_USER}" ]; then
	echo -n "Creating admin user '${ADMIN_USER}'..."
	ADMIN_CRYPT=$(openssl passwd -crypt "${ADMIN_PWD}")
	# Create user
	chroot ${MNT_DIR} useradd -p ${ADMIN_CRYPT} -G wheel ${ADMIN_USER}
	# Make this user sudoer
	echo -e "${ADMIN_USER}\tALL=(ALL)\tALL" >> ${MNT_DIR}/etc/sudoers
	# Close
	echo "ok"
fi

# Create a linux container
echo -n "Creating container..."
lxc-create -f ${LXC_CONFIG} ${LOG_CMDLINE} --name ${NAME} --template none || die "Unable to create the container"
echo "ok"
echo -n "Starting container..."
lxc-start -d --name ${NAME} ${LOG_CMDLINE} || die "Unable to start the container"
echo "ok"
echo "Your CernVM fork '${NAME}' is up and running"

# If we are not daemon, open console
if [ $F_DAEMON -eq 0 ]; then
	echo "Opening console..."
	lxc-console --name ${NAME} ${LOG_CMDLINE} -t ${CONSOLE_TTY} || die "Unable to connect to the console"
	# Cleanup before exit
	cleanup
fi
