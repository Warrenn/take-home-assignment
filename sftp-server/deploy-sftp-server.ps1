param (
    [String]
    $awsProfile = "",
    [String]
    $region = "eu-west-1"
)

write-output "Deploying SFTP Server..."
$scriptsPath = Resolve-Path "$PSScriptRoot\..\..\deployment-scripts"
& "$scriptsPath\deploy-template.ps1" -awsProfile $awsProfile -region $region -templateFile "$PSScriptRoot/sftp-server.yaml" -stackName "sftp-server"