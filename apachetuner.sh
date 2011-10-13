#!/bin/bash
# Credits Gus Maskowitz, Rob Wilderspin, Dan Farmer, Mark Hyde

# ===================================== DO SECTION =====================================
ME=`whoami`
LAST_ECHO=0
TYPE_ECHO=0

if [ "$ME" != "root" ]; then
  echo "You'll need to be root to run this"
  exit 1
fi

/sbin/service httpd status 2>&1 >/dev/null
if [ $? -ne 0 ]; then
 exit 0
fi

apachetuner_version="Apachetuner  v1.0"

if [ -f /etc/redhat-release ]; then
  system=$(cat /etc/redhat-release)
else
  echo "This does not appear to be Red-Hat and is unfortunately not yet supported"
  exit 0 
fi

# This was written specifically for a Rackspace environment
if [ -f /root/.rackspace/server_number ]; then
  server_number=$(cat /root/.rackspace/server_number)
fi

server_name=$(uname -n)
server_httpd_rpm=$(rpm -qf $(which httpd))
memtotal_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)

# mem_alert_level=$(echo $memtotal_mb | awk '{printf "%d", $0 * 0.9}')

#### The following cointributed by Mark Hyde
HTTPD_V_TMPFILE=$(mktemp)
httpd -V > $HTTPD_V_TMPFILE
apache_architecture=$(awk -F': +' '$1~/^Architecture/{print $2}' ${HTTPD_V_TMPFILE} )
apache_mpm=$(awk -F': +' '$1~/^Server MPM/{print $2}' ${HTTPD_V_TMPFILE} )
apache_server_version=$(awk -F': +' '$1~/^Server version/{print $2}' ${HTTPD_V_TMPFILE} )

config_file='/etc/httpd/conf/httpd.conf'

# Thank you to Rob Wilderspin for this magic...
eval $(awk '/\<IfModule prefork.c\>/,/<\/IfModule/ \
      {/^ServerLimit/ && s=$2; /^MaxClients/ && m=$2} \
      END {printf "serverlimit=%d maxclients=%d", s, m}' $config_file)

httpd_root=$(awk -F\" '/HTTPD_ROOT/ {print $2}' $HTTPD_V_TMPFILE)
httpd_server_config_file=$(awk -F\" '/SERVER_CONFIG_FILE/ {print $2}' $HTTPD_V_TMPFILE)
httpd_default_errorlog=$(awk -F\" '/DEFAULT_ERRORLOG/ {print $2}' $HTTPD_V_TMPFILE)

# Dan Farmer created this logic to find the size of each additional apache in memory.
apacheuser=$(ps -ef|awk '/httpd/ && !/root/ {print $1}' | uniq)
num_of_apache_children=$(ps -u $apacheuser -o pid= | wc -l)
apache_in_ram=$(ps -u $apacheuser -o pid= | xargs pmap -d | awk '/private/ {c+=1; sum+=$4} END {printf "%.2f", sum/c/1024}')

apache_footprint=$(echo $apache_in_ram*$num_of_apache_children | bc -l)
ram_at_maxc=$(echo $maxclients*$apache_in_ram|bc -l)

mem_percentage_at_max=$(echo $ram_at_maxc/$memtotal_mb*100 | bc -l)
# echo $mem_percentage_at_max

if [ -f /etc/php.ini ]; then
 php_meml=$(awk '/^memory_limit/ {print $3}' /etc/php.ini);
else
  echo "Checking for /etc/php.ini	Not found";
fi

http_binary=$(netstat -plnt |grep :80|awk -F/ '{print $2'})

# =================================== DISPLAY SECTION ===================================
echo "
=========================SYSTEM========================="

echo "$system
"
# This was written specifically for a Rackspace environment
if [ -f /root/.rackspace/server_number ]; then
echo "Server Number:                  $server_number
"
fi
echo "Server Name:			$server_name
Total Physical Memory:		$memtotal_mb MB

=========================APACHE========================="

echo "Version:			$apache_server_version
RPM:				$server_httpd_rpm
httpd binary:			$(which $http_binary)
Whats running on port 80	$(netstat -plnt |grep :80|awk '{print $7}')
Apache Architecture:		$apache_architecture"

echo "Serverlimit is:			$serverlimit
MaxClients is:			$maxclients"

echo "httpd root			$httpd_root
httpd server config file	$httpd_root/$httpd_server_config_file
httpd default errorlog		$httpd_root/$httpd_default_errorlog"

echo "
=========================PHP============================
/etc/php.ini memory_limit is:	$php_meml

=====================APACHE RUNTIME=====================
Apache user:			$apacheuser
Average Memory use:		$apache_in_ram MB per child
Number of children:		$num_of_apache_children

=========================REPORT==========================
Current memory footprint	$apache_footprint MB
Maximum memory footprint	$ram_at_maxc MB ($(printf %0.f $mem_percentage_at_max)% of installed RAM)

System memory divided by MaxClients		$(printf %0.00f $(echo $memtotal_mb/$maxclients |bc -l))
System memory divided by Apache child size	$(printf %0.f $(echo $memtotal_mb/$apache_in_ram | bc -l))
"

rm "$HTTPD_V_TMPFILE"
echo
