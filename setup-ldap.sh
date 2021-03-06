#!/bin/bash 
# Author: M.R.Niranjan (niranjan.ashok@gmail.com)
#
# This program is free software; you can redistribute it and/or modify
# 
# This program comes WITHOUT ANY WARRANTY; Any loss of data occurring due to this script cannot be claimed from author
# Do not run this script on Production systems , First run this script on test (non-production systems) before deploying
# it on Production Systems.
#
# Any comments or improvements can be mailed to niranjan.ashok@gmail.com
#
#
# Purpose: This script Configures OpenLDAP instance with given suffix on a bdb backend. Additionally it also configures
# Replication between two ldap servers 
#
# Read README file for more documentation on this shell script

## Our environmental Definition
source ./defines.sh
source ./common.sh


		### This function checks if user wants to continue with Setup or not ###

checkcont()
{
	echo -e "\n$breakline"
	echo -e "$welcome"
	echo -n "Would you like to continue with set up? [yes]: "
	read cont
	if [ "$cont" == "" ]; then
		cont=yes
	else if	[ "$cont" != "yes" ] || [ "$cont" != "YES" ] || [ "$cont" != "Yes" ]; then
		exit 1;
	fi
	fi
}

		### This function checks if openldap-servers package is installed ###
checkpackage()
{
ldappackage=`rpm -qa | grep openldap-servers 2>&1`
RETVAL=$?
if test $RETVAL == 0; then 
	echo -e "\n$ldappackage Packages are installed" >> $mylog
else
	echo -e "\nPackage openldap-servers is not installed. Please install openldap-servers rpm"
	exit 1
fi
}

		### This functions converts the sample slapd.conf to cn=config format.  ###

basicsetupopenldap()
{
if `test -f $sampleconfig`; then
        echo -e "Using $sampleconfig" >> $mylog
else
	echo $?
        echo -e "file $sampleconfig doesnt exist\n"
	exit 1
fi

#create the slapd.d directory first 
if `test -d $slapdconfigdir	`; then
	echo -e "$slapdconfigdir already exists" >> $mylog
	echo -e "\nDirectory already exists, backup and remove the directory, we are creating fresh instance"
	exit 1
else
	 echo -e "\n$breakline"
	 echo -e "\n$configdb"
	 echo -e "\nCreating $slapdconfigdir directory with user and group permissions of ldap" >> $mylog
	`mkdir $slapdconfigdir`
	`chown ldap.ldap $slapdconfigdir`
	`restorecon -R -v $slapdconfigdir`
fi
##run slaptest using the sample slapd.conf 

echo -e "\n$breakline"
echo -e "$configdbadmin"
echo -n "Enter rootpw for $configrootdn (Default: config): "
read configrootpw
	if [ "$configrootpw" == "" ];then
		configrootpw="config"
	fi
echo -e "\nConfig password for $configrootdn is $configrootpw" >> $mylog

# we hash configrootpw with SHA 
hashconfigrootpw=`$slappasswd -s $configrootpw`
slaptestout=`$slaptest -f $sampleconfig -F $slapdconfigdir`
RETVAL=$?
if [ $RETVAL == 0 ]; then
	`chown ldap.ldap $slapdconfigdir/* -R `
	## start the slapd process now 
	slapdstart=`$slapdinit start`
	slapdstartcheck=$?
	if [ $slapdstartcheck != 0 ]; then 
		echo "slapd did not start"
		exit
	else 
configrootmod=`$ldapmodify -x -D "$configrootdn" -w config -h $(hostname) <<EOF >>$mylog
dn: olcDatabase={0}config,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $hashconfigrootpw
EOF`
		echo -e "\nslapd service is started with cn=config and cn=monitor database" >> $mylog
	fi
	
else
	echo "There was some problem converting initial configuration to cn=config format" >> $mylog
	exit 1
fi
}

		### This function sets up berkely database for a given suffix.####


