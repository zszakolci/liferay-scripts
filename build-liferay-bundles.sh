#!/bin/bash

tomcatversion="7.0.57"

source "env.properties"

tmpdir=${gitroot}/bundles/build-liferay-bundles.$(date "+%Y-%m-%d-%H%M")

## ant settings
export PATH="${PATH}:/usr/local/bin"
export ANT_OPTS="-Xmx1024m -XX:MaxPermSize=512m" 

## Abort if tmpdir is already there
 if [[ -d ${tmpdir} ]]
then
	echo "${tmpdir} already exists! Exiting."
	exit 1
fi

mkdir ${tmpdir}

## Remove previous files
## rm -rf /opt/bundles-out/*

branches="ee-6.0.x ee-6.1.x ee-6.2.x master"
nodes=(8380 8280 8180 8080)
i=0
workingdir=""
for branch in ${branches}
do

		## Change to appropriate directory
		if [[ "${branch}" == "master" ]]
		then
			workingdir=${gitroot}/liferay-portal
		else
			workingdir=${gitroot}/liferay-portal-ee
		fi
	
		cd ${workingdir}
	
		## Reset repository
		git reset --hard 1> /dev/null
		git clean -fd 1> /dev/null
	
		## Refresh repository
		git checkout ${branch} &> /dev/null
		git pull upstream ${branch}
		git clean -fd 1> /dev/null
		## Change symlink to current branch
		## rm -f ${git}/bundles
		## ln -s /opt/bundles/${branch} ${git}/bundles
	
		## Remove previous files
		## rm -rf ${git}/bundles/*
		
		## Save last commit of current branch
		git log | head -6 > ${gitroot}/bundles/commit-${branch}.txt
		
		
	for offset in 0 1
	do
		port=$((${nodes[i]}+${offset}))
		tomcathome=${appserverfolder}/${port}/apache-tomcat-${tomcatversion}
		propertyfile="app.server.${USER}.properties"
		## Rename the appropriate property file
		cp app.server.properties ${propertyfile}
		sed -i.bak "s!app\.server\.parent\.dir=.*!app.server.parent.dir=${appserverfolder}/${port}!" ${propertyfile}
		sed -i.bak "s!app\.server\.tomcat\.version=.*!app.server.tomcat.version=${tomcatversion}!" ${propertyfile}
		sed -i.bak 's!app\.server\.tomcat\.dir=.*!app.server.tomcat.dir=${app.server.parent.dir}/apache-tomcat-${app.server.tomcat.version}!' ${propertyfile}
		sed -i.bak "s!app\.server\.tomcat\.deploy\.dir=.*!app.server.tomcat.deploy.dir=${deploymentfolder}/${port}/${branch}!" ${propertyfile}
		sed -i.bak "s!app\.server\.tomcat\.lib\.global\.dir=.*!app.server.tomcat.lib.global.dir=${dependenciesfolder}/{branch}/dependencies!" ${propertyfile}
		sed -i.bak 's!app\.server\.tomcat\.lib\.endorsed\.dir=.*!app.server.tomcat.lib.endorsed.dir=${app.server.tomcat.lib.global.dir}!' ${propertyfile}
		sed -i.bak 's!app\.server\.tomcat\.lib\.support\.dir=.*!app.server.tomcat.lib.support.dir=${app.server.tomcat.lib.global.dir}!' ${propertyfile}
		sed -i.bak 's!app\.server\.tomcat\.zip\.url=.*!app.server.tomcat.zip.url=http://archive.apache.org/dist/tomcat/tomcat-7/v${app.server.tomcat.version}/bin/${app.server.tomcat.zip.name}!' ${propertyfile}
		## ant build: unzip-tomcat and all
		## ant -buildfile build-dist.xml unzip-tomcat &> ${tmpdir}/${branch}-ant-unzip-tomcat.log
		export JAVA_HOME="${javahome}"
		
		if [ ! -d ${tomcathome} ]
		then
			mkdir -p ${appserverfolder}/${port}
			ant -buildfile build-dist.xml unzip-tomcat
		fi
	
		ant all &> ${tmpdir}/${branch}-${node}-ant-all.log
	
	
		## Create bundle archive on success
		if [[ $? == 0  ]]
		then
			rm -f ${dependenciesfolder}/${branch}/portal-web.war
			cp ${workingdir}/portal-web/portal-web.war ${dependenciesfolder}/${branch}
			## Save building timestamp
			## touch ${git}/bundles/built-on-$(date "+%Y-%m-%d-%H%M")
	
			## Remove tomcat zip files from bundle
			## rm -f ${git}/bundles/apache-tomcat*.zip
	
			## Zip current branch
			## cd ${git}/bundles/
			## zip -qro /opt/bundles-out/liferay-${branch}-$(date "+%Y-%m-%d-%H%M").zip *
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
			echo "${branch} has been built successfully on ${port}"
		else
			## on failure:
	
			## Save last commit as failed.txt
			git log | head -6 > ${tmpdir}/build-failed-${branch}-$(date "+%Y-%m-%d-%H%M").txt
		fi
		
		## Rename back the property file
		# mv app.server.${USER}.properties ${propertyfile}
	done
	i=$((i+1))
done

## Checking if r2d2 is mounted
## grep -q "/media/r2d2" /etc/mtab

## if [[ $? != 0 ]]
## then
##	mount /media/r2d2
##	if [[ $? != 0 ]]
##	then
##		echo "Failed to mount /media/r2d2! Not copying bundles to r2d2."
##		exit 1
##	fi
## fi

## Copy bundles to r2d2
## mv /media/r2d2/Support/Bundles/*.* /media/r2d2/Support/Bundles/archive
## cp -r /opt/bundles-out/* /media/r2d2/Support/Bundles/

## Clean up tmpdir
## rm -rf ${tmpdir}

