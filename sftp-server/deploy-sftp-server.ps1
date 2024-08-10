param (
    [String]
    $awsProfile = "",
    [String]
    [Parameter(Mandatory = $true)]
    $region,
    [String]
    $dataOpsEmail = ""
)

write-output "Deploying SFTP Server..."

# get the owner and product tags from the workflow file
$workflowYamlContent = Get-Content $(Resolve-Path "$PSScriptRoot\..\.github\workflows\update-stacks.yml")
$owner = $($workflowYamlContent -match "^.*OWNER.*:.*").Split(":")[1].Trim().Trim("""") 
$product = $($workflowYamlContent -match "^.*PRODUCT.*:.*").Split(":")[1].Trim().Trim("""")

# if the dataOpsEmail is not provided use the value from the workflow file
if ([string]::IsNullOrEmpty($dataOpsEmail)) {
    $dataOpsEmail = $($workflowYamlContent -match "^.*DATA_OPS_EMAIL.*:.*").Split(":")[1].Trim().Trim("""")
}

# using deploy-template.ps1 script to deploy the sftp server stack
$scriptsPath = Resolve-Path "$PSScriptRoot\..\scripts"
& "$scriptsPath\deploy-template.ps1" `
    -awsProfile $awsProfile `
    -region $region `
    -templateFile "$PSScriptRoot/sftp-server.yaml" `
    -stackName "sftp-server" `
    -overrides $([pscustomobject]@{ DataOpsEmail = $dataOpsEmail }) `
    -tags $([pscustomobject]@{ owner = $owner; product = $product })
