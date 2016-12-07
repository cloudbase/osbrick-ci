#!/bin/bash
#

# Loading all the needed functions
source /usr/local/src/osbrick-ci/jobs/library.sh

# Loading parameters
source /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.$JOB_TYPE.txt

# Maybe this should not be hardcoded.
SCRIPTS_DIR="/usr/local/src/osbrick-ci"
function update_local_conf (){

    VALID_JOB_TYPES=("iscsi" "fc" "smbfs")
    if [[ "${VALID_JOB_TYPES[@]}" =~ $JOB_TYPE ]]; then
        EXTRA_OPTS_PATH="$SCRIPTS_DIR/jobs/$JOB_TYPE/local-conf-extra"
    else
        echo "Invalid JOB_TYPE received: ($JOB_TYPE). Expecting $VALID_JOB_TYPES."
        exit 1
    fi

    scp -v -r -o "StrictHostKeyChecking no" -o "UserKnownHostsFile /dev/null" \
        -i $DEVSTACK_SSH_KEY $EXTRA_OPTS_PATH \
        ubuntu@$FLOATING_IP:/home/ubuntu/devstack
    run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY \
        "cat /home/ubuntu/devstack/local-conf-extra >> /home/ubuntu/devstack/local.conf" 6
}

hyperv01=$1

# Update local conf
update_local_conf

# add zuul branch to local.sh
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "sed -i '3 i\branch=$ZUUL_BRANCH' /home/ubuntu/devstack/local.sh"

# run devstack
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "source /home/ubuntu/keystonerc && /home/ubuntu/bin/run_devstack.sh $hyperv01" 5

# run post_stack
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "source /home/ubuntu/keystonerc && /home/ubuntu/bin/post_stack.sh $JOB_TYPE" 5
