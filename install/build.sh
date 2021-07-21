#!/bin/bash

if [ -e "/opt/template" ]
then

## Set variables
CONTAINERIP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')

#config rsyslog

cp /etc/rsyslog.conf /etc/rsyslog.conf.bak
sed -i 's|SysSock.Use="off")|SysSock.Use="on")|g' /etc/rsyslog.conf
sed -i 's|module(load="imjournal"|#module(load="imjournal"|g' /etc/rsyslog.conf
sed -i 's|StateFile="imjournal.state"|#StateFile="imjournal.state"|g' /etc/rsyslog.conf
rsyslogd

#
###Install Mailwatch
##Install Nginx, php-fpm, mariadb
#nginx
yum install nginx -y
cp -vp /opt/template/nginx/mailwatch.conf /etc/nginx/conf.d/
cp -vp /opt/template/nginx/policyd.conf /etc/nginx/conf.d/
sed -i "s|domain.com|$DOMAIN|" /etc/nginx/conf.d/mailwatch.conf
sed -i "s|domain.com|$DOMAIN|" /etc/nginx/conf.d/policyd.conf
#php-fpm
yum install https://rpms.remirepo.net/enterprise/remi-release-8.rpm -y
yum module enable php:remi-7.4 -y
yum install php php-fpm php-gd php-json php-mbstring php-mysqlnd php-xml php-xmlrpc php-opcache php-curl php-pecl-zip -y
cp -vp /etc/php-fpm.d/www.conf /etc/php-fpm.d/www.conf.bak
sed -i "s|^\user = apache|user = nginx|" /etc/php-fpm.d/www.conf && \
sed -i "s|^\group = apache|group = nginx|" /etc/php-fpm.d/www.conf && \
sed -i "s|^\;listen.owner = nobody|listen.owner = nginx|" /etc/php-fpm.d/www.conf && \
sed -i "s|^\;listen.group = nobody|listen.group = nginx|" /etc/php-fpm.d/www.conf && \
sed -i "s|^\;listen.mode = 0660|listen.mode = 0660|" /etc/php-fpm.d/www.conf && \
sed -i "s|^\listen.acl_users = apache,nginx|;listen.acl_users = apache,nginx|" /etc/php-fpm.d/www.conf
mkdir -p /run/php-fpm/
chown -R nginx. /var/lib/php/session

sleep 10
#Mariadb

wget https://downloads.mariadb.com/MariaDB/mariadb_repo_setup
chmod +x mariadb_repo_setup
./mariadb_repo_setup
yum install MariaDB-server MariaDB-client -y
nohup sudo -u mysql /sbin/mariadbd &
rm -rf mariadb_repo_setup

sleep 10
##Download và config Mailwatch

cd /opt/ && wget https://github.com/mailwatch/MailWatch/archive/refs/tags/v1.2.17.zip
unzip v1.2.17.zip
rm v1.2.17.zip
mv MailWatch-1.2.17 MailWatch
sed -i "s|512|255|g" /opt/MailWatch/create.sql

cd /opt/MailWatch/ && mysql < create.sql
mysql -u root -e "GRANT ALL ON mailscanner.* TO mailwatch@localhost IDENTIFIED BY '$MAILSCANNERPASS';" \
-e "GRANT FILE ON *.* TO mailwatch@localhost IDENTIFIED BY '$MAILSCANNERPASS';" \
-e "FLUSH PRIVILEGES;"

sed -i "s|^\my (\$db_pass) = 'mailwatch';|my (\$db_pass) = '$MAILSCANNERPASS';|" /opt/MailWatch/MailScanner_perl_scripts/MailWatchConf.pm


mysql mailscanner -u root \
-e "INSERT INTO users SET username = 'admin', password = MD5('$MAILWATCHPASS'), fullname = 'Admin', type = 'A';"

cd /opt/MailWatch/mailscanner/
chown root:nginx temp
chmod g+rw temp
cp conf.php.example conf.php
sed -i "s|^\define('DB_PASS', 'mailwatch');|define('DB_PASS', '$MAILSCANNERPASS');|" conf.php
sed -i "s|^\define('MAILWATCH_HOME', '/var/www/html/mailscanner');|define('MAILWATCH_HOME', '/opt/MailWatch/mailscanner');|" conf.php

sleep 10

#instal perl require
yum install "perl(DBD::mysql)" -y

#
####Install and config Postfix

#install postfix 3
yum -y install postfix

