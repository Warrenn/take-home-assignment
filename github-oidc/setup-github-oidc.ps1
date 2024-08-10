param (
    [String]
    $awsProfile = ""
)

write-output "Setting up GitHub OIDC..."

# get the owner and product tags from the workflow file
$workflowYamlContent = Get-Content $(Resolve-Path "$PSScriptRoot\..\.github\workflows\update-stacks.yml")
$region = $($workflowYamlContent -match "^.*AWS_DEFAULT_REGION.*:.*").Split(":")[1].Trim().Trim("""")
$owner = $($workflowYamlContent -match "^.*OWNER.*:.*").Split(":")[1].Trim().Trim("""") 
$product = $($workflowYamlContent -match "^.*PRODUCT.*:.*").Split(":")[1].Trim().Trim("""") 

# using deploy-template.ps1 script deploy the github oidc stack
$scriptsPath = Resolve-Path "$PSScriptRoot\..\scripts"
& "$scriptsPath\deploy-template.ps1" `
    -awsProfile $awsProfile `
    -region $region `
    -templateFile "$PSScriptRoot/github-oidc.yaml" `
    -stackName "github-oidc" `
    -tags $([pscustomobject]@{ owner = $owner; product = $product })