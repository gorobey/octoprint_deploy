#!/bin/bash

if (( $EUID != 0 )); then
    echo "Please run as root"
    exit
fi
echo "UNPLUG PRINTER FROM USB"
echo "Enter the name for new printer/instance:"
read INSTANCE
if [ -z "$INSTANCE" ]; then
    echo "No instance given. Exiting"
    exit 1
fi

if test -f "/etc/default/$INSTANCE"; then
    echo "Already have an entry for $INSTANCE. Exiting."
    exit 1
fi

echo "Port on which this instance will run (ENTER will increment last value in /etc/octoprint_ports):"
read PORT
if [ -z "$PORT" ]; then
    PORT=$(tail -1 /etc/octoprint_ports)

    if [ -z "$PORT"]; then
       PORT=4999
    fi

    PORT=$((PORT+1))
    echo Selected port is: $PORT
fi

if grep -q $PORT /etc/octoprint_ports; then
    echo "Port in use! Check /etc/octoprint_ports. Exiting."
    exit 1
fi

#TODO
#collect user, basedir path, daemon path
echo "Octoprint Daemon User [$USER]:"
read OCTOUSER
if [ -z "$OCTOUSER" ]; then
    OCTOUSER=$USER
fi

echo "Octoprint Daemon Path [/home/$USER/OctoPrint/venv/bin/octoprint]:"
read OCTOPATH
if [ -z "$OCTOPATH" ]; then
    OCTOPATH="/home/$USER/OctoPrint/venv/bin/octoprint"
fi

echo "Octoprint Config Path [/home/$USER/]:"
read OCTOCONFIG
if [ -z "$OCTOCONFIG" ]; then
    OCTOCONFIG="/home/$USER/"
fi

read -p "Auto-detect printer serial number for udev entry?" -n 1 -r
echo    #new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
   echo "Plug your printer in via USB now (detection time-out in 2 min)"
   counter=0
   while [[ -z "$UDEV" ]] && [[ $counter -lt 60 ]]; do 
      UDEV=$(timeout 2s journalctl -kf | sed -n -e 's/^.*SerialNumber: //p')
      counter=$(( $counter + 1 ))
   done
   
   if [ -z "$UDEV" ]; then
       echo "Printer not detected, edit /etc/udev/rules.d/99-octoprint.rules when identifier is determined"
       UDEV=XXXXXXXXXX
   fi
   echo "Serial number detected as: "$UDEV
else
   echo "UDEV identifier (ENTER if unknown, edit /etc/udev/rules.d/99-octoprint.rules):"
   read UDEV
   if [ -z "$UDEV" ]; then
        UDEV=XXXXXXXXXXXXXX
   fi
fi

#octoprint_base is the generic .octoprint folder that contains all configuration, upload, etc.
echo "Octoprint instance base folder [/home/$USER/.octoprint]:"
read BFOLD
if [ -z "$BFOLD" ]; then
    BFOLD="/home/$USER/.octoprint"
fi

read -p "Do you want to proceed? " -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
   cat octoprint_default | sed -e "s/OCTOUSER/$OCTOUSER" -e "s/OCTOPATH/$OCTOPATH" -e "s/OCTOCONFIG/$OCTOCONFIG" -e "s/NEWINSTANCE/$INSTANCE/" -e "s/NEWPORT/$PORT/" > /etc/default/$INSTANCE
   cat octoprint_init | sed -e "s/NEWINSTANCE/$INSTANCE/" > /etc/init.d/$INSTANCE
   cat octoprint_udev | sed -e "s/NEWINSTANCE/$INSTANCE/" -e "s/UDEV/$UDEV/" >> /etc/udev/rules.d/99-octoprint.rules

   #Open port to be on safe side
   ufw allow $PORT/tcp

   #Need to make init.d file executable
   chmod +x /etc/init.d/$INSTANCE
   #Append our port in the port list
   echo $PORT >> /etc/octoprint_ports
   #copy all files to our new directory
   cp -rp $BFOLD .$INSTANCE
   #Do config.yaml modifications here if needed..
   #sed -i "/s/PORT/$INSTANCE/" .$INSTANCE/config.yaml
   #TODO - Just add an entry after additionalPorts?
   cat $BFOLD/config.yaml | sed -e "s/INSTANCE/$INSTANCE/" > .$INSTANCE/config.yaml
   udevadm control --reload-rules
   udevadm trigger
   systemctl daemon-reload
   sleep 5
   systemctl start $INSTANCE
   systemctl enable $INSTANCE
fi