# config postfix main.cf
sed -i "s|^\#myhostname = host.domain.tld|myhostname = $HOSTNAME|" /etc/postfix/main.cf && \
sed -i "s|^\#mydomain = domain.tld|mydomain = $DOMAIN|" /etc/postfix/main.cf && \
sed -i "s|^\inet_interfaces = localhost|inet_interfaces = all|" /etc/postfix/main.cf
sed -i "s|^\#mynetworks = 168.100.189.0\/28, 127.0.0.0\/8|mynetworks = $CONTAINERIP\/32, 127.0.0.0\/8|" /etc/postfix/main.cf

sleep 10

cat /opt/template/postfix/extend_main.cf >> /etc/postfix/main.cf
rsync -av /opt/template/postfix/config/{body_checks,local_domains,postscreen_access.cidr,sender_access} /etc/postfix/
chmod 644 /etc/postfix/{body_checks,local_domains,postscreen_access.cidr,sender_access}
cat /opt/template/postfix/config/header_checks >> /etc/postfix/header_checks
cat /opt/template/postfix/config/transport >> /etc/postfix/transport
grep -RiIlr 'domain.com' /etc/postfix/ | xargs sed -i 's/domain.com/'$DOMAIN'/g'
sed -i "s|MAILBACKEND_HOST|$MAILBACKEND_HOST|" /etc/postfix/transport

postmap  /etc/postfix/local_domains
postmap  /etc/postfix/body_checks
postmap  /etc/postfix/sender_access
postmap  /etc/postfix/transport
postmap  /etc/postfix/header_checks

echo "enable postscreen"
sed -i '12s/^/#/' /etc/postfix/master.cf
sed -i '13s/.//' /etc/postfix/master.cf
sed -i '14s/.//' /etc/postfix/master.cf
sed -i '15s/.//' /etc/postfix/master.cf
sed -i '16s/.//' /etc/postfix/master.cf

sleep 10

#
###MailScanner
yum install subscription-manager -y
yum config-manager --set-enabled powertools
yum install -y perl-Cache-FastMmap perl-Config-IniFiles perl-Net-Server
wget https://github.com/MailScanner/v5/releases/download/5.3.4-3/MailScanner-5.3.4-3.rhel.noarch.rpm && \
yum localinstall MailScanner-5.3.4-3.rhel.noarch.rpm -y
rm -rf MailScanner-5.3.4-3.rhel.noarch.rpm
/usr/sbin/ms-configure --MTA=postfix --installEPEL=Y --installPowerTools=Y --installClamav=Y --configClamav=Y --installTNEF=Y --installUnrar=Y --installCPAN=Y --installDf=Y --SELPermissive=N --ignoreDeps=Y --ramdiskSize=1024

sleep 10

sed -i "s|run_mailscanner=0|run_mailscanner=1|g" /etc/MailScanner/defaults && \
sed -i "s|^\Run As User =|Run As User = postfix|" /etc/MailScanner/MailScanner.conf && \
sed -i "s|^\Run As Group =|Run As Group = mtagroup|" /etc/MailScanner/MailScanner.conf && \
sed -i "s|^\Incoming Queue Dir = \/var\/spool\/mqueue.in|Incoming Queue Dir = \/var\/spool\/postfix\/hold|" /etc/MailScanner/MailScanner.conf && \
sed -i "s|^\Outgoing Queue Dir = \/var\/spool\/mqueue|Outgoing Queue Dir = \/var\/spool\/postfix\/incoming|" /etc/MailScanner/MailScanner.conf && \
sed -i "s|^\MTA = sendmail|MTA = postfix|" /etc/MailScanner/MailScanner.conf && \
sed -i "s|^\Incoming Work User =|Incoming Work User = postfix|" /etc/MailScanner/MailScanner.conf && \
sed -i "s|^\Quarantine User =|Quarantine User = postfix|" /etc/MailScanner/MailScanner.conf && \
sed -i "s|^\Quarantine Group =|Quarantine Group = mtagroup|" /etc/MailScanner/MailScanner.conf && \
sed -i "s|^\Quarantine Permissions = 0660|Quarantine Permissions = 0644|" /etc/MailScanner/MailScanner.conf && \
sed -i "s|^\Quarantine Whole Message = no|Quarantine Whole Message = yes|" /etc/MailScanner/MailScanner.conf && \
sed -i "s|^\Sign Clean Messages = yes|Sign Clean Messages = no|" /etc/MailScanner/MailScanner.conf && \
sed -i "s|^\Notices To = postmaster|Notices To = postmaster@domain.com|" /etc/MailScanner/MailScanner.conf && \
sed -i "s|^\Virus Scanners = auto|Virus Scanners = clamd|" /etc/MailScanner/MailScanner.conf && \
sed -i "s|^\Is Definitely Not Spam = \%rules-dir\%\/spam.whitelist.rules|Is Definitely Not Spam = \&SQLWhitelist|" /etc/MailScanner/MailScanner.conf && \
sed -i "s|^\Is Definitely Spam = no|Is Definitely Spam = \&SQLBlacklist|" /etc/MailScanner/MailScanner.conf && \
sed -i "s|^\Definite Spam Is High Scoring = no|Definite Spam Is High Scoring = yes|" /etc/MailScanner/MailScanner.conf && \
sed -i "s|^\Spam Actions = deliver header \"X-Spam-Status: Yes\"|Spam Actions = store deliver header \"X-Spam-Status: Yes\"|" /etc/MailScanner/MailScanner.conf && \
sed -i "s|^\Always Looked Up Last = no|Always Looked Up Last = \&MailWatchLogging|" /etc/MailScanner/MailScanner.conf
sed -i "s|postmaster|postmaster@$DOMAIN|" /etc/MailScanner/MailScanner.conf

