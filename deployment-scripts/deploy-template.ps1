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
    $stackName,
    [PSCustomObject]
    $tags = $null,
    [PSCustomObject]
    $overrides = $null
)

if ([string]::IsNullOrEmpty($awsProfile)) {
    $awsProfile = $Env:AWS_PROFILE
}

if ([string]::IsNullOrEmpty($awsProfile)) {
    $awsProfile = "default"
}

# Function to deploy a new stack
function DeployNewStack {
    Write-Output "Deploying new stack..."

    $parameters = @(
        "--template-file $templateFile", 
        "--stack-name $stackName", 
        "--profile $awsProfile",  
        "--region $region",
        "--capabilities CAPABILITY_NAMED_IAM",
        "--output json")
    
    if ($null -ne $tags) {
        $parameters += "--tags ```n$([string]::Join(" ```n",$($tags.PSObject.Properties | ForEach-Object { "$($_.Name)='$($_.Value)'" })))"
    }

    if ($null -ne $overrides) {
        $parameters += "--parameter-overrides $([string]::Join(" ",$($overrides.PSObject.Properties | ForEach-Object { "$($_.Name)='$($_.Value)'" })))"
    }

    Invoke-Expression "& aws cloudformation deploy $parameters"
}

# Function to update an existing stack
function UpdateStack {
    Write-Output "Updating stack..."


    $parameters = @(
        "--stack-name $stackName", 
        "--template-body file://$templateFile", 
        "--profile $awsProfile",  
        "--region $region",
        "--capabilities CAPABILITY_NAMED_IAM",
        "--output json")
    
    if ($null -ne $tags) {
        $parameters += "--tags '[$([string]::Join(",",$($tags.PSObject.Properties | ForEach-Object { "{`"`"Key`"`":`"`"$($_.Name)`"`",`"`"Value`"`":`"`"$($_.Value)`"`"}" })))]'"
    }

    if ($null -ne $overrides) {
        $parameters += "--parameters $([string]::Join(" ",$($overrides.PSObject.Properties | ForEach-Object { "ParameterKey=$($_.Name),ParameterValue=$($_.Value)" })))"
    }

    Invoke-Expression "& aws cloudformation update-stack $parameters"
}

# Function to delete a stack
function DeleteStack {
    Write-Output "Deleting stack..."
    aws cloudformation delete-stack `
        --stack-name $stackName `
        --profile $awsProfile `
        --region $region `
        --output json
}

# Check the status of the stack
$status = aws cloudformation describe-stacks `
    --stack-name $stackName `
    --region $region `
    --profile $awsProfile `
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

 