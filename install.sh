#!/bin/bash
#
# Script to help download src, build and install softEther VPN https://github.com/SoftEtherVPN/SoftEtherVPN
# Script is tested on Ubuntu 18.04
#
# The latest version of this script is available at: https://github.com/legale/softether-vpn-installer
#
# Script version
#
# Colors
# Black        0;30     Dark Gray     1;30
# Red          0;31     Light Red     1;31
# Green        0;32     Light Green   1;32
# Brown/Orange 0;33     Yellow        1;33
# Blue         0;34     Light Blue    1;34
# Purple       0;35     Light Purple  1;35
# Cyan         0;36     Light Cyan    1;36
# Light Gray   0;37     White         1;37

RED='\033[0;31m';
GREEN='\033[0;32m';
BLUE='\033[0;34m';
NC='\033[0m'; # No Color

ver='0.0.0.0.2';
log='';
update='';
suflag='';
SCRIPT=$(readlink -f $0)
SCRIPTPATH=`dirname $SCRIPT`
logfile="$SCRIPTPATH/install.log";

HUB='vpn'
ROUTER_IP='192.168.168.1'
NETWORK='192.168.168.0'
ROUTER_INTERFACE="tap_$HUB"

#secondary functions

bigecho() {
	#return 1 if argument 1 is empty
	[[ -z $1 ]] && return 1
	#size
	[[ -z $2 ||  $2 > 1 ]] && size=0 || size=$2 
	
	case $size in
		0)
			printf "$1\n";;
		1)
			printf "# $1\n";;
		2)
			printf "## $1\n";;
	esac
}

log() { 
	#return 1 if argument 1 is empty
	[[ -z $1 ]] && return 1

	[[ -n $log ]] && echo "Log Message: $1" >> $logfile	 
	bigecho "${GREEN}Log message:${NC} $1"
}
exiterr() { 
	[[ -n $log ]] && echo "Error message: $1" >> $logfile	
	bigecho "${RED}Error message:${NC} $1"
	exit 1
}

