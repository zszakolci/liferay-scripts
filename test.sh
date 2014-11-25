##!bin/bash

## $0 - test.sh
## $1 - <customer>
## $2 - <issue>
## $3 - <portal-version>
## $4 - "-n"
## $5 - which node
## $6 - "-h"
## $7 - hotfix
## $8 - 
##

if [ ! -f env.properties ]
then
	if [ -f "/usr/lib/jvm/java-7-oracle/bin/java" ]
	then
		javahome="/usr/lib/jvm/java-7-oracle"
	elif [ -f "/usr/lib/jvm/java-7-openjdk/bin/java" ]
	then
		javahome="/usr/lib/jvm/java-7-openjdk"
	elif [ -f "/usr/lib/jvm/java-6-oracle/bin/java" ]
	then
		javahome="/usr/lib/jvm/java-6-oracle"
	elif [ -f "/usr/lib/jvm/java-6-openjdk/bin/java" ]
	then
		javahome="/usr/lib/jvm/java-6-openjdk"
	else
		read -p "Specify your JAVA_HOME:" javahome	
	fi

	read -p "MySQL username:" mysqlusr	
	read -s -p "MySQL password:" mysqlpwd
	read -p "PostGreSQL username:" postgresusr
	read -s -p "PostGreSQL password:" postgrespwd
	read -p "Oracle SID:" oracleSID
	read -s -p "Oracle password for system user:" oraclePWD
	eval echo issuefolder="~/liferay/issues" >> env.properties
	eval echo appserverfolder="~/liferay/app-servers" >> env.properties
	eval echo patchingfolder="~/liferay/patching/patching-tool" >> env.properties
	eval echo dependenciesfolder="~/liferay/vanilla" >> env.properties
	eval echo deploymentfolder="~/liferay/portals" >> env.properties
	eval echo gitroot="~/liferay/git" >> env.properties
	echo "jgroupsbindport=7800" >> env.properties
	myip=`/sbin/ifconfig | grep 192.168.211 | awk '{print $2}' | sed -e 's/addr://'`
	echo "javahome=${javahome}" >> env.properties
	echo "mysqlusr=${mysqlusr}" >> env.properties
	echo "mysqpwd=${mysqlpwd}" >> env.properties
	echo "postgresusr=${postgresusr}" >> env.properties
	echo "postgrespwd=${postgrespwd}" >> env.properties
	echo "oraclesid=${oracleSID}" >> env.properties
	echo "oraclepwd=${oraclePWD}" >> env.properties
	echo "myip=${myip}"  >> env.properties
	echo "customer=TEST" >> env.properties
	echo "issue=1" >> env.properties
fi

source env.properties

# Checking the env

if [ ! -f ${javahome}/bin/java ]
then
	echo "Java could not be found in ${javahome}"
	exit 1
fi

if [ ! -f /etc/init.d/mysql ]
then
	read -p "MySQL has not been installed. Do you wish to install it now? <y/n>" answer
	if [ ${answer} == "y" ]
	then
		sudo apt-get install mysql-server mysql-client
	fi	
fi
##  Variables

if [ ! -z $1 ]
then
	customer=$1
fi

if [ ! -z $2 ]
then
issue=$2
fi

version=$3
properties="${issuefolder}/${customer}/${issue}/data/portal-setup-wizard-${version}.properties"
dbname=${customer}_${issue}_${version}
hotfix=""
vanilla=0
ptfile=""
cleanpatches=0
cleanplugins=0
name=""
installpatches=1
hostname="localhost"
database=hsql
customerproperties=${issuefolder}/${customer}/${customer}.properties
upgrade=0
dropdb=0
ptool="patching-tool-17-internal.zip"


if [ -f ${customerproperties} ]
then
	source ${customerproperties}
fi

