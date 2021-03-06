

DRIFTIDS=()

OLDIFS=$IFS
IFS=' '

aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE > stacks-new
if [ $? != 0 ]; then
    exit 56
fi

while read stack; do
    thisID=`aws cloudformation detect-stack-drift --stack-name $stack | jq -r '.StackDriftDetectionId'`
    DRIFTIDS+=($thisID)
done <<< $(cat stacks-new | jq -r '.StackSummaries[].StackName' | grep $ENV-$SUBSYSTEM)

IFS=$OLDIFS


# Wait till all drift checks have completed
statusComplete="false"
while [ $statusComplete = "false" ]
do
    count=
    INPROGDRIFT=()
    for id in "${DRIFTIDS[@]}"
    do
        DRIFTSTATUS=`aws cloudformation describe-stack-drift-detection-status --stack-drift-detection-id $id | jq -r '.DetectionStatus'`

        if [ $DRIFTSTATUS == "DETECTION_IN_PROGRESS" ]; then
          count=$(( $count + 1 ))
          INPROGDRIFT+=($id)
        fi    
    done

    DRIFTIDS=()
    DRIFTIDS=("${INPROGDRIFT[@]}") 
    

    if [ $count > 0 ]; then
      statusComplete="false"
      sleep 5
    else
      statusComplete="true"
    fi
done

RED='\033[0;31m'
GREEN='\033[0;32m'
NOCOLOR='\033[0m'

driftcount=
# Get drift results 
echo "#################################"
echo "CHECKING FOR DRIFTED RESOURCES..."
echo "#################################"
for stack in $(cat stacks-new | jq -r '.StackSummaries[].StackName' | grep $ENV-$SUBSYSTEM); do
    DRIFTRESULT=`aws cloudformation describe-stacks --stack-name $stack | jq -r '.Stacks[].DriftInformation.StackDriftStatus'`
    if [ $DRIFTRESULT != "IN_SYNC" ]; then
      driftcount=$(( $driftcount + 1 ))
      printf "STACK NAME <========> $stack ${RED}\t\t$DRIFTRESULT ${NOCOLOR}\n\n"
      aws cloudformation  describe-stack-resource-drifts --stack-name $stack | jq -r '.StackResourceDrifts[] | select(.StackResourceDriftStatus != "IN_SYNC")'
      printf "\n\n\n\n" 
    fi
done

if [ $driftcount > 0 ]; then
  exit 56
else
printf "\n\n\n\n"
echo "##########################################"
echo "NO DRIFTS DETECTED. ALL RESOURCES IN SYNC"
echo "##########################################"
  exit 0
fi


