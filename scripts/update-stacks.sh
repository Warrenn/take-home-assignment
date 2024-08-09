#!/bin/bash

# Set -e to exit immediately if any command fails
set -e

# Function to compute SHA-512 hash
compute_sha512() {
    if command -v sha512sum &>/dev/null; then
        sha512sum "$1" | awk '{ print $1 }'
    elif command -v shasum &>/dev/null; then
        shasum -a 512 "$1" | awk '{ print $1 }'
    else
        echo "Neither sha512sum nor shasum is available" >&2
        exit 1
    fi
}

# Function to resolve a path
resolve() {
    cd "$(dirname "$1")"
    echo "$(pwd -P)/$(basename "$1")"
}

# Get the absolute path of the script
scriptPath=$(
    cd "$(dirname "$0")"
    pwd -P
)

echo "Updating stacks..."

# Get all available regions
regions=$(aws ec2 describe-regions --query "Regions[*].RegionName" --output text)
restrictedRegions=("ap-south-1" "ap-northeast-3" "ap-northeast-2" "ap-southeast-1" "ap-southeast-2" "eu-north-1")

agencyTemplatePath=$(resolve "$scriptPath/../agency/agency.yaml")
sftpServerTemplatePath=$(resolve "$scriptPath/../sftp-server/sftp-server.yaml")

agencyHash=$(compute_sha512 "$agencyTemplatePath")
sftpServerHash=$(compute_sha512 "$sftpServerTemplatePath")

# Loop through each region and update the stack if the sha512 hash does not match
for region in $regions; do
    if [[ ${restrictedRegions[@]} =~ $region ]]; then
        echo "Skipping restricted region: $region"
        continue
    fi

    echo "Checking stacks in region: $region"

    # Get all the stacks in the region that are in the COMPLETE state
    stacks=$(aws cloudformation list-stacks \
        --stack-status-filter UPDATE_COMPLETE CREATE_COMPLETE ROLLBACK_COMPLETE UPDATE_ROLLBACK_COMPLETE \
        --region "$region" \
        --query "StackSummaries[*].StackName" \
        --output text)

    # Loop through each stack and check if the sha512 hash matches
    for stack in $stacks; do

        # Check if stack ends with "-agency" or "-sftp-server"
        if [[ "$stack" != *"-agency" ]] && [[ "$stack" != "sftp-server" ]]; then
            continue
        fi

        # Get the stack details
        stackDetails=$(aws cloudformation describe-stacks \
            --stack-name "$stack" \
            --region "$region" \
            --query "Stacks[0]" \
            --output json)

        # Get the owner,sha512 and product tags
        owner=$(echo "$stackDetails" | jq -r '.Tags[] | select(.Key == "owner") | .Value')
        product=$(echo "$stackDetails" | jq -r '.Tags[] | select(.Key == "product") | .Value')
        sha512=$(echo "$stackDetails" | jq -r '.Tags[] | select(.Key == "sha512") | .Value')

        # Get the DataOpsEmail Parameter from the stack
        dataOpsEmail=$(echo "$stackDetails" | jq -r '.Parameters[] | select(.ParameterKey == "DataOpsEmail") | .ParameterValue')

        # if stack ends with "-agency" compare the sha512 hash of the template with the agency template hash
        if [[ "$stack" == *"-agency" ]] && [[ $sha512 != $agencyHash || $owner != $OWNER || $product != $PRODUCT ]]; then
            # update the stack
            echo "Updating stack: $stack in region $region with agency template"

            aws cloudformation update-stack \
                --stack-name $stack \
                --template-body "file://$agencyTemplatePath" \
                --parameters \
                ParameterKey=AgencyName,UsePreviousValue=true \
                ParameterKey=PublicKey,UsePreviousValue=true \
                ParameterKey=MonitoringFrequency,UsePreviousValue=true \
                --region $region \
                --tags '[{"Key":"owner","Value":"'$OWNER'"},{"Key":"product","Value":"'$PRODUCT'"},{"Key":"sha512","Value":"'$agencyHash'"}]' \
                --capabilities CAPABILITY_NAMED_IAM

            continue
        fi

        # if stack ends with "sftp-server" compare the sha512 hash of the template with the sftp server template hash
        if [[ "$stack" == "sftp-server" ]] && [[ $sha512 != $sftpServerHash || $owner != $OWNER || $product != $PRODUCT || $dataOpsEmail != $DATA_OPS_EMAIL ]]; then
            # update the stack
            echo "Updating stack: $stack in region $region with sftp server template"

            aws cloudformation update-stack \
                --stack-name $stack \
                --template-body file://$sftpServerTemplatePath \
                --region $region \
                --parameters ParameterKey=DataOpsEmail,ParameterValue=$DATA_OPS_EMAIL \
                --tags '[{"Key":"owner","Value":"'$OWNER'"},{"Key":"product","Value":"'$PRODUCT'"},{"Key":"sha512","Value":"'$sftpServerHash'"}]' \
                --capabilities CAPABILITY_NAMED_IAM
        fi
    done
done

echo "Stacks updated successfully."