setupbackend()
{
#Before we continue, check if config database is setup properly, we do ldapsearch to "cn=config", that would require us to know the binddn and bindpw, currently we use "cn=admin,cn=config" with password as "config". */

# To-do we need a method to get this info properly 

configout=`$ldapsearch -xLLL -b "cn=config" -D "$configrootdn" -w "$configrootpw" -h localhost dn | grep -v ^$`
RETVAL=$?
	if [ $RETVAL != 0 ]; then 
		echo -e "\nThere was some problem config database not properly setup" >> $mylog
		echo $configout >> $mylog
		exit 1
	fi
#we need the suffix for which we want to setup berkely database.
#To-do , probably it's better we get the choice of backend from user
#Here if we are called from slave, we do not want to call the below again but set the suffix to what provider has 

if [ "$providersuffix" == "" ]; then
{
	echo -e "$confsuffix"
	echo -n "Specify the suffix(default dc=example,dc=org): "
	read suffix
		if [ "$suffix" == "" ]; then
			suffix="dc=example,dc=org"
		fi
	echo -e "$breakline"
	echo -e "$suffixadmin"
	echo "$suffix" is configured with berkely database >> $mylog
	echo -n "Specify the rootbinddn to use (Default:cn=Manager,$suffix): "
	read rootbinddn
        	if [ "$rootbinddn" == "" ]; then
                	rootbinddn="cn=Manager,$suffix"
	                echo -e "\nroot binddn used is:$rootbinddn" >> $mylog
        	fi
	echo -n "Specify the rootbindpw to use (Default: redhat): "
	read rootbindpw
        	if [ "$rootbindpw" == "" ];then
                	rootbindpw="redhat"
	                echo -e "\nroot bind password is :$rootbindpw" >> $mylog
        	fi
}
else 
{
	suffix="$providersuffix"
	rootbinddn="$providerrootdn"
	rootbindpw="$providerrootpw"
}
fi
##By default we use /var/lib/ldap as our default directory 
dirtest=`test -d $suffixbackend`
RETVAL=$?
	if  [ $RETVAL != 0 ]; then
		echo -e "\nDirectory doesn't exist, create /var/lib/ldap with user and group permissions as ldap" >> $mylog
		exit 1
	fi
###setup the backend,  probably insted of doing below can we output this in an ldif file and then add it, does that look clean ?

hashrootbindpw=`$slappasswd -s $rootbindpw`
addbackend=`$ldapadd -x -D "$configrootdn" -w "$configrootpw" -h $(hostname) <<EOF 2>> $mylog
dn: olcDatabase=bdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcBdbConfig
olcDatabase: {1}bdb
olcSuffix: $suffix
olcDbDirectory: $suffixbackend
olcRootDN: $rootbinddn
olcRootPW: $hashrootbindpw
olcDbCacheSize: 1000
olcDbCheckpoint: 1024 10
olcDbIDLcacheSize: 3000
olcDbConfig: set_cachesize 0 10485760 0
olcDbConfig: set_lg_bsize 2097152
olcLimits: dn.exact="$rootbinddn" time.soft=unlimited time.hard=unlimited size.soft=unlimited size.hard=unlimited
olcDbIndex: uid pres,eq
olcDbIndex: cn,sn,displayName pres,eq,approx,sub
olcDbIndex: uidNumber,gidNumber eq
olcDbIndex: memberUid eq
olcDbIndex: objectClass eq
olcDbIndex: entryUUID pres,eq
olcDbIndex: entryCSN pres,eq
olcAccess: to attrs=userPassword by self write by anonymous auth by dn.children="ou=admins,dc=example,dc=com" write  by * none
olcAccess: to * by self write by dn.children="ou=admins,dc=example,dc=com" write by * read
EOF`

RETVAL=$?
if [ $RETVAL != 0 ]; then
	echo -n "There seems to be some problem creating database check $mylog file for more details"
	echo $addbackend >> $mylog
	exit 1;
fi
}

		### This function adds syncprov and accesslog overlay to the bdb backend used by suffix ####

