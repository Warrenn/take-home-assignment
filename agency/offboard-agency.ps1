param (
    [String]
    $awsProfile = "",
    [String]
    [Parameter(Mandatory = $true)]
    $region,
    [String]
    [Parameter(Mandatory = $true)]
    $agencyName
)

if ([string]::IsNullOrEmpty($awsProfile)) {
    $awsProfile = $Env:AWS_PROFILE
}

if ([string]::IsNullOrEmpty($awsProfile)) {
    $awsProfile = "default"
}

# get the cloudformation stacks in the region
$stacks = [string]::Join("", $(aws cloudformation list-stacks `
            --stack-status-filter CREATE_COMPLETE ROLLBACK_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE `
            --region $region `
            --profile $awsProfile `
            --query "StackSummaries[*].StackName" `
            --output json)) | ConvertFrom-Json

# check if the agency stack for the agency name exists in the region if not throw an error
$stacksWithName = $($stacks | Where-Object { $_ -eq "$agencyName-agency" })
if ($stacksWithName.Count -eq 0) {
    throw "Agency $agencyName does not exist in region $region"
}

# get the cloudformation exports for the agency stack
$exports = [string]::Join("", $(aws cloudformation list-exports `
            --profile $awsProfile `
            --region $region `
            --query "Exports[*]" `
            --output json)) | ConvertFrom-Json

# get the name of the s3 bucket for the agency
$agencyBucketName = $($exports | Where-Object { $_.Name -eq "$agencyName-s3-bucket-name" }).Value

if ([string]::IsNullOrEmpty($agencyBucketName)) {
    throw "Couldn't find S3 bucket for $agencyName in region $region"
}

# using cloudformation check if there are any objects in the agency bucket
$s3Objects = [string]::Join("", $(aws s3api list-objects `
            --bucket $agencyBucketName `
            --profile $awsProfile `
            --query "Contents[*]" `
            --output json)) | ConvertFrom-Json

if ($s3Objects.Count -gt 0) {
    $confirmDelete = Read-Host "Thare are files in $agencyBucketName bucket are you sure you want to delete the agency $agencyName in region $region? (y/n)"
    if ($confirmDelete -ne "y") {
        throw "Agency $agencyName in region $region will not be deleted"
    }

    write-output "Deleting files in $agencyBucketName bucket..."
    # delete the s3 bucket and all objects using the force option
    aws s3 rb s3://$agencyBucketName `
        --force `
        --region $region `
        --profile $awsProfile
}

# get the product from the workflow file
$workflowYamlContent = Get-Content $(Resolve-Path "$PSScriptRoot\..\.github\workflows\update-stacks.yml")
$product = $($workflowYamlContent -match "^.*PRODUCT.*:.*").Split(":")[1].Trim().Trim("""")

# get a list of all the parameters in the region
$parameters = [string]::Join("", $(aws ssm describe-parameters `
            --query "Parameters[*]" `
            --region $region `
            --profile $awsProfile `
            --output json)) | ConvertFrom-Json

# check if the sftp public key parameter exists in the region if so delete it
$sftpPublicKeyParameter = $($parameters | Where-Object { $_.Name -eq "/$product/sftp-public-key/$agencyName" })
if ($sftpPublicKeyParameter.Count -gt 0) {
    write-output "Deleting sftp public key parameter..."
    aws ssm delete-parameter `
        --name "/$product/sftp-public-key/$agencyName" `
        --region $region `
        --profile $awsProfile
}

# check if the sftp private key parameter exists in the region if so delete it
$sftpPrivateKeyParameter = $($parameters | Where-Object { $_.Name -eq "/$product/sftp-private-key/$agencyName" })
if ($sftpPrivateKeyParameter.Count -gt 0) {
    write-output "Deleting sftp private key parameter..."
    aws ssm delete-parameter `
        --name "/$product/sftp-private-key/$agencyName" `
        --region $region `
        --profile $awsProfile
}

# check if the sftp pass phrase parameter exists in the region if so delete it
$sftpPassPhraseParameter = $($parameters | Where-Object { $_.Name -eq "/$product/sftp-pass-phrase/$agencyName" })
if ($sftpPassPhraseParameter.Count -gt 0) {
    write-output "Deleting sftp pass phrase parameter..."
    aws ssm delete-parameter `
        --name "/$product/sftp-pass-phrase/$agencyName" `
        --region $region `
        --profile $awsProfile
}

# delete the agency stack
write-output "Deleting agency stack..."
aws cloudformation delete-stack `
    --stack-name "$agencyName-agency" `
    --region $region `
    --profile $awsProfile

Start-Sleep -Seconds 30 # Wait for stack to be deleted

# check if there are any agency stacks in the region in COMPLETE state
$stacks = [string]::Join("", $(aws cloudformation list-stacks `
            --stack-status-filter CREATE_COMPLETE ROLLBACK_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE `
            --region $region `
            --query "StackSummaries[*].StackName" `
            --profile $awsProfile `
            --output json)) | ConvertFrom-Json
        
$agencyStacks = $($stacks | Where-Object { $_ -like "*-agency" })
if ($agencyStacks.Count -eq 0) {
    # delete the sftp server stack
    write-output "Deleting sftp server stack..."
    aws cloudformation delete-stack `
        --stack-name "sftp-server" `
        --region $region `
        --profile $awsProfile
}

write-output "Agency $agencyName offboarded successfully..."
