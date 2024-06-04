Import-Module ActiveDirectory

$CurrentDate = Get-Date

#Get what day was 60 days ago.
$InactiveDate = $CurrentDate.AddDays(-60)

Write-Host "Inaktivitetsdatum: $InactiveDate"

#Search in AD to get users that have been inactiv for more then 60 days.
$InactiveUsers = Get-ADUser -Filter {LastLogonDate -lt $InactiveDate} -Properties Comment, MemberOf

#filter out all users that are a member of administrators
$InactiveUsersAdmin = $InactiveUsers | Where-Object { $_.MemberOf -notcontains "CN=Administrators,CN=Builtin,DC=domain,DC=com" }

# foreach user that is not a administrator and have been inactiv for more then 60 days. we delete.
foreach ($user in $InactiveUsersAdmin) {
    Remove-ADUser -Identity $user.SamAccountName -Confirm:$false
    Write-Host "Användare $($user.SamAccountName) är nu borttagen på grund av inaktivitet"
}