addoverlay()
{
## If we are master we also need to enable syncprov module overlay and accesslog module overlay
accesslogoverlay=`$ldapadd -x -D "$configrootdn" -w "$configrootpw" -h $(hostname) <<EOF 2>> $mylog
dn: olcOverlay=accesslog,olcDatabase={2}bdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcAccessLogConfig
olcOverlay: accesslog
olcAccessLogDB: cn=accesslog
olcAccessLogOps: writes
olcAccessLogPurge: 7+00:00 1+00:00
olcAccessLogSuccess: TRUE
EOF`
RETVAL=$?
if [ $RETVAL != 0 ]; then
	echo -e "\nThere seems to be some problem creating accesslog overlays for $suffix"
	echo $accesslogoverlay >> $mylog
	exit 1
else
	echo -e "\nSuccessfully added accesslog overlay for $suffix \n"   >> $mylog
	echo $accesslogoverlay >> $mylog
fi
syncprovoverlay=`$ldapadd -x -D "$configrootdn" -w "$configrootpw" -h $(hostname) <<EOF 2>> $mylog
dn: olcOverlay=syncprov,olcDatabase={2}bdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcSyncProvConfig
olcOverlay: syncprov
olcSpCheckpoint: 1000 60
EOF`
RETVAL=$?

if [ $RETVAL != 0 ]; then
{
	echo -e "\nThere seems to be some problem creating syncprov overlay for $suffix"
	echo $syncprovoverlay >> $mylog
	exit 1
}
else
	echo -e "\nSuccessfully added  syncprov overlay for $suffix \n"	>> $mylog

fi
}

		### This function loads the ppolicy, accesslog and syncprov modules to cn=config database. ###

enablemodules()
{
### we load ppolicy, accesslog, syncprov
### Load the ppolicy.la
ppolicyadd=`$ldapadd -x -D "$configrootdn" -w "$configrootpw" -h localhost <<EOF 2>> $mylog
dn: cn=module,cn=config
objectClass: olcModuleList
cn: module
olcModuleLoad: ppolicy.la
EOF`
RETVAL=$?
	if [ $RETVAL == 0 ];then
		echo -e "ppolicy.la module has been added" >> $mylog
	else
		exit 1
	fi
### Load the syncprov module 
syncprovadd=`$ldapadd -x -D "$configrootdn" -w "$configrootpw" -h localhost <<EOF 2>> $mylog
dn: cn=module,cn=config
objectClass: olcModuleList
cn: module
olcModuleLoad: syncprov.la
EOF`

RETVAL=$?
	  if [ $RETVAL == 0 ];then
          echo -e "syncprov.la module has been added" >> $mylog
	  else
               	exit 1
	  fi
if [ $master ];then
### We enable accesslog module 
accesslogadd=`$ldapadd -x -D "$configrootdn" -w "$configrootpw" -h localhost <<EOF 2>> $mylog
dn: cn=module,cn=config
objectClass: olcModuleList
cn: module
olcModuleLoad: accesslog.la
EOF`
RETVAL=$?
     if [ $RETVAL == 0 ];then
         echo -e "accesslog.la module has been added\n" >> $mylog
     else
         exit 1
     fi
fi
}

		### We create a minimum DIT and load in to ldap server ###

enabledit()
{
dcobject=`echo $suffix | awk -F "," '{print $1}' | awk -F "=" '{print $2}'`
echo -e "dn: $suffix" >> $myldif
echo -e "objectClass: top" >> $myldif
echo -e "objectClass: domain" >> $myldif
echo -e "dc: $dcobject" >> $myldif
echo -e '\n' >> $myldif
IFS=" "
for i in `cat $workingdir/create_ou.conf`
do
echo -e "dn: ou=$i,$suffix" >> $myldif
echo -e "objectClass: top" >> $myldif
echo -e "objectClass: organizationalUnit" >> $myldif
echo -e "ou: $i" >> $myldif
echo -e '\n' >> $myldif
done
ditadd=`$ldapadd -x -D "$rootbinddn" -w "$rootbindpw" -f $myldif -h localhost` 2>> $mylog
RETVAL=$?
	if [ $RETVAL == 0 ]; then
		echo -e "\nOpenldap is now configured with $suffix"
	else
		echo -e "\nThere was some problem creating basic Directory Information tree check $mylog for more details" 
		exit 1
	fi
rm -f $myldif 
}

		### Setup Accesslog backend on Master ###

