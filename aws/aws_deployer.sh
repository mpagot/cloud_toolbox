#!/bin/bash

function usage {
  echo "Usage:

  $0  -r <Region> -s <Security group name> \\
      -i <Image AMI ID> -m <Machine type>

Options
  r - Region name
  g - Security group name
  i - Image AMI id
  m - Machine type
  v - verbose mode
  D - dry run
  h - print this help message
" >&2
}

while getopts ":vDhr:g:i:m:" options
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
        g)
          GROUP="${OPTARG}"
          ;;
        i)
          IMAGE="${OPTARG}"
          ;;
        m)
          MACHINE_TYPE="${OPTARG}"
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

if [ -z "${GROUP}" ]
then
  echo "security group name name must be set"
  error=1
fi

if [ -z "${IMAGE}" ]
then
  echo "image name must be set"
  error=1
fi

if [ -z "${MACHINE_TYPE}" ]
then
  echo "Machine type must be set"
  error=1
fi

if [ -n "${error}" ]
then
  exit 1
fi

if [ ! ${dryrun} ]
then
  VPC_ID=$(aws ec2 create-vpc --region ${REGION} --cidr-block 10.0.0.0/28 --query 'Vpc.VpcId' --output text)
  SG_ID=$(aws ec2 create-security-group --region ${REGION} --group-name ${GROUP} --description "Security group for ${GROUP}" --vpc-id ${VPC_ID} --query 'GroupId' --output text)
  SUBNET_ID=$(aws ec2 create-subnet --region ${REGION} --cidr-block 10.0.0.0/28  --vpc-id ${VPC_ID} --query 'Subnet.SubnetId' --output text)
else
  echo "aws ec2 create-vpc --region ${REGION} --cidr-block 10.0.0.0/28 --query 'Vpc.VpcId' --output text"
  echo "aws ec2 create-security-group --region ${REGION} --group-name ${GROUP} --description \"Security group for ${GROUP}\" --vpc-id <VPC_ID> --query 'GroupId' --output text"
  echo "aws ec2 create-subnet --region ${REGION} --cidr-block 10.0.0.0/28  --vpc-id <VPC_ID> --query 'Subnet.SubnetId' --output text"
fi

if [ ! ${dryrun} ]
then
  echo "Create VM with:"
  echo "    REGION:${REGION}"
  echo "    GROUP:${GROUP}"
  echo "    IMAGE:${IMAGE}"
  echo "    MACHINE_TYPE:${MACHINE_TYPE}"
  echo "    VPC_ID:${VPC_ID}"
  echo "    SG_ID:${SG_ID}"
  echo "    SUBNET_ID:${SUBNET_ID}"
  export INSTANCE_ID=$(aws ec2 run-instances --region ${REGION} --image-id ${IMAGE} --instance-type ${MACHINE_TYPE} --security-group-ids "${SG_ID}" --subnet-id "${SUBNET_ID}" --query 'Instances[0].InstanceId' --output text)
  echo "Created VM ${INSTANCE_ID}"
else
  echo "aws ec2 run-instances --region ${REGION} --image-id ${IMAGE} --instance-type ${MACHINE_TYPE} --security-group-ids <SG_ID> --subnet-id <SUBNET_ID> --query 'Instances[0].InstanceId' --output text"
fi
