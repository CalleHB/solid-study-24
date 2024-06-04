
#######################
#Parameter för att välja OU att söka i och vart mappar ska skapas.
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $oupath,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $folderpath
)
#######################
#Parameter för att hämta en en användare manager i flera led till topp managern.
Function Get-ManagerChain {
    param (
        [string]$userName
    )

    $UserObj = Get-ADUser -Identity $user -Properties Manager
    $ManagerChain = @()

    while ($UserObj.Manager) {
        if ([string]::IsNullOrEmpty($UserObj.Manager)) {
            Write-Warning "Manager for user $UserName does not exist."
            break
        }
    
        try {
            $Manager = Get-ADUser -Identity $UserObj.Manager -Properties DisplayName, Manager
            if ($null -eq $Manager) {
                Write-Warning "Manager with identity $($UserObj.Manager) not found."
                break
            }
            $ManagerChain += $Manager.DisplayName
            $UserObj = $Manager
        } catch {
            Write-Error "Failed to get manager for user $UserName"
            break
        }
    }

    return $ManagerChain
}


#Här skapar jag utefter att användaren har skrivit in sin folderpath tidigare en logfolder i samma mapp. Sparar en Log för förändringar i scriptet och en för uppdaterandet av AD
$logsfolder = "$folderpath\Logs\"
$logFileName = "Folderlogs-" + (Get-Date -Format "yyyy-MM") + ".txt"
$logFilePath = "$logsfolder$logFileName"
$userFileName = "Folderlogs-Users" + (Get-Date -Format "yyyy-MM")
$userlogs = "$logsfolder$userFileName"

#Hämtar alla användare som finns i det OU som användaren sökte efter, finns inte detta 
$OU = Get-ADOrganizationalUnit -Filter "Name -eq '$oupath'" -Properties DistinguishedName
if ($null -eq $OU) {
    Write-Host "OU:n '$oupath' hittades inte."
    return   
}

#Testar om folders och logg finns eller inte, annars skapas detta.
if (-not (Test-Path $folderpath)) {
    try {
        New-Item -Path $folderpath -ItemType Directory -Force
    } catch {
        Write-Error "Failed to create directory at $folderpath $($_.Exception.Message)"
        return
    }
}
if (-not (Test-Path $logsfolder)) {
    try {
        New-Item -Path $logsfolder -ItemType Directory -Force
    } catch {
        Write-Error "Failed to create logs at $logsfolder $($_.Exception.Message)"
        return
    }
}

$users = Get-ADUser -SearchBase $OU.DistinguishedName -Filter * -Properties Manager
$users | Export-Csv -Path $userlogs -NoTypeInformation -Force
$previousUsers = Import-Csv -Path $userlogs

# Tar bort rättighter på Rootmappen som skapas för att inga andra tex, Users ska få rättighter i denna mappen.
Disable-NTFSAccessInheritance -Path $folderpath
Clear-NTFSAccess -Path $folderpath
$accounts = "Administrators", "SYSTEM", "CREATOR OWNER"
Add-NTFSAccess -Path $folderpath -Account $accounts -AccessRights FullControl

$users = Get-ADUser -SearchBase $OU.DistinguishedName -Filter * -Properties Manager