setupaccesslog()
{
## create accesslog directory, We use /var/lib/ldap-accesslog
	if `test -d $accesslogdir`; then
        	echo "Directory already exists, backup and remove the directory, we are creating fresh instance" >> $mylog
	        exit 1
	fi
echo -e "\n$accesslogdb"
`mkdir $accesslogdir`
`chown ldap.ldap $accesslogdir`
echo -n "Specify the Root Binddn for accesslog (Default:cn=accesslog): "
read accesslogbinddn
        if [ "$accesslogbinddn" == "" ]; then
                accesslogbinddn="cn=accesslog"
                echo -e "\nroot binddn accesslogused is:$rootbinddn" >> $mylog
        fi
echo -n "Specify the bindpw to use for $accesslogbinddn (Default: redhat): "
read accesslogbindpw
        if [ "$accesslogbindpw" == "" ];then
                accesslogbindpw="redhat"
                echo -e "\nroot bind password is :$rootbindpw" >> $mylog
        fi
hashaccesslogbindpw=`$slappasswd -s $accesslogbindpw`
addaccesslogbackend=`$ldapadd -x -D "$configrootdn" -w "$configrootpw" -h localhost <<EOF 2>> $mylog
dn: olcDatabase=bdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcBdbConfig
olcDatabase: {2}bdb
olcDbDirectory: /var/lib/ldap-accesslog
olcSuffix: cn=accesslog
olcAccess: {0}to * by dn.base="cn=replicator,ou=Admins,$suffix" read   by * break
olcLimits: {0}dn.exact="cn=accesslog" time.soft=unlimited time.hard=unlimited size.soft=unlimited size.hard=unlimited
olcLimits: {1}dn.exact="cn=replicator,ou=Admins,$suffix" time.soft=unlimited time.hard=unlimited size.soft=unlimited size.hard=unlimited
olcDbConfig: set_cachesize 0 10485760 0
olcDbConfig: set_lg_bsize 2097152
olcRootDN: $accesslogbinddn
olcRootPW: $hashaccesslogbindpw
olcDbCacheSize: 1000
olcDbCheckpoint: 1024 10
olcDbIDLcacheSize: 3000
olcDbIndex: default eq
olcDbIndex: reqEnd eq
olcDbIndex: reqResult eq
olcDbIndex: reqStart eq
olcDbIndex: objectClass eq
olcDbIndex: entryCSN pres,eq
EOF`
RETVAL=$?

	if [ $RETVAL != 0 ]; then
        	echo -e "\nThere seems to be some problem creating "cn=accesslog" database check $mylog file for more details\n"
	        echo $addaccesslogbackend >> $mylog
        	exit 1;
	else
		echo -e "\nOpenldap has been configured as Provider for $suffix\n" >>$mylog
		echo -e "\n$successprovider"
	fi
addaccesslogoverlay=`$ldapadd -x -D "$configrootdn" -w "$configrootpw" -h $(hostname) <<EOF 2>>$mylog
dn: olcOverlay=syncprov,olcDatabase={3}bdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcSyncProvConfig
olcOverlay: syncprov
olcSpNoPresent: TRUE
olcSpReloadHint: TRUE
EOF`
RETVAL=$?
		if [ $RETVAL != 0 ]; then
                echo -e "\nThere seems to be some problem creating accesslog overlay check $mylog file for more details\n"
                echo $addaccesslogoverlay >> $mylog
                exit 1;
        else
                echo -e "\nAccesslog overlay has been configured\n" >> $mylog
        fi

}

		### This function contacts master OpenLDAP server and configures accesslog to enable unlimited read access to supplier binddn ####

