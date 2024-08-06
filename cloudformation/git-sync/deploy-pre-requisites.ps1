param (
    [String]
    $awsProfile = "",
    [String]
    $region = "eu-west-1"
)

write-output "Deploying git-sync pre-requisites..."
$scriptsPath = Resolve-Path "$PSScriptRoot\..\..\deployment-scripts"
& "$scriptsPath\deploy-template.ps1" -awsProfile $awsProfile -region $region -templateFile "$PSScriptRoot/pre-requisites.yaml" -stackName "git-sync-pre-requisites"