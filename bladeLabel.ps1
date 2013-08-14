#This script will go through each UCS Blade, identify the Service Profile associated and Label the blade to match the name of the Service Profile
Import-Module CiscoUcsPS
#Connect to UCS Infrastructure
$UCS = Read-Host "Please type the fqdn or IP of the UCS you would like to label"
$UCSuser = Read-Host "Please enter your username"
$UCSPassword = Read-Host -AsSecureString "Password"

Connect-Ucs -Name $UCS $cred

#Populate Blade info to be labled
$BladeList=Get-UcsBlade

foreach ($Blade in $BladeList)
{
$Label=$Blade.AssignedToDn
$Device=$Blade.serverid
Set-UcsBlade -Blade $Device -UsrLbl $Label -Force
}
Get-UcsBlade | ft ServerID,UsrLbl