contactprovider()
{
## We first need to check if master is reachable from slave 
## If reachable we need rootdn and rootpw of the suffix for which we are configuring slave 
echo -n "Specify the hostname of the provider(Master): "
read providerhost

	if [ "$providerhost" == "" ]; then
                echo -e "\nDid not enter provider hostname:"
		exit 1
        fi
		echo -n "Specify the provider port number on which slapd is running: "
		read providerport
		echo -n "Specify the suffix configured on $providerhost for which consumer should be configured: " 
		read providersuffix

		providersuffixtest=`$ldapsearch -xLLL -b "$providersuffix" -s base -p $providerport -h $providerhost` 2>> /dev/stderr
		RETVAL=$?
	if [ $RETVAL != 0 ];then
		echo -e "\nProvider not reachable"
		exit 1;
	
	else 
	{
		echo -e "\n		Provider accessible		\n"
		echo -n "specify the provider(aka Master) bindn to be used for replication agreement.This user should have unlimited read access to cn=accesslog.If no value is given, we create "cn=replicator,$providersuffix" on $providerhost with unlimited read access to cn=accesslog (Default:cn=replicator,$providersuffix): "
		read repbinddn
		echo -n "Specify the password of  $repbindn (Default: redhat) :"
		read repbindpw

		if [ "$repbindpw" == "" ]; then
			repbindpw=redhat
			hashrepbindpw=$($slappasswd -s $repbindpw)
		fi
		if [ "$repbinddn" == "" ];then
			repbinddn="cn=replicator,$providersuffix"
			echo -n "Specify the Configuration Administrator dn of $providerhost(Default:$configrootdn):"
			read configadmin
			if [ "$configadmin" == "" ]; then
				configadmin="$configrootdn"
			fi
			echo -n "Specify the password of $configadmin: "
			read configpw
			if [ "$configpw" == "" ]; then
                                configpw="config"
                        fi
			echo -n "Specify the rootbinddn to use (Default:cn=Manager,$providersuffix): "
		        read providerrootbinddn
                	if [ "$providerrootbinddn" == "" ]; then
                        	providerrootbinddn="cn=Manager,$providersuffix"
                        	echo -e "\nroot binddn used is:$providerrootbinddn" >> $mylog
                	fi
       			 echo -n "Specify the rootbindpw to use (Default: redhat): "
		        read providerrootbindpw
	                if [ "$providerrootbindpw" == "" ];then
        	                providerrootbindpw="redhat"
                	        echo -e "\nroot bind password is :$providerrootbindpw" >> $mylog
	                fi
			### First we create access control to provide unlimited access to cn=accesslog
			### find the dn of cn=accesslog database
			accesslogdn=$($ldapsearch -xLLL -b "cn=config" -D "$configadmin" -w "$configpw" -h "$providerhost" "(&(objectClass=olcBdbConfig)(olcSuffix="cn=accesslog"))" dn | awk -F " " '{print $2}')

access1=`$ldapmodify -x -D "$configadmin" -w "$configpw" -h "$providerhost" <<EOF 2>> $mylog
dn: $accesslogdn
changetype: modify
add: olcLimits
olcLimits: dn.exact="$repbinddn" time.soft=unlimited time.hard=unlimited size.soft=unlimited size.hard=unlimited
-
add: olcAccess
olcAccess: to * by dn.base="$repbinddn" read by * break
EOF`
			RETVAL=$?
			if [ $RETVAL != 0 ];then
			{
				echo -e "\nThere was some problem adding access control to $repbinddn check $mylog for more details"
				echo -e "\n$access1" >> $mylog
				exit 1
			}
			else
			{
				echo -e "\nReplica binddn access control was added successfully"
			}
			fi
access2=`$ldapadd -x -D "$providerrootbinddn" -w "$providerrootbindpw" -h $providerhost <<EOF 2>>$mylog
dn: $repbinddn
cn: replicator
objectClass: top
objectClass: inetOrgPerson
userPassword: $hashrepbindpw
sn: admin
EOF`
			RETVAL=$?
                        if [ $RETVAL != 0 ];then
                        {

				echo -e "\n$repbinddn was not created $provider check $mylog for more details"
				echo -e "$access2" >> $mylog
				exit 1
			}	
			else 
				echo -e "\n$repbindn created successfully on $providerhost"
			fi
		
		fi
		
	}
	fi	
}

			### This function creates sync replication agreement on Slave Server ###

configureconsumer()
{
syncagreement=`ldapmodify -x -D "$configrootdn" -w "$configrootpw" -h $(hostname) <<EOF 2>> $mylog
dn: olcDatabase={2}bdb,cn=config
changetype: modify
add: olcSyncRepl
olcSyncRepl: rid=001 provider=ldap://$providerhost:$providerport binddn="$repbinddn" bindmethod=simple credentials=$repbindpw searchbase="$providersuffix" logbase="cn=accesslog" logfilter="(&(objectClass=auditWriteObject)(reqResult=0))" schemachecking=on type=refreshAndPersist  retry="5 5 5 +" syncdata=accesslog
-
add: olcUpdateref
olcUpdateref: ldap://$providerhost:$providerport
EOF`
RETVAL=$?
	if [  $RETVAL != 0 ];then 
		echo -e "\n There was some problem creating sync agreement"
		exit 1;
	else
		echo -e "\n Sync agreemnt created successfully"
	fi
}	

		### This function configures TLS/SSL for slapd to listen on port 636 ###

