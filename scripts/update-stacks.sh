#!/bin/bash

# exit immediately if a command exits with a non-zero status
set -e

# function to resolve a path
resolve() {
    cd "$(dirname "$1")"
    echo "$(pwd -P)/$(basename "$1")"
}

# get the absolute path of the script
scriptPath=$(
    cd "$(dirname "$0")"
    pwd -P
)

echo "Updating stacks..."

# get all available regions
regions=$(aws ec2 describe-regions --query "Regions[*].RegionName" --output text)
# define restricted regions
restrictedRegions=(\
    "ap-south-1" \
    "ap-northeast-1" \
    "ap-northeast-3" \
    "ap-northeast-2" \
    "ap-southeast-1" \
    "ap-southeast-2" \
    "sa-east-1" \
    "eu-north-1" \
    "eu-west-2" \
    "eu-west-3" \
    "us-east-2" \
    "ca-central-1" \
    "us-west-1" \
    "us-west-2")

agencyTemplatePath=$(resolve "$scriptPath/../agency/agency.yaml")
sftpServerTemplatePath=$(resolve "$scriptPath/../sftp-server/sftp-server.yaml")

# loop through each region and update the stack if a stack is an agency stack or a sftp server stack
for region in $regions; do
    # skip if the region is restricted
    if [[ ${restrictedRegions[@]} =~ $region ]]; then
        echo "Skipping restricted region: $region"
        continue
    fi

    echo "Checking stacks in region: $region"

    # get all the stacks in the region that are in the COMPLETE state
    stacks=$(aws cloudformation list-stacks \
        --stack-status-filter UPDATE_COMPLETE CREATE_COMPLETE ROLLBACK_COMPLETE UPDATE_ROLLBACK_COMPLETE \
        --region "$region" \
        --query "StackSummaries[*].StackName" \
        --output text)

    # loop through each stack and update if necessary
    for stack in $stacks; do
        # if stack name ends with "-agency" it is an agency stack
        if [[ "$stack" == *"-agency" ]]; then
            # update the agency stack
            echo "Updating agency stack: $stack in region $region with agency template"

            # set +e to ignore validation errors
            set +e

            error=$(aws cloudformation update-stack \
                --stack-name $stack \
                --template-body "file://$agencyTemplatePath" \
                --parameters \
                ParameterKey=AgencyName,UsePreviousValue=true \
                ParameterKey=PublicKey,UsePreviousValue=true \
                ParameterKey=MonitoringFrequency,UsePreviousValue=true \
                --region $region \
                --tags '[{"Key":"owner","Value":"'$OWNER'"},{"Key":"product","Value":"'$PRODUCT'"}]' \
                --capabilities CAPABILITY_NAMED_IAM 2>&1 1>/dev/null)

            errCode=$?
            
            # set -e to exit on other errors
            set -e

            # if there is no error continue to the next stack
            [[ $errCode -eq 0 ]] && continue
            
            # if there is a validation error continue to the next stack
            [[ $error =~ ".*\(ValidationError\).*" ]] && continue
            
            # otherwise exit with the error code
            echo "got error: $error"
            exit $errCode
        fi

        # if stack name is "sftp-server" it is an sftp server stack
        if [[ "$stack" == "sftp-server" ]]; then
            # update the stack
            echo "Updating sftp server stack: $stack in region $region with sftp server template"

            # set +e to ignore validation errors
            set +e

            error=$(aws cloudformation update-stack \
                --stack-name $stack \
                --template-body file://$sftpServerTemplatePath \
                --region $region \
                --parameters ParameterKey=DataOpsEmail,ParameterValue=$DATA_OPS_EMAIL \
                --tags '[{"Key":"owner","Value":"'$OWNER'"},{"Key":"product","Value":"'$PRODUCT'"}]' \
                --capabilities CAPABILITY_NAMED_IAM 2>&1 1>/dev/null)

            errCode=$?
            
            # set -e to exit on other errors
            set -e

            # if there is no error continue to the next stack
            [[ $errCode -eq 0 ]] && continue
            
            # if there is a validation error continue to the next stack
            [[ $error =~ ".*\(ValidationError\).*" ]] && continue
            
            # otherwise exit with the error code
            echo "got error: $error"
            exit $errCode
        fi
    done
done

echo "Stacks updated successfully."
