basedir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.$JOB_TYPE.txt
source /home/jenkins-slave/tools/keystonerc_admin
source $basedir/library.sh

logs_project=os-brick

set +e
set -f

[ "$IS_DEBUG_JOB" != "yes" ] && run_wsmancmd_with_retry $hyperv01 $WIN_USER $WIN_PASS 'powershell -executionpolicy remotesigned Stop-Service nova-compute'
[ "$IS_DEBUG_JOB" != "yes" ] && run_wsmancmd_with_retry $hyperv01 $WIN_USER $WIN_PASS 'powershell -executionpolicy remotesigned Stop-Service neutron-hyperv-agent'
run_wsmancmd_with_retry $hyperv01 $WIN_USER $WIN_PASS 'powershell -executionpolicy remotesigned C:\OpenStack\osbrick-ci\HyperV\scripts\export-eventlog.ps1'
run_wsmancmd_with_retry $hyperv01 $WIN_USER $WIN_PASS 'powershell -executionpolicy remotesigned C:\OpenStack\osbrick-ci\HyperV\scripts\collect_systemlogs.ps1'

set +f
echo "Collecting logs"
ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $DEVSTACK_SSH_KEY ubuntu@$FLOATING_IP "/home/ubuntu/bin/collect_logs.sh $hyperv01 $IS_DEBUG_JOB"

echo "Downloading logs"
scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $DEVSTACK_SSH_KEY ubuntu@$FLOATING_IP:/home/ubuntu/aggregate.tar.gz "aggregate-$VMID.tar.gz"

gzip -9 /home/jenkins-slave/logs/console-$ZUUL_UUID-$JOB_TYPE.log
gzip -9 /home/jenkins-slave/logs/hyperv-build-log-$ZUUL_UUID-$JOB_TYPE-$hyperv01.log
gzip -9 /home/jenkins-slave/logs/devstack-build-log-$ZUUL_UUID-$JOB_TYPE.log

if [ "$IS_DEBUG_JOB" != "yes" ]; then
    LOGDEST="/srv/logs/$logs_project/$ZUUL_CHANGE/$ZUUL_PATCHSET/$JOB_TYPE"
else
    TIMESTAMP=$(date +%d-%m-%Y_%H-%M)
    LOGDEST="/srv/logs/debug/$logs_project/$ZUUL_CHANGE/$ZUUL_PATCHSET/$JOB_TYPE/$TIMESTAMP" 
fi

echo "Creating logs destination folder"
ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY logs@logs.openstack.tld "if [ -z '$ZUUL_CHANGE' ] || [ -z '$JOB_TYPE' ] || [ -z '$ZUUL_PATCHSET' ]; then echo 'Missing parameters!'; exit 1; elif [ ! -d $LOGDEST ]; then mkdir -p $LOGDEST; else rm -rf $LOGDES; fi"


echo "Uploading logs"
scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY "aggregate-$VMID.tar.gz" logs@logs.openstack.tld:$LOGDEST/aggregate-logs.tar.gz

echo "Extracting logs"
ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY logs@logs.openstack.tld "tar -xzf $LOGDEST/aggregate-logs.tar.gz -C $LOGDEST/"

echo "Uploading temporary logs"
scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY "/home/jenkins-slave/logs/console-$ZUUL_UUID-$JOB_TYPE.log.gz" logs@logs.openstack.tld:$LOGDEST/console.log.gz

scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY "/home/jenkins-slave/logs/hyperv-build-log-$ZUUL_UUID-$JOB_TYPE-$hyperv01.log.gz" logs@logs.openstack.tld:$LOGDEST/hyperv-build-log-$ZUUL_UUID-$JOB_TYPE-$hyperv01.log.gz
scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY "/home/jenkins-slave/logs/devstack-build-log-$ZUUL_UUID-$JOB_TYPE.log.gz" logs@logs.openstack.tld:$LOGDEST/devstack-build-log-$ZUUL_UUID-$JOB_TYPE.log.gz

echo "Fixing permissions on all log files"
ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY logs@logs.openstack.tld "chmod a+rx -R $LOGDEST"

echo "Removing local copy of aggregate logs"
rm -fv aggregate-$VMID.tar.gz
rm -f /home/jenkins-slave/logs/console-$ZUUL_UUID-$JOB_TYPE.log.gz

echo "Removing HyperV temporary console logs.."
rm -fv /home/jenkins-slave/logs/hyperv-build-log-$ZUUL_UUID-$JOB_TYPE-$hyperv01.log.gz

echo "Removing temporary devstack log.."
rm -fv /home/jenkins-slave/logs/devstack-build-log-$ZUUL_UUID-$JOB_TYPE.log.gz

echo `date -u +%H:%M:%S`
set -e