conf_tls()
{
### We setup TLS parameters to enable SSL/TLS for slapd. The attributes are: 
#olcTLSCACertificateFile: /etc/pki/tls/certs/cacert.pem  CA certificate
#olcTLSCertificateFile: /etc/pki/tls/certs/ldap.pem Server Cert
#olcTLSCertificateKeyFile: /etc/pki/tls/certs/ldap-key.pem  Server Private key 

### The below code currently asks the path to the certs, We do not generate the certs and TLS Verify Client as "allow"
echo -e "$breakline"
echo -e "$tlssetup"
echo -n "CA certificate (Default: $defaultcacert)"
read cacert
	if [ "$cacert" == "" ];then
		cacert="$defaultcacert"
	fi
echo -n "Server Certificate (Default: $defaultservercert): "
read server
	if [ "$server" == "" ];then
		server="$defaultservercert"
	fi
echo -n "Server Cert's Private key (Default: $defaultserverprivatekey): "
read serverkey
	if [ "$serverkey" == "" ]; then
		serverkey="$defaultserverprivatekey"
	fi
enabletls=`$ldapmodify -x -D "$configrootdn" -w "$configrootpw" -h $(hostname) <<EOF 2>> $mylog
dn: cn=config
changetype: modify
add: olcTLSCACertificateFile
olcTLSCACertificateFile:  $defaultcacert
-
add: olcTLSCertificateFile
olcTLSCertificateFile: $defaultservercert
-
add: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: $defaultserverprivatekey
-
replace: olcTLSVerifyClient
olcTLSVerifyClient: allow
EOF`
RETVAL=$?
	if [  $RETVAL != 0 ];then
	{
                echo -e "\n There was some problem adding TLS/SSL Parameters to cn=config, check $mylog for more details"
                echo -e "\n$enabletls" >> $mylog
                exit 1
	}
	else 
	{
		#check if SLAPD_LDAPS=no is set in /etc/sysconfig/ldap 
		LDAPS=$(grep ^SLAPD_LDAPS $sysconf_ldap | grep "no")
		if [ "$LDAPS" == "SLAPD_LDAPS=no" ]; then
		{
			sed 's/SLAPD_LDAPS=no/SLAPD_LDAPS=yes/' $sysconf_ldap > $sysconf_ldap.new
			/bin/cp $sysconf_ldap $sysconf_ldap.orig
			/bin/cp -f $sysconf_ldap.new $sysconf_ldap
			echo -e "\nTLS/SSL has been Set, /etc/sysconfig/ldap file has been modified to set "SLAPD_LDAPS=yes""
			echo -e "\nslapd service will be restarted now"

			slapdstart=`$slapdinit restart` >> $mylog
			RETVAL=$?
			if [ $RETVAL != 0 ]; then
				echo -e "\nThere was some problem starting slapd, check $mylog"
				echo $RETVAL >> $mylog
				exit 1
			fi
			checksslport=`$netstat -plant | grep ^[t][c]p | grep 636`
			RETVAL=$?
			if [ $RETVAL != 0 ]; then
                                echo -e "\nThere was some problem, slapd doesn't seem to run on port 636, check $mylog"
                                echo $RETVAL >> $mylog
                                exit 1
                        fi
			echo -e "\nslapd service is running port 636\n"
			
		}	
		else 
		{
			echo -e "\nRestarting slapd service"
			$slapdinit restart >> $mylog
			echo -e "$breakline"
		
		}
		fi
		
		
	}	
	fi
	
}

RETVAL=0

## We are called as:
case "$1" in 
	--master)
		master=true
		checkcont
		checkpackage
		basicsetupopenldap
		enablemodules
		conf_tls
		setupbackend
		enabledit
		setupaccesslog
		addoverlay
		;;
	--slave)
		slave=true
		checkpackage
		basicsetupopenldap
		enablemodules
		setupbackend
		enabledit
		contactprovider
		configureconsumer
		;;
	usage)
		echo $"Usage: $0 {--master|--slave}"
                RETVAL=0
                ;;
	*)	
		echo $"Usage: $0 {--master|--slave}"
		RETVAL=2
		;;
esac
