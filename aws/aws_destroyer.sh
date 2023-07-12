#!/bin/bash

function usage {
  echo "Usage:

  $0  -i <Machine_ID> -g <Security_group_ID> \\
      -p <VPC_ID> -s <Subnet_ID>

Options
  r - Region name
  i - Machine instance id
  g - Security group id
  p - VPC id
  s - Subnet id
  v - verbose mode
  D - dry run
  h - print this help message
" >&2
}

while getopts ":vDhr:g:i:p:s:" options
  do
    case "${options}"
      in
        D)
          dryrun=1
          ;;
        v)
          verbose=1
          ;;
        h)
           usage
           exit 0
           ;;
        r)
          REGION="${OPTARG}"
           ;;
        i)
          INSTANCE_ID="${OPTARG}"
          ;;
        g)
          SG_ID="${OPTARG}"
          ;;
        p)
          VPC_ID="${OPTARG}"
          ;;
        s)
          SUBNET_ID="${OPTARG}"
          ;;
        \?)
          echo "Invalid option: -${OPTARG}" >&2
          exit 1
          ;;
        :)
          echo "Option -${OPTARG} requires an argument." >&2
          exit 1
          ;;
        *)
          usage
          exit 1
          ;;
    esac
done

if [ -z "$1" ]
then
  usage
  exit 0
fi

if [ -z "${REGION}" ]
then
  echo "Region must be set"
  error=1
fi

if [ -n "${error}" ]
then
  exit 1
fi


# The order of commands here matters
if [ -z "${INSTANCE_ID}" ]
then
  echo "No instance to terminate"
else
  QUERY="[TerminatingInstances[?InstanceId==\`${INSTANCE_ID}\`]][0][0].CurrentState.Name"
  if [ ! ${dryrun} ]
  then
    while [ "$(aws ec2 terminate-instances --instance-ids ${INSTANCE_ID} --region ${REGION} --query "${QUERY}" --output text)" != "terminated" ]; do echo "waiting temination"; sleep 1; done
  else
    echo "aws ec2 terminate-instances --instance-ids ${INSTANCE_ID} --region ${REGION} --query '${QUERY}' --output text"
  fi
fi

if [ -z "${SUBNET_ID}" ]
then
  echo "No subnet to delete"
else
  if [ ! ${dryrun} ]
  then
    aws ec2 delete-subnet --region ${REGION} --subnet-id ${SUBNET_ID}
  else
    echo "aws ec2 delete-subnet --region ${REGION} --subnet-id ${SUBNET_ID}"
  fi
fi

if [ -z "${SG_ID}" ]
then
  echo "No security group to delete"
else
  if [ ! ${dryrun} ]
  then
    aws ec2 delete-security-group --region ${REGION} --group-id ${SG_ID}
  else
    echo "aws ec2 delete-security-group --region ${REGION} --group-id ${SG_ID}"
  fi
fi

if [ -z "${VPC_ID}" ]
then
  echo "No VPC to delete"
else
  if [ ! ${dryrun} ]
  then
    aws ec2 delete-vpc --region ${REGION} --vpc-id ${VPC_ID}
  else
    echo "aws ec2 delete-vpc --region ${REGION} --vpc-id ${VPC_ID}"
  fi
fi
