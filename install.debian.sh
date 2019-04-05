#!/bin/bash
# exit on failure
set -e
set -o pipefail

#############################################################################
#
# Aquameta Installer Script
#
# Does the following:
# - install apt packages
# - install python packages
# - install postgresql extensions
#
#############################################################################

# prompting and sanity checking
echo "                                           __          "
echo "_____    ________ _______    _____   _____/  |______   "
echo "\__  \  / ____/  |  \__  \  /     \_/ __ \   __\__  \  "
echo " / __ \< <_|  |  |  // __ \|  Y Y  \  ___/|  |  / __ \_"
echo "(____  /\__   |____/(____  /__|_|  /\___  >__| (____  /"
echo "     \/    |__|          \/      \/     \/          \/ "
echo "            [ version 0.2.0 - base install ]"
echo ""
echo "                 OBLIGATORY WARNING:"
echo ""
echo "    This code is highly experimental and should "
echo "       NOT be run in a production environment."
echo "              You have been warned."
echo "                     ❤ MGMT."

read -p "Continue? [y/N]" -n 1 -r
echo    # (optional) move to a new line
if ! [[ $REPLY =~ ^[Yy]$ ]]
then
    exit 1
fi

# set working directory and destination directory
SRC="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# make sure we're running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

#############################################################################
# prompt for $DEST location
#############################################################################
read -p "Installation directory [/opt/aquameta]: " DEST
DEST=${DEST:-/opt/aquameta}


#############################################################################
# apt packages
#############################################################################

echo "Adding apt repositories..."
add-apt-repository "deb http://deb.debian.org/debian/ stretch main contrib non-free"
add-apt-repository "deb-src http://deb.debian.org/debian/ stretch main contrib non-free"
add-apt-repository "deb http://security.debian.org/ stretch/updates main contrib non-free"
add-apt-repository "deb-src http://security.debian.org/ stretch/updates main contrib non-free"
add-apt-repository "deb http://deb.debian.org/debian/ stretch-updates main contrib non-free"
add-apt-repository "deb-src http://deb.debian.org/debian/ stretch-updates main contrib non-free"

echo "Adding PostgreSQL apt repository..."
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
RELEASE=$(lsb_release -cs)
echo "deb http://apt.postgresql.org/pub/repos/apt/ ${RELEASE}"-pgdg main | sudo tee  /etc/apt/sources.list.d/pgdg.list



echo "Installing dependencies via apt..."
# update
apt-get update -y

# add the universe repository


# install required packages
DEBIAN_FRONTEND=nointeractive \
	apt-get install -y postgresql-10 postgresql-10-plv8 postgresql-10-python-multicorn \
	postgresql-server-dev-10 postgresql-plpython-10 python-pip \
	python-werkzeug python-psycopg2 nginx sudo sendmail \
	fuse \
	libssl-dev libpcre3 libpcre3-dev


#############################################################################
# sendmail
#############################################################################

# locale-gen "en_US.UTF-8" && dpkg-reconfigure locales
# echo `tail -1 /etc/hosts`.localdomain >> /etc/hosts



#############################################################################
# python packages
#############################################################################

echo "Installing core python packages..."

pip install requests fusepy

# filesystem_fdw
cd $SRC/src/py-package/filesystem_fdw
sudo -H pip install --upgrade .

# aquameta-endpoint
cd $SRC/src/py-package/uwsgi-endpoint
sudo -H pip install --upgrade .



#############################################################################
# aquameta postgresql extensions
#############################################################################

# install extensions into PostgreSQL's extensions/ directory
echo "Building core PostgreSQL extensions..."
cd $SRC/src/pg-extension/pg_catalog_get_defs && make && make install
cd $SRC/src/pg-extension/meta && make && make install
cd $SRC/src/pg-extension/bundle && make && make install
cd $SRC/src/pg-extension/filesystem && make && make install
cd $SRC/src/pg-extension/email && make && make install
cd $SRC/src/pg-extension/event && make && make install
cd $SRC/src/pg-extension/endpoint && make && make install
cd $SRC/src/pg-extension/widget && make && make install
cd $SRC/src/pg-extension/semantics && make && make install



#############################################################################
# build the aquameta database
#############################################################################

echo "Configuring PostgreSQL..."
# enable peer authentication
sudo sed -i "s/^local   all.*$/local all all trust/" /etc/postgresql/10/main/pg_hba.conf
systemctl restart postgresql.service

# create aquameta database
sudo -u postgres createdb aquameta
sudo -u postgres psql -c "alter database aquameta set bytea_output to 'hex'" aquameta

# create dependency extensions required by aquameta
echo "Installing dependency extensions..."
sudo -u postgres psql -c "create extension if not exists plpythonu" aquameta
sudo -u postgres psql -c "create extension if not exists multicorn schema public" aquameta
sudo -u postgres psql -c "create extension if not exists hstore schema public" aquameta
sudo -u postgres psql -c "create extension if not exists hstore_plpythonu schema public" aquameta
sudo -u postgres psql -c "create extension if not exists dblink schema public" aquameta
sudo -u postgres psql -c "create extension if not exists \"uuid-ossp\"" aquameta
sudo -u postgres psql -c "create extension if not exists pgcrypto schema public" aquameta
sudo -u postgres psql -c "create extension if not exists postgres_fdw" aquameta
sudo -u postgres psql -c "create extension if not exists plv8" aquameta