get_external_ip() {
	log "trying to get external ip address"
	INTERFACES=$(ip link show | grep -o '^.\+BROADCAST' | cut -d ' ' -f 2 | cut -d ':' -f 1)
	for INTERFACE in $INTERFACES; do
		log "check interface: $INTERFACE"
		echo "$INTERFACE" | grep -i 'tap_'
		if [[ $? != 0 ]]; then
			log "i think i got you $INTERFACE"
			EXTERNAL_IP=$(ip addr show dev $INTERFACE | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*')
			[[ -n $EXTERNAL_IP ]] && log "external ip address is: $EXTERNAL_IP" || exiterr "unable to get external ip address"
			break
		fi
	done
	return 0
}

# secondary functions END

welcome(){
	clear
	bigecho "${BLUE}SoftEther VPN${NC} installer version $ver" 1

	echo -n 'Type yes to continue: '
	read answer
	[[ $answer != 'yes' ]] && exit 0

	echo -n 'Want to create install.log? (y/n) default "y": '
	read answer
	[[ -z $answer || $answer == 'y' ]] && log='true' 

	echo -n 'update and upgrade system packets? (y/n) default "y": '
	read answer
	[[ -z $answer || $answer == 'y' ]] && update='true' 
	
	#creating empty logfile
	[[ -n $log ]] && echo '' > $logfile
	log 'Checking superuser rights.'
	[[ "$(id -u)" == 0 ]] && log 'superuser rights found.' || exiterr 'superuser rights not found.' 
}

apt_update() {
	log 'apt-get update && apt-get update && apt-get upgrade -y'
	apt-get update && apt-get upgrade -y > /dev/null 2>&1
	[[ $? == 0 ]] && log 'done' || exiterr 'failed'
}

systemd-resolved_config() {
	log "/lib/systemd/systemd-resolved listen on port 53 by default to provide DNS service."
	log "check tcp port 53 via fuser 53/tcp"
	str=$(fuser 53/tcp)
	log "fuser returns: $?"
	if [[ $? == 0 ]]; then
		log 'trying to change /etc/systemd/resolved.conf'
		grep -i '^DNSStubListener' /etc/systemd/resolved.conf
		if [[ $? == 0 ]]; then
			log 'DNSStubListener param found. trying to set DNSStubListener=no'
			sed -i 's%\(^DNSStubListener=\).*$%\1no%i' /etc/systemd/resolved.conf
		else
			log 'DNSStubListener param not found. trying to add DNSStubListener=no'
			echo 'DNSStubListener=no' >> /etc/systemd/resolved.conf
		fi
		
		check=$(grep -i '^DNSStubListener' /etc/systemd/resolved.conf)
		log "check DNSStubListener param is: $check"
		grep -i '^DNSStubListener=no' /etc/systemd/resolved.conf
		[[ $? == 0 ]] && log 'done' || exiterr 'failed'
		log 'restarting systemd-resolved'
		systemctl restart systemd-resolved
		[[ $? == 0 ]] && log 'done' || exiterr 'failed'
	fi
	
}

install_packets() { 
# Установка пакетов для сборки softether
# checkinstall нужен для создания deb пакета из скриптового инсталятор
	log 'installing packets iptables-persistent dnsmasq psmisc git checkinstall gcc libncurses-dev libreadline-dev make cmake libssl-dev zlib1g-dev libreadline-dev zlib1g-dev libncurses-dev'
	apt-get -y install iptables-persistent dnsmasq psmisc git checkinstall gcc libncurses-dev libreadline-dev make cmake libssl-dev zlib1g-dev libreadline-dev zlib1g-dev libncurses-dev > /dev/null 2>&1
	[[ $? == 0 ]] && log 'done' || log 'failed' 
}

download_and_make() {
	# Скачивание репозитория Stable версии
	cd /tmp
	if [[ ! -e '/tmp/SoftEtherVPN_Stable' ]]; then
		log 'git clone --depth=0 https://github.com/SoftEtherVPN/SoftEtherVPN_Stable.git'
		git clone https://github.com/SoftEtherVPN/SoftEtherVPN_Stable.git > /dev/null 2>&1
		[[ $? == 0 ]] && log 'done' || exiterr 'failed'
	else
		log '/tmp/SoftEtherVPN_Stable is exists. Download skipped.';
	fi
	
	log './configure'
	# Компилирование исполняемых файлов
	cd /tmp/SoftEtherVPN_Stable
	./configure > /dev/null 2>&1
	[[ $? == 0 ]] && log 'done' || exiterr 'failed'
	
	log 'make'
	make > /dev/null 2>&1
	[[ $? == 0 ]] && log 'done' || exiterr 'failed'
	
	log 'modifying Makefile...' 
	#меняем переменные в Makefile, чтобы vpnserver установился в /opt/vpnserver, а не /usr/local/vpnserver usr/local/vpncmd и т.д.
	sed -i 's%\(^INSTALL_VPNSERVER_DIR=\).*$%\1/opt/vpnserver/%' Makefile > /dev/null 2>&1
	sed -i 's%\(^INSTALL_VPNBRIDGE_DIR=\).*$%\1/opt/vpnserver/%' Makefile > /dev/null 2>&1
	sed -i 's%\(^INSTALL_VPNCLIENT_DIR=\).*$%\1/opt/vpnserver/%' Makefile > /dev/null 2>&1
	sed -i 's%\(^INSTALL_VPNCMD_DIR=\).*$%\1/opt/vpnserver/%' Makefile > /dev/null 2>&1
	[[ $? == 0 ]] && log 'done' || exiterr 'failed'
	
}

install_vpn() {
	log 'check if vpnserver exists'
	str=$(which vpnserver)
	if [[ $? == 0 ]]; then
		log "vpnserver found in $str"
		log "vpnserver stop and killall vpnserver"
		vpnserver stop > /dev/null 2>&1
		sleep 3 > /dev/null 2>&1
		killall vpnserver > /dev/null 2>&1
	fi
	
	log 'check if /opt/vpnserver/vpn_server.config exists'
	# backup old config
	if [[ -e /opt/vpnserver/vpn_server.config || -h /opt/vpnserver/vpn_server.config ]]; then
		configfile_old='/tmp/vpn_server.config_temp';
		log "config found. moving to $configfile_old"
		mv /opt/vpnserver/vpn_server.config $configfile_old > /dev/null 2>&1
		[[ $? == 0 ]] && log 'done' || exiterr 'failed'
	else
		log 'old config not found'
	fi
	
	log 'check if softethervpn-stable is installed'
	dpkg -l softethervpn-stable > /dev/null 2>&1
	log "dpkg -l softethervpn-stable return $?"
	if [[ $? == 0 ]]; then
		log 'trying to remove package dpkg -r softethervpn-stable'
		dpkg -r softethervpn-stable > /dev/null 2>&1
		[[ $? == 0 ]] && log 'done' || exiterr 'failed'
	else
		log 'softethervpn-stable is no installed'
	fi
	log 'removing /opt/vpnserver if exists'
	if [[ -e /opt/vpnserver || -h /opt/vpnserver ]]; then
		rm -Rf /opt/vpnserver > /dev/null 2>&1
		[[ $? == 0 ]] && log 'done' || exiterr 'failed'
	else
		log '/opt/vpnserver not found'
 	fi
	
	if [[ -n $configfile_old ]]; then
		configfile_save='/opt/vpnserver/vpn_server.config.save'
		log "copying $configfile_old to $configfile_save"
		mkdir /opt/vpnserver > /dev/null 2>&1
		cp $configfile_old $configfile_save > /dev/null 2>&1
		[[ $? == 0 ]] && log 'done' || exiterr 'failed'
	fi
	
	log 'installing via checkinstall to /opt/vpnserver'
	#Установка
	checkinstall -y > /dev/null 2>&1
	[[ $? == 0 ]] && log 'done' || exiterr 'failed'
}


vpnserver_config() {
#удаляем старый конфиг, если он есть
[[ -e /etc/vpn_server.config || -h /etc/vpn_server.config ]] && rm -Rf /etc/vpn_server.config > /dev/null 2>&1
#create symlink for config to /etc/vpn_server.config 
ln -s /opt/vpnserver/vpn_server.config /etc/vpn_server.config > /dev/null 2>&1
[[ $? == 0 ]] && log 'done' || exiterr 'failed'

log 'vpnserver starting to create config.'
#запускаем сервер
vpnserver start
[[ $? == 0 ]] && log 'done' || exiterr 'failed'
sleep 3

log 'vpnserver stop and killall vpnserver'
vpnserver stop
[[ $? == 0 ]] && log 'done' || exiterr 'failed'
sleep 3
killall vpnserver


# Server setup
# Настраиваем сервер
# Сначала отключаем dynamic dns. Можно сделать только через конфиг вручную
log 'disabling ddns in config /opt/vpnserver/vpn_server.config'
sed -i "/declare DDnsClient/{n;n;s/\(Disabled\) false/\1 true/}" /opt/vpnserver/vpn_server.config
[[ $? == 0 ]] && log 'done' || exiterr 'failed'

str=$(sed -n "/declare DDnsClient/{n;n;p}" /opt/vpnserver/vpn_server.config)
log "config file string: $str"
echo "$str" | grep -i 'true'
[[ $? == 0 ]] && log 'done' || exiterr 'failed'	
	
	
log 'vpnserver starting.'
#запускаем сервер
vpnserver start
[[ $? == 0 ]] && log 'done' || exiterr 'failed'
sleep 2

#Отключаем все порты кроме 5555
log "disable all vpnserver configuration interface ports except 5555"
vpncmd localhost:5555 /SERVER /CMD ListenerDisable 443 > /dev/null 2>&1
vpncmd localhost:5555 /SERVER /CMD ListenerDisable 992 > /dev/null 2>&1
vpncmd localhost:5555 /SERVER /CMD ListenerDisable 1194 > /dev/null 2>&1

# Отключение Keep Alive Internet Connection
log "Disable keep alive signals"
vpncmd localhost:5555 /SERVER /CMD KeepDisable  > /dev/null 2>&1

# Выбор более устойчивого алгоримта шифрования чем установлен по умолчанию
log "Set stronger encryption algo AES256-SHA"
vpncmd localhost:5555 /SERVER /CMD ServerCipherSet AES256-SHA > /dev/null 2>&1

# Удаляем стандартный хаб
log "delete default Hub"
vpncmd localhost:5555 /SERVER /CMD HubDelete DEFAULT > /dev/null 2>&1

# Создание нового хаба и введение пароля хаба
# Рекомендую на этом шаге пароль оставить пустой, 
# чтобы не вводить его во всех слудующих комнадах
log "create Hub $HUB with pass"
vpncmd localhost:5555 /SERVER /CMD HubCreate $HUB /password:'' > /dev/null 2>&1

# Создание группы пользователей 
log "create group Users"
vpncmd localhost:5555 /SERVER /HUB:$HUB /CMD GroupCreate Users /REALNAME:Users /NOTE:none > /dev/null 2>&1


# Отключение логгирования пакетов в данном хабе
vpncmd localhost:5555 /SERVER /HUB:$HUB /CMD LogDisable package > /dev/null 2>&1

# Включение протокола L2TP на хабе VPN
# Не забудьте сменить ключ PSK на свой!
vpncmd localhost:5555 /SERVER /CMD IPsecEnable /L2TP:yes /L2TPRAW:no /ETHERIP:no /PSK:vpn /DEFAULTHUB:$HUB > /dev/null 2>&1

# disable SSTP
vpncmd localhost:5555 /SERVER /CMD SstpEnable Disable > /dev/null 2>&1

# creating bridge
vpncmd localhost:5555 /SERVER /CMD BridgeCreate $HUB /DEVICE:$HUB /TAP:yes > /dev/null 2>&1

# Создание пользователя в ново-созданной группе
log "create user ru"
vpncmd localhost:5555 /SERVER /HUB:$HUB /CMD UserCreate ru /GROUP:Users /REALNAME:"ru" /NOTE:none > /dev/null 2>&1

# Задаем пароль
log "user password setup"
vpncmd localhost:5555 /SERVER /HUB:$HUB /CMD UserPasswordSet ru > /dev/null 2>&1

# hub pass
log "set Hub password"
vpncmd localhost:5555 /SERVER /HUB:$HUB /CMD SetHubPassword 

# admin pass
log "set vpnserver admin access password"
vpncmd localhost:5555 /SERVER /CMD ServerPasswordSet 
}


init.d_config() {
log "create /etc/init.d/vpnserver start script"
touch /etc/init.d/vpnserver
chmod +x /etc/init.d/vpnserver
cat > /etc/init.d/vpnserver << EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          vpnserver
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start daemon at boot time
# Description:       Enable Softether by daemon.
### END INIT INFO
DAEMON=vpnserver
LOCK=/var/lock/subsys/vpnserver
TAP_ADDR=$ROUTER_IP
TAP_INTERFACE=$ROUTER_INTERFACE
test -x $DAEMON || exit 0
case "\$1" in
start)
\$DAEMON start
touch \$LOCK
sleep 1
/sbin/ip address add \$TAP_ADDR/24 dev \$TAP_INTERFACE
;;
stop)
\$DAEMON stop
rm \$LOCK
;;
restart)
\$DAEMON stop
sleep 3
\$DAEMON start
sleep 1
/sbin/ip address add \$TAP_ADDR/24 dev \$TAP_INTERFACE 
;;
*)
echo "Usage: \$0 {start|stop|restart}"
exit 1
esac
exit 0
EOF
log "update-rc.d vpnserver defaults"
update-rc.d vpnserver defaults
}