# Loopa igenom varje användare som finns i variablen $users
foreach ($user in $users) {
    # Sparar datum och tid för att använda i till våran loggfil.
    
    $toc = Get-Date -Format "yyyy-MM-dd HH.mm.ss"

    $username = $user.SamAccountName
    $managerChain = Get-ManagerChain -UserName $user.Manager

    #Sätter ihop vägen till användarens mapp med rootsökvägen och användarens namn som mappen som ska skapas
    $userPath = Join-Path -Path $folderpath -ChildPath $username
    #sparar användarens managers name i en variable för att kunna tilldela dem rättigheter på mappar. "CN=|,.*" används för att spara endas namnet
    $managername = $user.Manager -replace "CN=|,.*"

    # Loggar händelsen till loggfilen när vi börjar med att försöka skapa mappen
    Add-Content -Path $logFilePath -Value "[$toc]"
    Add-Content -Path $logFilePath -Value "[$toc] -----------SCRIPT STARTED FOR $username------------"
    Add-Content -Path $logFilePath -Value "[$toc]"

    #Scriptet spartar med att koll om mappen redan finns eller inte, vi lägger den i en try för att undvida en krash av scriptet
    try {
        Add-NTFSAccess -Path $folderpath -Account $username -AccessRights ReadAndExecute -AccessType Allow -AppliesTo ThisFolderOnly
        # Om användarmappen inte redan finns, skapa den
        if (-not (Test-Path $userPath)) {
            New-Item -Path $userPath -ItemType Directory -Force
            Add-Content -Path $logFilePath -Value "[$toc] Folder created for user: $username"
            # Tilldelar rättighter för mappen till kontorna som ska ha behörighet och rätt behörigter till dessa användare.
            Add-NTFSAccess -Path $userPath -Account $username -AccessRights Read,Write -AccessType Allow -AppliesTo ThisFolderSubfoldersAndFiles
            Add-Content -Path $logFilePath -Value "[$toc] Access granted to: $username, $managerChain."
            # Om användare har en manager så läggs denna också till med rättighter, annars skriv ett meddeland till loggfilen med info om detta.
            if ($managername) {
                Add-NTFSAccess -Path $userPath -Account $ManagerChain -AccessRights Read,Write -AccessType Allow -AppliesTo ThisFolderSubfoldersAndFiles
                Add-Content -Path $logFilePath -Value "[$toc] Access granted to Managers: $managerChain."
            }
            else {
                Add-Content -Path $logFilePath -Value "[$toc] User $username dose not have a manager"
            }

        }
        # Om mappen redan finns, kontrollera om det har gjorts ändringar från AD
# Om mappen redan finns, kontrollera om det har gjorts ändringar från AD

        elseif (Test-Path $userPath) {
    
            $previousUser = $previousUsers | Where-Object { $_.SamAccountName -eq $user.SamAccountName }

            #Om användaren inte finns i den tidigare CSV filen eller om deras manager har ändrats
            if (-not $previousUser -or $previousUser.Manager -ne $user.Manager) {
                # Rensa som gammla tillåtna användarna och sätt nya utefter att AD strukturen har förändrats
                Clear-NTFSAccess $userPath
                Add-NTFSAccess -Path $userPath -Account $username -AccessRights Read,Write -AccessType Allow -AppliesTo ThisFolderSubfoldersAndFiles
                Add-Content -Path $logFilePath -Value "[$toc] Access granted to: $username"
                #Har användaren en manager så sätt även rättighter på mappen, i flera led uppåt
                if ($managername) {
                    Add-NTFSAccess -Path $userPath -Account $managerChain -AccessRights Read,Write -AccessType Allow -AppliesTo ThisFolderSubfoldersAndFiles
                    Add-Content -Path $logFilePath -Value "[$toc] Access granted to: $managerChain."
                }

                # Uppdaterar den nya CSV filen med den nya infon från AD så vi ifall det förrändras varje gång
                if ($previousUser) {
                    $previousUser.Manager = $managerChain
                    $previousUsers | Export-Csv -Path $userlogs -NoTypeInformation -Force
                }

            # Log the changes
                Add-Content -Path $logFilePath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH.mm.ss')] Folder permissions updated for user: $username"
            } else {
                Add-Content -Path $logFilePath -Value "[$toc] Nothing has changed for this user"
            }
            #Skriver in att loggningen av skapandet av mappen har slutat.
            Add-Content -Path $logFilePath -Value "[$toc]"
            Add-Content -Path $logFilePath -Value "[$toc] -----------SCRIPT STOPPED FOR $Username------------"
            Add-Content -Path $logFilePath -Value "[$toc]"
        }
            #Om det blir något fel med skrivtet så kommer denna cathe att fånga upp detta och skriva ut det i våran fil under ett eget fäl
            catch {
                 Add-Content -Path $logFilePath -Value "-----------Error message started------------"
                $errorMessage = $_.Exception.Message
                Add-Content -Path $logFilePath -Value "Error running script for user $username : $errorMessage"
                Add-Content -Path $logFilePath -Value "-----------Error message ended------------"
            }
            finally {
                 Add-Content -Path $logFilePath -Value "-----------SCRIPT STOPPED FOR $Username------------"
            }
        }
        catch {
            Add-Content -Path $logFilePath -Value "---SCRIPT STOPPED---"
        }
    }
