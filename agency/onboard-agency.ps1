param (
    [String]
    $awsProfile = "",
    [String]
    [Parameter(Mandatory = $true)]
    $region,
    [String]
    [Parameter(Mandatory = $true)]
    $agencyName,
    [ValidateSet("daily", "weekly")]
    [String]
    $monitoringFrequency = "daily"
)

if ([string]::IsNullOrEmpty($awsProfile)) {
    $awsProfile = $Env:AWS_PROFILE
}

if ([string]::IsNullOrEmpty($awsProfile)) {
    $awsProfile = "default"
}

# validate that the agency name is valid
if ($agencyName -notmatch "^[a-zA-Z0-9-]+$" -or $agencyName.Length -gt 100) {
    throw "Agency name must be only alphanumeric with hyphens and less than 100 characters"
}

# get a list of the cloudformation exports in the region
$exports = [string]::Join("", $(aws cloudformation list-exports `
            --profile $awsProfile `
            --region $region `
            --query "Exports[*]" `
            --output json)) | ConvertFrom-Json

# check if the agency stack for the agency name exists in the region if so throw an error
$exportsWithName = $($exports | Where-Object { $_.Name -eq "$agencyName-sftp-user-name" })
if ($exportsWithName.Count -gt 0) {
    throw "Agency $agencyName already onboarded in region $region"
}

# check if the sftp server stack exists in the region if not deploy it
$sftpExports = $($exports | Where-Object { $_.Name -eq "sftp-server-endpoint" })
if ($sftpExports.Count -eq 0) {
    $scriptsPath = Resolve-Path "$PSScriptRoot\..\sftp-server"
    & "$scriptsPath\deploy-sftp-server.ps1" `
        -awsProfile $awsProfile `
        -region $region
}

# get the owner and product tags from the workflow file
$workflowYamlContent = Get-Content $(Resolve-Path "$PSScriptRoot\..\.github\workflows\update-stacks.yml")
$owner = $($workflowYamlContent -match "^.*OWNER.*:.*").Split(":")[1].Trim().Trim("""") 
$product = $($workflowYamlContent -match "^.*PRODUCT.*:.*").Split(":")[1].Trim().Trim("""")
$passPhrase = [guid]::NewGuid().ToString()

write-output "Generating new key for agency $agencyName..."

# check if a local public key file exists and delete it if it does
if (Test-Path -Path "$agencyName-sftp-key.pub") {
    Remove-Item -Path "$agencyName-sftp-key.pub"
}

# check if a local private key file exists and delete it if it does
if (Test-Path -Path "$agencyName-sftp-key") {
    Remove-Item -Path "$agencyName-sftp-key"
}

# generate a new key pair
ssh-keygen -t rsa -b 2048 -f "$agencyName-sftp-key"  -N "$passPhrase"

# get the public and private key contents
$sftpPublicCertificate = Get-Content "$agencyName-sftp-key.pub" -Encoding ascii
$sftpPrivateCertificate = Get-Content "$agencyName-sftp-key" -Encoding ascii

$tagsString = "[{""Key"":""owner"",""Value"":""$owner""},{""Key"":""product"",""Value"":""$product""},{""Key"":""agency"",""Value"":""$agencyName""}]"

# write the passphrase, public and private key to ssm parameters for the agency
aws ssm put-parameter `
    --name "/$product/sftp-public-key/$agencyName" `
    --type "SecureString" `
    --value "$($sftpPublicCertificate)" `
    --overwrite `
    --region $region `
    --profile $awsProfile

aws ssm put-parameter `
    --name "/$product/sftp-private-key/$agencyName" `
    --type "SecureString" `
    --value "$($sftpPrivateCertificate)" `
    --overwrite `
    --region $region `
    --profile $awsProfile

aws ssm put-parameter `
    --name "/$product/sftp-pass-phrase/$agencyName" `
    --type "SecureString" `
    --value "$($passPhrase)" `
    --overwrite `
    --region $region `
    --profile $awsProfile

# add the tags to the parameters
aws ssm add-tags-to-resource `
    --resource-type "Parameter" `
    --resource-id "/$product/sftp-private-key/$agencyName" `
    --tags $tagsString `
    --region $region `
    --profile $awsProfile
    
aws ssm add-tags-to-resource `
    --resource-type "Parameter" `
    --resource-id "/$product/sftp-public-key/$agencyName" `
    --tags $tagsString `
    --region $region `
    --profile $awsProfile
    
aws ssm add-tags-to-resource `
    --resource-type "Parameter" `
    --resource-id "/$product/sftp-pass-phrase/$agencyName" `
    --tags $tagsString `
    --region $region `
    --profile $awsProfile

write-output "Onboarding agency $agencyName..."

# using deploy-template.ps1 script deploy the agency user stack
$scriptsPath = Resolve-Path "$PSScriptRoot\..\scripts"
& "$scriptsPath\deploy-template.ps1" `
    -awsProfile $awsProfile `
    -region $region `
    -templateFile "$PSScriptRoot/agency.yaml" `
    -stackName "$agencyName-agency" `
    -overrides $([pscustomobject]@{ AgencyName = $agencyName; PublicKey = $sftpPublicCertificate; MonitoringFrequency = $monitoringFrequency }) `
    -tags $([pscustomobject]@{ owner = $owner; product = $product; agency = $agencyName; frequency = $monitoringFrequency })

write-output "Onboarding agency $agencyName complete..."
write-output "Agency $agencyName public key file: $agencyName-sftp-key.pub"
write-output "Agency $agencyName private key file: $agencyName-sftp-key"
write-output "Agency $agencyName pass phrase: $passPhrase"