function choosePortalVersion {
case "$1" in
	"6012")
		version="ee-6.0.12"
		port=6012
		name="6.0-ee-sp2"
	;; 
	"6110")
		version="ee-6.1.10"
		name="6.1.10-ee-ga1"
		port=6110
	;;

	"6120")
		version="ee-6.1.20"
		port=6120
		name="6.1.20-ee-ga2"
	;;

	"6130")
		version="ee-6.1.30"
		port=6130
		name="6.1.30-ee-ga3"
	;;

	"6210")
		version="ee-6.2.10"
		port=6210
		name="6.2.10.1-ee-ga1"
	;;

	"ee60x")
		version="ee-6.0.x"
		port=8380
		
	;;
	"ee61x")
		version="ee-6.1.x"
		port=8280
	;;
	
	"ee62x")
		version="ee-6.2.x"
		port=8180
	;;

	"master")
		version="master"
		port=8080
	;;
esac
}

choosePortalVersion $3
newversion=${version}
newport=${port}
shift 3 
while getopts "h:d:vrbgf:c:p:s:a:e:u:" opt; do
    case "$opt" in
    h)  hotfix=$OPTARG
        ;;
    f)  
	ptfile=$OPTARG
        ;;
    v)
	vanilla=1
	;;
    c)
	context=$OPTARG
	;;
    p)
	port=$OPTARG
	;;
    a)
	appserver=$OPTARG
	;;
    s)
	servicepack=$OPTARG
	;;
    r)
	cleanpatches=1
	cleanplugins=1
	;;
    e)
	plugins=$OPTARG
	;;
    d)
	database=$OPTARG
	;;
    b)  installpatches=0
	;;
    u)
	upgrade=1
	upgradefrom=$OPTARG
	oldproperties="${issuefolder}/${customer}/${issue}/data/portal-setup-wizard-${upgradefrom}.properties"

	;;
    g)
	dropdb=1
	;;
    i)
	dump=1
    ;;
    esac
done

shift $((OPTIND-1))




mkdir -p ${issuefolder}/${customer}/${issue}/data


if [ ! -f ${customerproperties} ]
then
	if [ -z ${version} ]
	then
		read -p "Portal version:" version
		choosePortalVersion ${version}
	fi
	echo "appserver=apache-tomcat-7.0.57" >> ${customerproperties}
	echo "database=${database}" >> ${customerproperties}
	echo "plugins=Ehcache" >> ${customerproperties}
	echo "version=${version}" >> ${customerproperties}
	echo "context=ROOT" >> ${customerproperties}
	echo "port=${port}" >> ${customerproperties}
	echo "hostname=localhost" >> ${customerproperties}
	echo "dbhost=localhost" >> ${customerproperties}

	source ${customerproperties}
fi

appserverparent=${appserverfolder}/${port}
liferayhome=${issuefolder}/${customer}/liferay-portal-${version}-${port}
### WORKAROUND FOR MASTER ###

if [ ${version} == "master" ]
then
	liferayhome=${appserverparent}
fi

########
mkdir -p ${liferayhome}/patches

