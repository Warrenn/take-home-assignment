param (
    [String]
    $awsProfile = "",
    [String]
    $region = "eu-west-1"
)

write-output "Deploying code pipeline ..."

$deploymentConfig = Get-Content $(Resolve-Path "$PSScriptRoot\..\code-pipeline-stack-deployment.json") | ConvertFrom-Json

$scriptsPath = Resolve-Path "$PSScriptRoot\..\deployment-scripts"
& "$scriptsPath\deploy-template.ps1" `
    -awsProfile $awsProfile `
    -region $region `
    -templateFile "$PSScriptRoot/code-pipeline.yaml" `
    -stackName "code-pipeline" `
    -tags $deploymentConfig.tags `
    -overrides $deploymentConfig.parameters