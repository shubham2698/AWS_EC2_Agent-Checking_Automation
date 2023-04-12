#!/bin/bash
echo "Profile name ,Region , InstanceId,Instance Name,Project Name ,Platform,Release Train,TaggingVersion ,Qualys Status,Instance state,Environment,Market" >> QualysStatusReport.csv

Project_name="";
Instance_name="";
instance_state="";
Project_environment="";
Business_Service="";

declare -A input
input["sandbox-frankfurt"]="eu-central-1"
input["sandbox-london"]="eu-west-2"


describe_server_tag(){
  Project_name=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$id" "Name=key,Values=$1" --output json --region $f2 --profile $f1 --query 'Tags[0].Value');
  Instance_name=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$id" "Name=key,Values=$2" --output json --region $f2 --profile $f1 --query 'Tags[0].Value');
  Project_environment=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$id" "Name=key,Values=$3" --region $f2 --profile $f1 --query Tags[0].Value --output json);
  Business_Service=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$id" "Name=key,Values=$4" --region $f2 --profile $f1 --query Tags[0].Value --output json);
  instance_state=$(aws ec2 describe-instances --instance-ids $id --query Reservations[*].Instances[*].[State.Name] --region $f2 --profile $f1 --output text);
  echo "instance_state ${instance_state}";
}

for index in ${!input[*]}
do
  f1=$index
  f2=${input[$index]}
  echo "Qualys Reporting Initiated for Profile ${f1} and Region ${f2}..."	
				  
  for id in $(aws ec2 describe-instances --query Reservations[*].Instances[*].[InstanceId] --region $f2 --profile $f1 --output text); do
    
    id=$(echo "${id}");
    echo "Reporting for InstanceId ${id} "
    status="";
    os=$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$id" --query 'InstanceInformationList[*].[PlatformType]' --region $f2 --profile $f1 --output text);
    os=$(echo "${os}");
    if [ "$os" = "Linux" ]; then
      Command_Id_temp=$(aws ssm send-command --document-name "AWS-RunShellScript" --instance-ids "${id}" --parameters '{"commands":["#!/bin/bash","systemctl show qualys-cloud-agent --property=ActiveState"]}' --profile $f1 --region $f2 --query 'Command.CommandId'); 
      Command_Id=`sed -e 's/^"//' -e 's/"$//' <<<"$Command_Id_temp"`;
      COMMANDOUTPUT=$(aws ssm get-command-invocation --command-id ${Command_Id} --instance-id ${id}  --region $f2 --profile $f1 | grep "ActiveState") ;
      describe_server_tag Project Name Environment BusinessService;

      ACTIVE='Active: active (running)'
      INACTIVE='Active: inactive (dead)'

      if [[ "$COMMANDOUTPUT" =~ ."=active". ]]; then
        status="qualys-cloud-agent is installed and running."
      elif [[ "$COMMANDOUTPUT" =~ ."=inactive". ]]; then
        status="qualys-cloud-agent is not installed or not running."
      else
      status="Unknown Error"
      fi
      echo "${f1},${f2}, ${id} ,${Instance_name}, ${Project_name} ,${os},${Business_Service},V2.4, ${status} ,${instance_state} ,${Project_environment}" >> QualysStatusReport.csv

    elif [ "$os" = "Windows" ]; then
    Command_Id_temp=$(aws ssm send-command --document-name "AWS-RunPowerShellScript" --instance-ids "${id}" --parameters '{"commands":["get-service QualysAgent | select Status"]}' --profile $f1 --region $f2 --query 'Command.CommandId'); 
    Command_Id=`sed -e 's/^"//' -e 's/"$//' <<<"$Command_Id_temp"`;
    COMMANDOUTPUT=$(aws ssm get-command-invocation --command-id ${Command_Id} --instance-id ${id}  --region $f2 --profile $f1 | grep "Status") ;

    describe_server_tag Project Name Environment BusinessService;

    standardErrorContent='StandardErrorContent'
    running='Running'
    stopped='Stopped'

    if [[ "$COMMANDOUTPUT" =~ .*"$running".* ]]; then
      status="qualys-cloud-agent is installed and running."
    elif [[ "$COMMANDOUTPUT" =~ .*"$stopped".* ]]; then
      status="qualys-cloud-agent is not running."
    elif [[ "$COMMANDOUTPUT" =~ .*"$standardErrorContent".* ]]; then
      status="qualys-cloud-agent is not installed."
    else
      status="Unknown error"
    fi

    echo "${f1},${f2}, ${id} ,${Instance_name}, ${Project_name} ,${os},${Business_Service},V2.4, ${status} ,${instance_state} ,${Project_environment}" >> QualysStatusReport.csv
    else
      echo "Instance Stopped ${id}"
  fi

done
echo "Qualys Reporting Ended for Profile ${f1} and Region ${f2}"
done 
echo "Qualys Reporting Finished"
$upload=$(aws s3 cp ./QualysStatusReport.csv s3://buket-name/);
echo $upload;
