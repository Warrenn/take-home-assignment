param (
    [String]
    $awsProfile = "",
    [String]
    $region = "eu-west-1",
    [String]
    [Parameter(Mandatory = $true)]
    $templateFile,
    [String]
    [Parameter(Mandatory = $true)]
    $stackName
)

if ([string]::IsNullOrEmpty($awsProfile)) {
    $awsProfile = $Env:AWS_PROFILE
}

if ([string]::IsNullOrEmpty($awsProfile)) {
    $awsProfile = "default"
}

$deploymentConfig = Get-Content ./code-pipeline-stack-deployment.json | ConvertFrom-Json
$owner = $deploymentConfig.tags.owner
$product = $deploymentConfig.tags.product

# Function to deploy a new stack
function DeployNewStack {
    Write-Output "Deploying new stack..."
    aws cloudformation deploy `
        --template-file $templateFile `
        --stack-name $stackName `
        --profile $awsProfile `
        --region $region `
        --tags `
            owner=$owner `
            product=$product `
        --capabilities CAPABILITY_NAMED_IAM `
        --output json
}

# Function to update an existing stack
function UpdateStack {
    Write-Output "Updating stack..."
    aws cloudformation update-stack `
        --stack-name $stackName `
        --template-body file://$templateFile `
        --region $region `
        --tags "[{""Key"":""owner"",""Value"":""$owner""},{""Key"":""product"",""Value"":""$product""}]" `
        --capabilities CAPABILITY_NAMED_IAM `
        --output json
}

# Function to delete a stack
function DeleteStack {
    Write-Output "Deleting stack..."
    aws cloudformation delete-stack `
        --stack-name $stackName `
        --region $region `
        --output json
}

# Check the status of the stack
$status = aws cloudformation describe-stacks `
    --stack-name $stackName `
    --region $region `
    --query "Stacks[0].StackStatus" `
    --output text

write-output "Stack status: $status"

if ($status -eq "NotFoundException" -or [System.String]::IsNullOrEmpty($status)) {
    # Stack does not exist, deploy new stack
    DeployNewStack
}
elseif ($status -eq "CREATE_FAILED" -or $status -eq "ROLLBACK_FAILED" -or $status -eq "ROLLBACK_COMPLETE" -or $status -eq "DELETE_FAILED" -or $status -eq "UPDATE_ROLLBACK_FAILED") {
    # Stack is in error state, delete and redeploy
    DeleteStack
    Start-Sleep -Seconds 30 # Wait for stack to be deleted
    DeployNewStack
}
else {
    # Stack exists and is not in error, update if necessary
    UpdateStack
}

 