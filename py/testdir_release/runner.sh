#!/bin/bash

# Normally die on first error
set -e

echo "Setting PATH and showing java/python versions"
date
export PATH="/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin"
echo "Checking python/java links and revs first"
echo "JAVA_HOME: $JAVA_HOME"
which java
java -version
which javac
javac -version
echo "PATH: $PATH"
which python
python --version

# This is critical:
# Ensure that all your children are truly dead when you yourself are killed.
# trap "kill -- -$BASHPID" INT TERM EXIT
# leave out EXIT for now
trap "kill -- -$BASHPID" INT TERM
echo "BASHPID: $BASHPID"
echo "current PID: $$"
# The -PID argument tells bash to kill the process group with id $BASHPID, 
# Process groups have the same id as the spawning process, 
# The process group id remains even after processes have been reparented. (say by init)
# The -- gets kill not to interpret this as a signal ..
# Don't use kill -9 though to kill this script though!
# Get the latest jar from s3. Has to execute up in h2o

# a secret way to skip the download (use any arg)
if [ $# -eq 0 ]
then
    cd ../..
    ./get_s3_jar.sh
    # I'm back!
    cd -
fi

rm -f h2o-nodes.json
if [[ $USER == "jenkins" ]]
then 
    # clean out old ice roots from 0xcust.** (assuming we're going to run as 0xcust..
    # only do this if you're jenksin
    echo "If we use more machines, expand this cleaning list."
    echo "The possibilities should be relatively static over time"
    echo "Could be problems if other threads also using that user on these machines at same time"
    echo "Could make the rm pattern match a "sourcing job", not just 0xcustomer"
    ssh -i ~/.0xcustomer/0xcustomer_id_rsa 0xcustomer@192.168.1.164 rm -f -r /home/0xcustomer/ice*

    python ../four_hour_cloud.py -cj pytest_config-jenkins.json &
else
    python ../four_hour_cloud.py &
fi 

CLOUD_PID=$!
jobs -l

echo ""
echo "Have to wait until h2o-nodes.json is available from the cloud build. Deleted it above."
echo "spin loop here waiting for it. Since the h2o.jar copy slows each node creation"
echo "it might be 12 secs per node"

while [ ! -f ./h2o-nodes.json ]
do
  sleep 5
done
ls -lt ./h2o-nodes.json


# We now have the h2o-nodes.json, that means we started the jvms
# Shouldn't need to wait for h2o cloud here..
# the test should do the normal cloud-stabilize before it does anything.
# n0.doit uses nosetests so the xml gets created on completion. (n0.doit is a single test thing)
# A little '|| true' hack to make sure we don't fail out if this subtest fails
# test_c1_rel has 1 subtest

# This could be a runner, that loops thru a list of tests.

echo "If it exists, pytest_config-<username>.json in this dir will be used"
echo "i.e. pytest_config-jenkins.json"
echo "Used to run as 0xcust.., with multi-node targets (possibly)"
../testdir_single_jvm/n0.doit c1/test_c1_rel.py || true
../testdir_single_jvm/n0.doit c2/test_c2_rel.py || true
# If this one fails, fail this script so the bash dies 
# We don't want to hang waiting for the cloud to terminate.
../testdir_single_jvm/n0.doit test_shutdown.py

if ps -p $CLOUD_PID > /dev/null
then
    echo "$CLOUD_PID is still running after shutdown. Will kill"
    kill $CLOUD_PID
fi
ps aux | grep four_hour_cloud

# test_c2_rel has about 11 subtests inside it, that will be tracked individually by jenkins
# ../testdir_single_jvm/n0.doit test_c2_rel || true
# We don't want the jenkins job to complete until we kill it, so the cloud stays alive for debug
# also prevents us from overrunning ourselves with cloud building
# If we don't wait, the cloud will get torn down.

jobs -l
echo ""
echo "You can stop this jenkins job now if you want. It's all done"

# if wait $cloud_pid
# then
#     echo "$cloud_pid succeeded"
# else
#     echo "$pid failed"
# fi
# 