# create aquameta core extensions
echo "Installing core Aquameta extensions..."
sudo -u postgres psql -c "create extension pg_catalog_get_defs schema pg_catalog" aquameta
sudo -u postgres psql -c "create extension meta" aquameta
sudo -u postgres psql -c "create extension bundle" aquameta
sudo -u postgres psql -c "create extension filesystem" aquameta
sudo -u postgres psql -c "create extension email" aquameta
sudo -u postgres psql -c "create extension event" aquameta
sudo -u postgres psql -c "create extension endpoint" aquameta
sudo -u postgres psql -c "create extension widget" aquameta
sudo -u postgres psql -c "create extension semantics" aquameta
sudo -u postgres psql -f $SRC/src/sql/ide/000-ide.sql aquameta



#############################################################################
# install and checkout enabled bundles
#############################################################################

echo "Setting up $DEST/..."
mkdir --parents $DEST
cp -R $SRC/bundles-available $DEST
cp -R $SRC/bundles-enabled $DEST
chown -R postgres:postgres $DEST/bundles-available
chown -R postgres:postgres $DEST/bundles-enabled

echo "Loading bundles-enabled/*/*.csv ..."
for D in `find $DEST/bundles-enabled/* \( -type l -o -type d \)`
do
    sudo -u postgres psql -c "select bundle.bundle_import_csv('$D')" aquameta
done

echo "Checking out head commit of every bundle ..."
sudo -u postgres psql -c "select bundle.checkout(c.id) from bundle.commit c join bundle.bundle b on b.head_commit_id = c.id;" aquameta



#############################################################################
# configure uwsgi and start the service
#############################################################################

echo "Setting up uWSGI service..."
mkdir -p /etc/aquameta
# copy service file into /etc/systemd/system
cp $SRC/src/py-package/uwsgi-endpoint/aquameta.emperor.uwsgi.service /etc/systemd/system

# copy uwsgi .ini file into /etc/uwsgi/uwsgi-emperor.ini
cp $SRC/src/py-package/uwsgi-endpoint/uwsgi-emperor.ini /etc/aquameta

systemctl enable aquameta.emperor.uwsgi.service
systemctl restart aquameta.emperor.uwsgi.service



#############################################################################
# configure nginx and restart the service
#############################################################################

echo "Setting up nginx..."
cp $SRC/src/py-package/uwsgi-endpoint/nginx/aquameta_endpoint.conf /etc/nginx/sites-available
cd /etc/nginx/sites-enabled
rm -f ./default
ln -sf ../sites-available/aquameta_endpoint.conf
systemctl restart nginx



#############################################################################
# setup aquameta superuser
#############################################################################

echo "Superuser Registration"
echo "----------------------"
echo "Enter the name, email and password of the user you'd like to setup as superuser:"
read -p "Full Name: " NAME
read -p "Email Address: " EMAIL
read -p "PostgreSQL Username [$(logname)]: " ROLE
if [[ $ROLE = '' ]]
then
	ROLE=$(logname)
fi
read -s -p "Password: " PASSWORD

echo ""
echo "Creating superuser...."
REG_COMMAND="select endpoint.register_superuser('$EMAIL', '$PASSWORD', '$NAME', '$ROLE')"
sudo -u postgres psql -c "$REG_COMMAND" aquameta


#############################################################################
# grant default permissions for 'anonymous' and 'user' roles
#############################################################################

echo ""
echo "New User Registration Scheme"
echo "----------------------------"
echo "Please select a security scheme:"
echo "a) PRIVATE - No anonymous access, no anonymous user registration"
echo "b) OPEN REGISTRATION - Anonymous users may register for an account and read limited data"

until [[ $REPLY =~ ^[AaBb]$ ]]; do
	read -p "Choice? [a/B] " -n 1 -r
    echo
done

sudo -u postgres psql -f $SRC/src/privileges/000-general.sql aquameta

if [[ $REPLY =~ ^[Aa]$ ]]; then
	echo "Installing PRIVATE security scheme..."
	sudo -u postgres psql -f $SRC/src/privileges/001-anonymous.sql aquameta
else if [[ $REPLY =~ ^[Bb]$ ]]; then
        echo "Installing OPEN REGISTRATION scheme..."
        sudo -u postgres psql -f $SRC/src/privileges/001-anonymous-register.sql aquameta
    fi
fi

sudo -u postgres psql -f $SRC/src/privileges/002-user.sql aquameta




#############################################################################
# finished!
#############################################################################
MACHINE_IP=`hostname --ip-address|cut -d ' ' -f1`
EXTERNAL_IP=`dig +short myip.opendns.com @resolver1.opendns.com`

echo ""
echo "Aquameta was successfully installed.  Next, login and configure your installation:"
echo ""
echo "Localhost link: http://localhost/setup"
echo "Machine link:   http://$MACHINE_IP/setup"
echo "External link:  http://$EXTERNAL_IP/setup"
