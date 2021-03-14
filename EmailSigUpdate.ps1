#BambooHR Email Signature Information Update
#Script by Dominik Feiler
#11.03.2021
#Get API Access to BambooHR, Generate Custom Report to get all Fields to be loaded into Active Directory for Email Signatures

# BambooHR API Key, to be passed into the script as Parameter
# API Key obtained from https://feisst.bamboohr.com/settings/permissions/api.php?id=2795
param(
    [Parameter(Mandatory=$true,Position=0)]
    [string]
    $BambooHRAPIKey
)

#Script Execution Logging
$LogFilePath = "C:\Users\Administrator\Documents\Automated Execution Script\AD Profile BambooHR Update\Log.log"

Start-Transcript -Path $LogFilePath -Append

#$BambooHRAPIKey = "3c23d700a85f970e168c74f61ac023cf2dc96c76"

Write-Host $BambooHRAPIKey
$BambooHRAPIKeyBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($BambooHRAPIKey+":x"))

#BambooHR API Endpoints
$BambooHRCustomReport = "https://feisst.bamboohr.com/api/gateway.php/feisst/v1/reports/custom?format=csv"


#Generate Body to request correct fields from BambooHR
$BambooHRReportFields = @{
    title = "Feist Group Email Signature Information"
    fields = "id","workEmail","preferredName","firstname","lastname","mobilePhone","workPhonePlusExtension","jobTitle","division","department","supervisorEmail"
} | ConvertTo-Json

#Query BambooHR for custom fields, as CSV
$BambooHRCSVReport = Invoke-WebRequest -Headers @{"Authorization" = "Basic $BambooHRAPIKeyBase64"} -Method POST -ContentType "application/json" -Uri $BambooHRCustomReport -Body $BambooHRReportFields

#Convert Bamboo Response to Tabular Data
$CSV = ConvertFrom-Csv $BambooHRCSVReport.Content

#Go through CSV file row by row
foreach ($row in $CSV) {
    #Skip rows without Work Email
    if(($null -eq $row.'Work Email') -or ("" -eq $row.'Work Email')){ 
        Write-Host "Skipping $($row.'First Name') $($row.'Last Name') as they don't have an Email address set in BambooHR"
        continue 
    }

    $ADUser = Get-ADUser -Filter "UserPrincipalName -eq '$($row.'Work Email')'" -ErrorAction SilentlyContinue
    
    #Skip if no matching ADUser can be found
    if($null -eq $ADUser){ 
        Write-Host "Skipping $($row.'First Name') $($row.'Last Name') ($($row.'Work Email')) as they dont have a matching AD User"
        continue
    }

    Write-Host "Working with $ADUser"
    Write-Host "Available details: $row"


    #Below, Set-ADUser breaks if you try to set e.g. an empty string as a phone number
    #Check if e.g. phone number exists in CSV-file. If not, set $null rather than ""
    Set-ADUser -Identity $ADUser `
        -GivenName $(if($row.'Preferred Name' -ne "") {$row.'Preferred Name'} else {$row.'First Name'} ) `
        -Surname $row.'Last Name' `
        -MobilePhone $(if($row.'Mobile Phone' -ne "" ) { $row.'Mobile Phone' } else { $null } ) `
        -OfficePhone $(if($row.'Work phone + ext.' -ne "" ) { $row.'Work phone + ext.' } else { $null } ) `
        -Title $(if($row.'Job Title' -ne "" ) { $row.'Job Title' } else { $null } ) `
        -Company $(if($row.Division -ne "" ) { $row.Division } else { $null } ) `
        -Department $(if($row.Department -ne "" ) { $row.Department } else { $null } )


    #Try to set User's Manager / Supervisor
    if($row.'Manager''s email' -ne ""){
        $Manager = Get-ADUser -Filter "UserPrincipalName -eq '$($row.'Manager''s email')'" -ErrorAction SilentlyContinue
        if($null -eq $Manager){
            Write-Host "Unable to find Manager ($($row.'Manager''s email'))"
        }else{
            Set-ADUser -Identity $ADUser -Manager $Manager
        }
    }else{
        Write-Host "User doesn't have a manager"
    }

    #Try to get the photo from BambooHR and set into Active Directory
    $BambooHRUserID = $row.EEID
    try{
        $BambooHRUserPhoto = "https://api.bamboohr.com/api/gateway.php/feisst/v1/employees/"+$BambooHRUserID+"/photo/medium"
        $PhotoResponse = Invoke-WebRequest -Headers @{"Authorization" = "Basic $BambooHRAPIKeyBase64"} -Method GET -ContentType "image/jpeg" -Uri $BambooHRUserPhoto
        Set-ADUser -Identity $ADUser -Replace @{thumbnailPhoto = $PhotoResponse.Content}

    }catch{
        Write-Host "Unable to Get or Set User image"
    }

    Write-Host "Set all available details for $($row.'Work Email')"
}

Stop-Transcript