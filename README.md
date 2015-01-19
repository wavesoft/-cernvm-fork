
# CernVM Environment Fork

This utility allows _forking_ of a booted micro-CernVM OS into a new linux container.

This can be very useful when you want to _isolate_ the execution of a particular application that is already fully compatible with a CernVM/RHEL6 distribution.

# Usage

The `cernvm-fork ` utility accepts the following command-line parameters:

    CernVM Environment Fork Script
    Usage:
    
     cernvm-fork <name> [-n|--new] [-c|--nonic] [-d|--daemon]
                        [-r|--run=<script>] [-t|--tty=<number>]
                        [-a|--admin=<username>[:<password>]]
                        [--init=<script>] [--cvmfs=<repos>]
     cernvm-fork <name> -C [-t|--tty=<number>]
     cernvm-fork <name> -D

When creating a new CernVM fork, the following parameters are accepted:

 * `-n` or `--new` : Instructs cernvm-fork not to clone the environment, but rather to start with a clean uCernVM boot.
 * `-d` or `--daemon` : Instructs cernvm-fork not to attach a console after the container is created, but rather to let it run in the background.
 * `-c` or `--nonic` : Do not attach a network card.
 * `-r <script>` or `--run <script>` : Run the specified script after the container is booted. This file can either point to a location in the host filesystem **OR** in the guest filesystem. The script will first check the guest filesystem and if the file does not exist, it will copy it from the host filesystem.
 * `-a <user>[:<password>]` or `--admin <user>[:<password>]` : Create the given user with sudo privileges. If a password is not specified, you will be prompted to enter it right before the container is booted.
 * `-t` or `--tty` : The TTY you want the console to attach to. This flag has no effect if `-d` was not specified.
 * `--init=<script>` : The custom init script to use for booting the OS. This defaults to `/sbin/init`.
 * `--ip=<address>` : The IP address to assign to the container. If this flag is not specified, a random new IP will be assigned.
 * `--log=<file>` : The file where to write the debug log messages.
 * `--cvmfs=<repository>[,<repository>...]` : The names of the CVMFS repositories to bind-mount from the host OS to the guest OS before booting.

The `cernvm-fork` utility also accepts the following commands:

 * `-C` : Connect to the console of the specified linux container.
 * `-D` : Destroy the specified forked linux container.

# Technical Information

This utility uses the low-level Linux Container Utilities (lxc-utils) in order to start a new isolated linux container. For the root filesystem, it uses the same techniques with micro-CernVM in order to create a RW overlay on top of the RO operating system files fetched from CVMFS.

This utility is usable **only** inside a micro-CernVM environment, since it exploits the existing mouts and cache files used by micro-boot phase. 

When instructed to *Fork*, the utility will copy the current uCernVM RW cache, effectively 'cloning' the current state. It will then modify the network configuration in order to give it another IP.

When instructed to perform a *Clean boot*, the utility will follow the same procedure, but start with a clean RW cache.

# Incomplete features

 * The utility expects a network bridge called `lxcbr0` to be existing and already configured with the IP subnet `192.168.25.0/24`. (The utility must be able to adapt on the current network configuration).
 * The `--cvmfs` parameter even though it's properly functioning, should not be used if you are booting uCernVM with the default init process. That's because the guest OS will mount autofs on `/cvmfs` and will handle automatic mounting of any CVMFS repository as commonly used in CernVM. This parameter might be useful if you are using your own, lightweight init process. (The utility must be able to detect and disable the CVMFS bind-mount feature when using the default init).

# License

CernVM Environment Fork Utility 
Copyright (C) 2014-2015  Ioannis Charalampidis, PH-SFT, CERN

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
