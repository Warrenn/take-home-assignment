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

# validate that the agency name is valid
if ($agencyName -notmatch "^[a-zA-Z0-9-]+$") {
    throw "Agency name must be alphanumeric and cannot contain hyphens"
}

# using cloudformation check if a stack with the name exists in the region
$exports = [string]::Join("", $(aws cloudformation list-exports `
            --profile $awsProfile `
            --region $region `
            --query "Exports[*]" `
            --output json)) | ConvertFrom-Json

$exportsWithName = $($exports | Where-Object { $_.Name -eq "$agencyName-sftp-user-name" })
if ($exportsWithName.Count -gt 0) {
    throw "Agency $agencyName already onboarded in region $region"
}

$sftpExports = $($exports | Where-Object { $_.Name -eq "sftp-server-endpoint" })

if ($sftpExports.Count -eq 0) {
    $scriptsPath = Resolve-Path "$PSScriptRoot\..\sftp-server"
    & "$scriptsPath\deploy-sftp-server.ps1" `
        -awsProfile $awsProfile `
        -region $region
}

$workflowYamlContent = Get-Content $(Resolve-Path "$PSScriptRoot\..\.github\workflows\update-stacks.yml")
$owner = $($workflowYamlContent -match "^.*OWNER.*:.*").Split(":")[1].Trim().Trim("""") 
$product = $($workflowYamlContent -match "^.*PRODUCT.*:.*").Split(":")[1].Trim().Trim("""")
$passPhrase = [guid]::NewGuid().ToString()

# using aws cli parameter store to check if the sftp user has a public key
$sftpPublicCertificate = $(aws ssm get-parameter `
        --name "$product/sftp-public-key/$agencyName" `
        --with-decryption `
        --region $region `
        --profile $awsProfile `
        --query "Parameter.Value" `
        --output text)

if ([string]::IsNullOrEmpty($sftpPublicCertificate)) {

    write-output "No public key found for agency $agencyName, generating new key..."

    # using powershell check if a file exists
    if (Test-Path -Path "$agencyName-sftp-key.pem") {
        Remove-Item -Path "$agencyName-sftp-key.pem"
    }

    if (Test-Path -Path "$agencyName-sftp-key") {
        Remove-Item -Path "$agencyName-sftp-key"
    }


    ssh-keygen -t rsa -b 2048 -f "$agencyName-sftp-key"  -N "$passPhrase"

    $sftpPublicCertificate = Get-Content "$agencyName-sftp-key.pub" -Encoding ascii
    $sftpPrivateCertificate = Get-Content "$agencyName-sftp-key" -Encoding ascii

    $tagsString = "[{""Key"":""owner"",""Value"":""$owner""},{""Key"":""product"",""Value"":""$product""},{""Key"":""agency"",""Value"":""$agencyName""}]"

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
}
else {
    # read the private key from ssm
    $sftpPrivateCertificate = $(aws ssm get-parameter `
            --name "/$product/sftp-private-key/$agencyName" `
            --with-decryption `
            --region $region `
            --profile $awsProfile `
            --query "Parameter.Value" `
            --output text)
    
    # read the pass phrase from ssm
    $passPhrase = $(aws ssm get-parameter `
            --name "/$product/sftp-pass-phrase/$agencyName" `
            --with-decryption `
            --region $region `
            --profile $awsProfile `
            --query "Parameter.Value" `
            --output text)

    # write the content of the public key to a file
    $sftpPublicCertificate | Out-File "$agencyName-sftp-key.pub" -Encoding ascii

    # write the content of the private key to a file
    $sftpPrivateCertificate | Out-File "$agencyName-sftp-key" -Encoding ascii
}


write-output "Onboarding agency $agencyName..."

# get the sha512 hash of the template file
$agencyTemplateSha512 = (Get-FileHash -Path "$PSScriptRoot/agency.yaml" -Algorithm SHA512 | Select-Object -ExpandProperty Hash).ToLower()

# using deploy-template.ps1 script to deploy the agency user stack
$scriptsPath = Resolve-Path "$PSScriptRoot\..\scripts"
& "$scriptsPath\deploy-template.ps1" `
    -awsProfile $awsProfile `
    -region $region `
    -templateFile "$PSScriptRoot/agency.yaml" `
    -stackName "$agencyName-agency" `
    -overrides $([pscustomobject]@{ AgencyName = $agencyName; PublicKey = $sftpPublicCertificate }) `
    -tags $([pscustomobject]@{ owner = $owner; product = $product; sha512 = $agencyTemplateSha512; agency = $agencyName })

write-output "Onboarding agency $agencyName complete..."
write-output "Agency $agencyName public key file: $agencyName-sftp-key.pub"
write-output "Agency $agencyName private key file: $agencyName-sftp-key"
write-output "Agency $agencyName pass phrase: $passPhrase"