patches=`ls ${liferayhome}/patches`
patches=${patches#liferay-}
patches=${patches%.zip}

echo "************************************************************************************************"
echo " Launching portal ${version} for ${customer} ${issue} on ${appserver} using port ${port}"
echo " Database: ${database}"
echo " Context: ${context}"
# echo " Patches to install: ${servicepack} - ${patches}"
echo "************************************************************************************************"

webapps=${deploymentfolder}/${port}/$version
## Create customer folder if it does not exist

if [ ! -d ${webapps} ]
then
mkdir -p ${webapps}
fi

v=${version#'ee-'}
if [ ! -z ${servicepack} ]
then
	if [ ${version} == "ee-6.2.10" ]
	then
	spver=$((${servicepack#'SP'} + 1))
	else
		spver=${servicepack#'SP'}
	fi	
	v=${v}.${spver}
elif [ ${version} == "ee-6.2.10" ]
then
v=${v}.1
fi

#umask 666
## Unpack the portal if it does not exist
if [ ! -f ${webapps}/${context}/WEB-INF/lib/portal-impl.jar ]
then
	# rm -rf ${webapps}
	portalpath=`find ${webapps} -name portal-impl.jar`
	if [ -z ${portalpath} ]
	then
		mkdir -p ${webapps}/${context}
		mkdir -p ${dependenciesfolder}/${version}
		war=`ls ${dependenciesfolder}/${version}/*.war`
		if [ -z ${war} ]
		then
			cd ${dependenciesfolder}/${version}
			if [ ${version} == "ee-6.0.12" ]
			then
				wget http://files.liferay.com/private/ee/portal/${v}/liferay-portal-6.0-ee-sp2-20110727.war
			elif [ ${version} == "ee-6.1.10" ]
			then
				wget http://files.liferay.com/private/ee/portal/${v}/liferay-portal-6.1.10-ee-ga1-20120223174854827.war
			else
			wget -nd -r --no-parent -A '*.war' http://files.liferay.com/private/ee/portal/${v}/
			fi
		fi
		war=`ls ${dependenciesfolder}/${version}/*.war`
		if [ ! -f ${war} ]
		then
			echo "Portal war file could not be found in ${dependenciesfolder}/${version}"
			exit 1
		fi
		cd ${webapps}/${context}
		unzip $war
	else
		ctxroot="${portalpath%'/WEB-INF/lib/portal-impl.jar'}"
		echo $ctxroot		
		mv ${ctxroot} ${webapps}/${context}
	fi
fi

if [ ! -f ${webapps}/${context}/WEB-INF/lib/portal-impl.jar ]
then
	echo "${webapps}/${context}/WEB-INF/lib/portal-impl.jar Could not be found"
exit 1
fi

vanilladependencies=${dependenciesfolder}/${version}/dependencies
extracteddependencies="$HOME/liferay/dependencies/${version}"
mkdir -p ${extracteddependencies}
mkdir -p ${vanilladependencies}

cd "${vanilladependencies}"
if [ ! -f "${vanilladependencies}/portal-service.jar" -o ! -f "${vanilladependencies}/portlet.jar" ]
then
if [ ${version} == "ee-6.1.10" ]
then
wget -nd http://files.liferay.com/private/ee/portal/${v}/liferay-portal-dependencies-6.1.10-ee-ga1-20120223174854827.zip
else
	wget -nd -r --no-parent -A 'liferay-portal-dependencies*.zip' http://files.liferay.com/private/ee/portal/${v}/
fi
unzip -j "${vanilladependencies}/*.zip"

fi

if [ ! -f "${vanilladependencies}/activation.jar" ]
then
	wget -nd http://www.java2s.com/Code/JarDownload/activation/activation.jar.zip
	unzip activation.jar.zip 
fi

if [ ! -f "${vanilladependencies}/ccpp.jar" ]
then
	wget -nd http://central.maven.org/maven2/javax/ccpp/ccpp/1.0/ccpp-1.0.jar
mv ccpp-1.0.jar ccpp.jar
fi

if [ ! -f "${vanilladependencies}/jms.jar" ]
then
	wget -nd http://www.java2s.com/Code/JarDownload/javax.jms/javax.jms.jar.zip
unzip javax.jms.jar.zip
mv javax.jms.jar jms.jar
fi

if [ ! -f "${vanilladependencies}/jta.jar" ]
then
wget -nd http://www.java2s.com/Code/JarDownload/jta/jta.jar.zip
unzip jta.jar.zip
fi

if [ ! -f "${vanilladependencies}/jtds.jar" ]
then
wget -nd http://central.maven.org/maven2/net/sourceforge/jtds/jtds/1.3.0/jtds-1.3.0.jar
mv jtds-1.3.0.jar jtds.jar
fi

if [ ! -f "${vanilladependencies}/mail.jar" ]
then
wget -nd http://www.java2s.com/Code/JarDownload/mail/mail.jar.zip
unzip mail.jar.zip
fi

if [ ! -f "${vanilladependencies}/persistence.jar" ]
then
wget -nd http://www.java2s.com/Code/JarDownload/javax.persistence/javax.persistence.jar.zip
unzip javax.persistence.jar.zip
mv javax.persistence.jar persistence.jar
fi

if [ ! -f "${vanilladependencies}/support-tomcat.jar" ]
then
wget -nd http://central.maven.org/maven2/com/liferay/portal/support-tomcat/6.1.1/support-tomcat-6.1.1.jar
mv support-tomcat-6.1.1.jar support-tomcat.jar
fi

if [ ${installpatches} -ne 0 ]
then
	rm -f ${extracteddependencies}/*
	cp ${vanilladependencies}/*.jar "${extracteddependencies}"
fi
rm -f ${vanilladependencies}/*.zip




cd $liferayhome

## Download Tomcat

tomcathome=${appserverparent}/${appserver}

if [ ! -f ${tomcathome}/bin/catalina.sh ]
then
	mkdir -p ${tomcathome}
	cd ${appserverparent}
	branch=${appserver:14:1}
	appversion=${appserver:14:6}
	
	if [ ! -f ${appserver}.zip ]
	then
		wget http://xenia.sote.hu/ftp/mirrors/www.apache.org/tomcat/tomcat-${branch}/v${appversion}/bin/${appserver}.zip
		if [ ! -f ${appserver}.zip ]
		then
			echo "ERROR: ${appserver}.zip does not exist in ${appserverparent}"
			exit 1
		fi
	fi
	unzip ${appserver}.zip
	shutdownport=${port}5
	ajpport=${port}9
	if [ ${port} -gt 6552 ]
	then
		p=$((${port}-6000))
		shutdownport="${p}5"
		ajpport="${p}9"
	fi
	sed -i.bak "s/8080/${port}/" ${tomcathome}/conf/server.xml
	sed -i.bak "s/8009/${ajpport}/" ${tomcathome}/conf/server.xml
	sed -i.bak "s/8005/${shutdownport}/" ${tomcathome}/conf/server.xml
fi


## change the context

portpref=${port:1}
jpda=$((${portpref}+8000))
if [ ! -f ${tomcathome}/bin/setenv.sh ]
then
echo "JAVA_HOME=${javahome}
JAVA_OPTS=\"$JAVA_OPTS -Dfile.encoding=UTF8 -Dorg.apache.catalina.loader.WebappClassLoader.ENABLE_CLEAR_REFERENCES=false -Xmx1024m -XX:MaxPermSize=256m -Djava.net.preferIPv6Addresses=false -Djava.net.preferIPv4Stack=true -Djgroups.bind_addr=${myip} -Djgroups.bind_port=${jgroupsbindport} -Djgroups.tcpping.initial_hosts=${myip}[7810],${myip}[7820],${myip}[7800],${myip}[7830]\"

JPDA_TRANSPORT=\"dt_socket\"
JPDA_ADDRESS=\"${jpda}\"
JPDA_HOST=\"${myip}\"" > ${tomcathome}/bin/setenv.sh
fi

## setting the portal dependencies in the catalina.properties


sed -i -e "s:common.loader=.*:common.loader=\${catalina.base}/lib,\${catalina.base}/lib/*.jar,\${catalina.home}/lib,\${catalina.home}/lib/*.jar,${extracteddependencies},${extracteddependencies}/*.jar:" ${tomcathome}/conf/catalina.properties

sed -i -e "s@name=\"${hostname}\" *appBase=\".*\"@name=\"${hostname}\" appBase=\"${webapps}\"@" ${tomcathome}/conf/server.xml

sed -i -e "s@name=\"localhost\" *appBase=\"webapps\"@name=\"${hostname}\" appBase=\"${webapps}\"@" ${tomcathome}/conf/server.xml



sed -i -e "s/defaultHost=\"localhost\"/defaultHost=\"${hostname}\"/" ${tomcathome}/conf/server.xml

mkdir -p ${tomcathome}/conf/Catalina/${hostname}

if [ ! -f ${tomcathome}/conf/Catalina/kali/${context}.xml ]
then

rm -f ${tomcathome}/conf/Catalina/kali/*
ctpath=${context}

if [ "${context}" == "ROOT" ]
then
ctpath=""
fi
echo "<Context path=\"/${ctpath}\" crossContext=\"true\">

	<!-- JAAS -->

	<!--<Realm
		className=\"org.apache.catalina.realm.JAASRealm\"
		appName=\"PortalRealm\"
		userClassNames=\"com.liferay.portal.kernel.security.jaas.PortalPrincipal\"
		roleClassNames=\"com.liferay.portal.kernel.security.jaas.PortalRole\"
	/>-->

	<!--
	Uncomment the following to disable persistent sessions across reboots.
	-->

	<!--<Manager pathname=\"\" />-->

	<!--
	Uncomment the following to not use sessions. See the property
	\"session.disabled\" in portal.properties.
	-->

	<!--<Manager className=\"com.liferay.support.tomcat.session.SessionLessManagerBase\" />-->
</Context>" > ${tomcathome}/conf/Catalina/${hostname}/${context}.xml

fi


cd ${liferayhome}
echo "admin.email.from.name=Test Test
liferay.home=${liferayhome}
admin.email.from.address=test@liferay.com
setup.wizard.enabled=false
terms.of.use.required=false
users.reminder.queries.enabled=false
users.reminder.queries.custom.question.enabled=false
hot.undeploy.on.redeploy=true

auto.deploy.tomcat.dest.dir=${webapps}" > ${liferayhome}/portal-setup-wizard.properties
if [ "${context}" != "ROOT" ]
then
	echo -e "\nportal.virtual.path=/${context}\nportal.ctx=/${context}" >> ${liferayhome}/portal-setup-wizard.properties
fi

if [ ${upgrade} -eq 0 ]
then

case "${database}" in
	"hsql")
	if [ ${dropdb} -eq 1 ]
	then
		rm -rf ${liferayhome}/data/hsql
	fi
	if [ ! -f ${properties} ]
	then
		content="jdbc.default.driverClassName=org.hsqldb.jdbcDriver\njdbc.default.url=jdbc:hsqldb:\${liferay.home}/data/hsql/${dbname}\njdbc.default.username=sa\njdbc.default.password="
		echo -e "${content}" > ${properties}
	else
		sed -i "s@jdbc\.default\.driverClassName=.*@jdbc.default.driverClassName=org.hsqldb.jdbcDriver@" "${properties}"
		sed -i "s@jdbc\.default\.url=.*@jdbc.default.url=jdbc:hsqldb:\${liferay.home}/data/hsql/${dbname}@" "${properties}"
		sed -i "s@jdbc\.default\.username=.*@jdbc.default.username=sa@" "${properties}"
		sed -i "s@jdbc\.default\.password=.*@jdbc.default.password=@" "${properties}"
	fi
	;;
	"mysql")
	# sudo service mysql start
	if [ ${dropdb} -eq 1 ]
	then
		dropsql="DROP DATABASE ${dbname};"
		mysql -u ${mysqlusr} -e "${dropsql}"
	fi

	SQL="CREATE DATABASE IF NOT EXISTS ${dbname} character set utf8"
	mysql -u ${mysqlusr} -e "$SQL"
	if [ ! -f ${properties} ]
	then
		content="\n ## MySQL \n jdbc.default.driverClassName=com.mysql.jdbc.Driver\njdbc.default.url=jdbc:mysql://${dbhost}:3306/${dbname}?useUnicode=true&characterEncoding=UTF-8&useFastDateParsing=false\njdbc.default.username=${mysqlusr}\njdbc.default.password=${mysqlpwd}"
		echo -e "${content}" > ${properties}
	else
		sed -i "s!jdbc\.default\.driverClassName=.*!jdbc.default.driverClassName=com.mysql.jdbc.Driver!" ${properties}
		sed -i 's@jdbc\.default\.url='".*@jdbc.default.url=jdbc:mysql://${dbhost}/${dbname}\?useUnicode=true\&characterEncoding=UTF-8\&useFastDateParsing=false@" ${properties}
		sed -i "s!jdbc\.default\.username=.*!jdbc.default.username=${mysqlusr}!" ${properties}
		sed -i "s!jdbc\.default\.password=.*!jdbc.default.password=${mysqlpwd}!" ${properties}
	fi
	;;

	"postgresql")
	# sudo /etc/init.d/postgresql start
	dbname=`echo ${dbname} | tr '[:upper:]' '[:lower:]'`
	if [ ${dropdb} -eq 1 ]
	then
		sudo -u ${postgresusr} -p ${postgrespwd} -H sh -c "psql -c \"drop database ${dbname};\""
	fi
	sudo -u ${postgresusr} -p ${postgrespwd} -H sh -c "psql -c \"create database ${dbname};\""
	if [ ! -f ${properties} ]
	then
		content="\n ## Postgresql\n jdbc.default.driverClassName=org.postgresql.Driver\njdbc.default.url=jdbc:postgresql://${dbhost}:5432/${dbname}\njdbc.default.username=${postgresusr}\njdbc.default.password=${postgrespwd}"
		echo -e "${content}" > ${properties}
	else
		sed -i "s!jdbc\.default\.driverClassName=.*!jdbc.default.driverClassName=org.postgresql.Driver!" ${properties}
		sed -i "s!jdbc\.default\.url=.*!jdbc.default.url=jdbc:postgresql://${dbhost}:5432/${dbname}!" ${properties}
		sed -i "s!jdbc\.default\.username=.*!jdbc.default.username=${postgresusr}!" ${properties}
		sed -i "s!jdbc\.default\.password=.*!jdbc.default.password=${postgrespwd}!" ${properties}
	fi
	;;

	"oracle")
		echo "-- Create user
create user &1 identified by &1 default tablespace users temporary tablespace temp;

grant resource to &1; 
grant connect to &1;

alter user &1 quota unlimited on users;" >> ${issuefolder}/${customer}/${issue}/data/create_schema.sql
		# echo "create user ${dbname} identified by ${dbname} default tablespace users temporary tablespace temp; grant resource to ${dbname}; grant connect to ${dbname}; alter user ${dbname} quota unlimited on users;"
		
		# echo "create user ${dbname} identified by ${dbname} default tablespace users temporary tablespace temp;" | sqlplus system/${oraclepwd}
		# echo "grant resource to ${dbname};" | sqlplus system/${oraclepwd}
		# echo "grant connect to ${dbname};" | sqlplus system/${oraclepwd}
		# echo "alter user ${dbname} quota unlimited on users;" | sqlplus system/${oraclepwd}
		echo "exit" | sqlplus system/${oraclepwd}@${dbhost}/${oraclesid} @${issuefolder}/${customer}/${issue}/data/create_schema.sql ${dbname}
	if [ ! -f ${properties} ]
	then
		content="\n ## ORACLE\n jdbc.default.driverClassName=oracle.jdbc.driver.OracleDriver\njdbc.default.url=jdbc:oracle:thin:@${dbhost}:1521:${oraclesid}\njdbc.default.username=${dbname}\njdbc.default.password=${dbname}"
		echo -e "${content}" > ${properties}
	else
		sed -i "s!jdbc\.default\.driverClassName=.*!oracle.jdbc.driver.OracleDriver!" ${properties}
		sed -i "s!jdbc\.default\.url=.*!jdbc.default.url=jdbc:oracle:thin:@${dbhost}:1521:${oraclesid}!" ${properties}
		sed -i "s!jdbc\.default\.username=.*!jdbc.default.username=${dbname}!" ${properties}
		sed -i "s!jdbc\.default\.password=.*!jdbc.default.password=${dbname}!" ${properties}
	fi

	;;
esac 

else
	if [ ! -f ${oldproperties} ]
	then
		echo "You wanted to perform an upgrade, however ${oldproperties} does not exist."
		exit 1
	else
		cp ${oldproperties} ${properties}
	fi
fi

## Create the database


	# Altering the main property file
	rm -f ${appserverparent}/portal-ext.properties
	echo "include-and-override=${liferayhome}/portal-setup-wizard.properties
	include-and-override=${properties}" > ${appserverparent}/portal-ext.properties

	## Installing customer patches
	mkdir -p ${patchingfolder}
	cd ${patchingfolder}
	patchproperty="${customer}-${port}-${version}.properties"
		echo "patching.mode=binary
jdk.version=jdk6
war.path=${webapps}/${context}
global.lib.path=${extracteddependencies}
patches.folder=${liferayhome}/patches" > ${patchproperty}

if [ ! -f ${patchingfolder}/patching-tool.sh ]
then
	cd ..
	wget http://files.liferay.com/private/ee/fix-packs/patching-tool/${ptool}
	unzip ${ptool}
	cd patching-tool
fi


mkdir -p ${liferayhome}/patches
mkdir -p $HOME/liferay/patching/fix-packs/${version}/${servicepack}

	if [ ${installpatches} -eq 1 ]
	then

	./patching-tool.sh ${customer}-${port}-${version} revert
	if [ ${cleanpatches} -eq 1 ]
	then
		rm -rf ${liferayhome}/patches/*
	fi
	if [ ! -z $hotfix ]
	then
		vanilla=0
		${patchingfolder}/patching-tool.sh ${customer}-${port}-${version} download $hotfix	
	fi
	if [ ! -z $ptfile ]
	then
		vanilla=0
		${patchingfolder}/patching-tool.sh ${customer}-${port}-${version} download-all "$ptfile"
	fi

	if [ ! -z $servicepack ]
	then
		if [ ${servicepack} = "latest" ]
		then
			${patchingfolder}/patching-tool.sh ${customer}-${port}-${version} download-all-latest
		else	
			fileno=`ls $HOME/liferay/patching/fix-packs/${version}/${servicepack} | wc -l`
			if [ ${fileno} -lt 14 ]
			then
				mkdir -p zip
				cd zip
				wget -nd -r --no-parent -A 'liferay-portal-fix-packs-src*.zip' http://files.liferay.com/private/ee/portal/${v}/
				unzip -d $HOME/liferay/patching/fix-packs/${version}/${servicepack} *.zip
			fi
			cp $HOME/liferay/patching/fix-packs/${version}/${servicepack}/* ${liferayhome}/patches
		fi
	fi
	if [ $vanilla -eq 0 ]
	then
		${patchingfolder}/patching-tool.sh ${customer}-${port}-${version} install
	fi
	fi
	shopt -s extglob
	## Deploying plugins
	if [ ${cleanplugins} -eq 1 ]
	then
		cd ${webapps}
		rm -r !(${context})
	fi
	shopt -u extglob
	
	mkdir -p ${liferayhome}/deploy
	for plugin in ${plugins}
	do
		pluginpath=`ls /home/zalan/liferay/plugins/${version}/${plugin}*.lpkg` 
		if [ ! -z "${pluginpath}" ]
		then
			cp "${pluginpath}" ${liferayhome}/deploy
		fi
	done
	chmod -R 777 ${webapps}
	mkdir -p ${dependenciesfolder}/${version}/licenses
	## Launching the portal
	chmod +x ${tomcathome}/bin/*.sh
	chmod +r ${dependenciesfolder}/${version}/licenses/*
	license=`ls ${dependenciesfolder}/${version}/licenses/*.xml`
	
	cp ${license} ${liferayhome}/deploy
	chmod +rw ${liferayhome}/deploy/*
	#sudo chmod -R +rw ${webapps}

	${tomcathome}/bin/catalina.sh jpda run