cp -vp /opt/template/custom.rules /etc/MailScanner/rules/

chown postfix.mtagroup /var/spool/postfix/{hold,incoming} && \
chown postfix.mtagroup /var/spool/MailScanner && \
chown postfix.root /var/spool/postfix && \
touch "/var/spool/MailScanner/incoming/Processing.db" && \
chown postfix.postfix "/var/spool/MailScanner/incoming/Processing.db" && \
touch /var/spool/MailScanner/incoming/SpamAssassin.cache.db && \
chown postfix.postfix /var/spool/MailScanner/incoming/SpamAssassin.cache.db && \
chown postfix.postfix /etc/MailScanner/rules/custom.rules

usermod -a -G mtagroup nginx
chgrp mtagroup /var/spool/postfix/incoming
chgrp mtagroup /var/spool/postfix/hold
chmod g+rx /var/spool/postfix/incoming
chmod g+rx /var/spool/postfix/hold

sed -i "s|^\#bayes_path /etc/MailScanner/bayes/bayes|bayes_path /etc/MailScanner/bayes/bayes|"  /etc/MailScanner/spamassassin.conf && \
sed -i "s|^\# bayes_file_mode 0770|bayes_file_mode 0664|"  /etc/MailScanner/spamassassin.conf
mkdir /etc/MailScanner/bayes
chown root:nginx /etc/MailScanner/bayes
chmod g+rws /etc/MailScanner/bayes
/bin/bash /opt/template/bayes/bayes_db.sh
sa-learn --restore /opt/template/bayes/bayes.txt
sa-update
sa-learn --sync
chown postfix:mtagroup /etc/MailScanner/bayes/bayes_*
chmod g+rw /etc/MailScanner/bayes/bayes*
spamassassin -D -p /etc/MailScanner/spamassassin.conf --lint

sleep 10

cd  /opt/MailWatch && cp tools/Cron_jobs/mailwatch /etc/cron.daily/
chmod +x /etc/cron.daily/mailwatch
grep -RiIl '/var/www/html/mailscanner/functions.php' /opt/MailWatch/ | xargs sed -i "s|/var/www/html/mailscanner/functions.php|/opt/MailWatch/mailscanner/functions.php|g"
cp /opt/MailWatch/tools/Cron_jobs/mailwatch_db_clean.php /usr/local/bin/
cp /opt/MailWatch/tools/Cron_jobs/mailwatch_quarantine_maint.php /usr/local/bin/
cp /opt/MailWatch/tools/Cron_jobs/mailwatch_quarantine_report.php /usr/local/bin/

sed -i "s|^\User_Alias MAILSCANNER = www-data|User_Alias MAILSCANNER = nginx|"  /opt/MailWatch/tools/sudo/mailwatch
cp /opt/MailWatch/tools/sudo/mailwatch /etc/sudoers.d/
chmod 440 /etc/sudoers.d/mailwatch

ln -s /opt/MailWatch/MailScanner_perl_scripts/MailWatch.pm /usr/share/MailScanner/perl/custom
ln -s /opt/MailWatch/MailScanner_perl_scripts/SQLBlackWhiteList.pm /usr/share/MailScanner/perl/custom
ln -s /opt/MailWatch/MailScanner_perl_scripts/SQLSpamSettings.pm /usr/share/MailScanner/perl/custom

rsync -av /opt/MailWatch/MailScanner_perl_scripts/MailWatchConf.pm /usr/share/MailScanner/perl/custom/

#
### Install extend && Config Clamd
yum -y install clamav-data
freshclam
sed -i "s|^\#TCPSocket 3310|TCPSocket 3310|"  /etc/clamd.d/scan.conf
#sed -i "s|^\#LocalSocket /var/run/clamd.scan/clamd.sock|LocalSocket /var/run/clamd.scan/clamd.sock|" /etc/clamd.d/scan.conf
sed -i "s|^\#LogFile /var/log/clamd.scan|LogFile /var/log/clamd.scan|" /etc/clamd.d/scan.conf
sed -i "s|^\Clamd Socket = /var/run/clamd.scan/clamd.sock|#Clamd Socket = /var/run/clamd.scan/clamd.sock|" /etc/MailScanner/MailScanner.conf