dnsmasq_config() {
log "dnsmasq config create for interface $ROUTER_INTERFACE"
cat > /etc/dnsmasq.conf <<EOF
# added by https://github.com/legale/softether-vpn-installer
port=0
interface = $ROUTER_INTERFACE
dhcp-range = $ROUTER_INTERFACE,192.168.168.10,192.168.168.254,3h
dhcp-option = $ROUTER_INTERFACE,option:router,$ROUTER_IP
EOF
service dnsmasq restart
}

iptables_config() {
log "list current iptables nat rules"
str=$(iptables -L --line-numbers -t nat)
log "current rules are: $str"
log "search rule for our network $NETWORK"
echo "$str" | grep -i $NETWORK > /dev/null 2>&1
if [[ $? == 0 ]]; then
	log "$NETWORK found"
	log "trying to delete all rules for the network $NETWORK"
	RULE=$(iptables -L --line-numbers -t nat | grep -io -m 1 "^.\+$NETWORK.\+$" | cut -d ' ' -f 1)
	while [[ -n $RULE ]]; do
		log "iptables -t nat -D POSTROUTING $RULE"
		iptables -t nat -D POSTROUTING $RULE > /dev/null 2>&1
		RULE=$(iptables -L --line-numbers -t nat | grep -io -m 1 "^.\+$NETWORK.\+$" | cut -d ' ' -f 1)
	done
fi
log "iptables -t nat -A POSTROUTING -s $NETWORK/24 -j SNAT --to-source $EXTERNAL_IP"
iptables -t nat -A POSTROUTING -s $NETWORK/24 -j SNAT --to-source $EXTERNAL_IP > /dev/null 2>&1
[[ $? == 0 ]] && log 'done' || exiterr 'failed'

log "iptables-save >/etc/iptables/rules.v4"
iptables-save >/etc/iptables/rules.v4
[[ $? == 0 ]] && log 'done' || exiterr 'failed'

log "iptables-save >/etc/iptables/rules.v6"
ip6tables-save >/etc/iptables/rules.v6
[[ $? == 0 ]] && log 'done' || exiterr 'failed'

}

sysctl_config() {
	log 'trying to change /etc/sysctl.conf'
	grep -i '^net\.ipv4\.ip_forward' /etc/sysctl.conf
	if [[ $? == 0 ]]; then
		log 'net.ipv4.ip_forward param found. trying to enable'
		sed -i 's%\(^net\.ipv4\.ip_forward\).*$%\1=1%i' /etc/sysctl.conf
	else
		log 'net.ipv4.ip_forward param not found. trying to add net.ipv4.ip_forward=1'
		echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
	fi
	
	check=$(grep -i '^net\.ipv4\.ip_forward' /etc/sysctl.conf)
	log "check net.ipv4.ip_forward param is: $check"
	grep -i '^net\.ipv4\.ip_forward=1' /etc/sysctl.conf
	[[ $? == 0 ]] && log 'done' || exiterr 'failed'
	log "run sysctl --system"
	sysctl --system  > /dev/null 2>&1
}
welcome 
[[ -n $update ]] && apt_update
get_external_ip
install_packets
download_and_make
install_vpn
vpnserver_config
init.d_config
dnsmasq_config
iptables_config
sysctl_config

service vpnserver restart

exit 0