#
### Config Spamassassin
sed -i "s|^\# use_bayes 0|use_bayes 1|"  /etc/MailScanner/spamassassin.conf
sed -i "s|^\# bayes_auto_learn 0|bayes_auto_learn 1|"  /etc/MailScanner/spamassassin.conf

#
### Install && Config Cbpolicyd
mkdir -p /opt/cbpolicyd
cd /opt/cbpolicyd
wget https://download.policyd.org/v2.0.14/cluebringer-2.0.14-1.noarch.rpm
rpm -ivh cluebringer-2.0.14-1.noarch.rpm
wget https://download.policyd.org/v2.0.14/cluebringer-v2.0.14.zip
unzip cluebringer-v2.0.14.zip
rm -rf cluebringer-v2.0.14.zip cluebringer-2.0.14-1.noarch.rpm
cd /opt/cbpolicyd/cluebringer-v2.0.14/database

for i in core.tsql access_control.tsql quotas.tsql amavis.tsql checkhelo.tsql checkspf.tsql greylisting.tsql;
do
./convert-tsql mysql $i
done > policyd.sql
mysqladmin -u root create policyd
mysql -u root -e "CREATE USER 'policyd_user'@'localhost' IDENTIFIED BY '$POLICYDPASS';" \
-e "GRANT ALL PRIVILEGES ON policyd.* TO 'policyd_user'@'localhost';" \
-e "FLUSH PRIVILEGES;"
sed -i 's/TYPE=InnoDB CHARACTER SET latin1 COLLATE latin1_bin//' policyd.sql
mysql -u root policyd < policyd.sql

sed -i 's/#Username=root/Username=policyd_user/'  /etc/policyd/cluebringer.conf
sed -i 's/#Password=/Password='$POLICYDPASS'/g'  /etc/policyd/cluebringer.conf
sed -i 's/dbname=cluebringer/dbname=policyd/' /usr/share/cluebringer/webui/includes/config.php
sed -i 's/$DB_USER="root"/$DB_USER="policyd_user"/g'  /usr/share/cluebringer/webui/includes/config.php
sed -i 's/#$DB_PASS=""/$DB_PASS="'$POLICYDPASS'"/g'  /usr/share/cluebringer/webui/includes/config.php

sed -i 's|#log_level=2|log_level=3|g'  /etc/policyd/cluebringer.conf
sed -i 's|#log_file=/var/log/cbpolicyd.log|log_file=/var/log/cbpolicyd.log|g'  /etc/policyd/cluebringer.conf
sed -i 's|log_mail=maillog|log_mail=main|g'  /etc/policyd/cluebringer.conf

chown -R nginx.nginx /usr/share/cluebringer/webui
cp -vp /opt/template/nginx/policyd.conf /etc/nginx/conf.d/

rm -rf /opt/template

##Start Services
echo "start php-fpm"
/usr/sbin/php-fpm -D
echo "start nginx"
/usr/sbin/nginx -c /etc/nginx/nginx.conf
echo "start postfix"
/usr/sbin/postfix start
echo "start mailscanner"
/usr/lib/MailScanner/init/ms-init start 
echo "start clamd"
/usr/sbin/clamd -c /etc/clamd.d/scan.conf
echo "start cbpolicyd"
/usr/bin/perl /usr/sbin/cbpolicyd --config /etc/policyd/cluebringer.conf

else
##Start Services
echo "start rsyslog"
/usr/sbin/rsyslogd
echo "start php-fpm"
/usr/sbin/php-fpm -D
echo "start nginx"
/usr/sbin/nginx -c /etc/nginx/nginx.conf
echo "start postfix"
/usr/sbin/postfix start
echo "start mariadb"
nohup sudo -u mysql /sbin/mariadbd &
echo "start mailscanner"
/usr/lib/MailScanner/init/ms-init start 
echo "start clamd"
/usr/sbin/clamd -c /etc/clamd.d/scan.conf
echo "start cbpolicyd"
/usr/bin/perl /usr/sbin/cbpolicyd --config /etc/policyd/cluebringer.conf

echo "Installed successfully. You can access now to MailWatch http://$HOSTNAME:90"

fi 


if [[ $1 == "-d" ]]; then
  while true; do sleep 1000; done
fi

if [[ $1 == "-bash" ]]; then
  /bin/bash
fi
