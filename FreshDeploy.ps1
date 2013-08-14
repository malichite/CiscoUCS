#Deploy UCS from scratch
#***WARNING***
#This will delete all configs, pools, service profiles.....
#Updated 8/14/13
#Ryan LaPointe

import-module CiscoUcsPS

$ucsm = read-host "Enter the UCSM IP or Hostname"
Connect-UCS -Name $ucsm

#Gather Variables for config
$ucsSite = Read-Host "Enter UCS Site"
$ucsBlock = Read-Host "Enter UCS Block"
$ucsID = $ucsSite+$ucsBlock
$mac="20:10:20:$ucsID"
$macA1=$mac+":A0:00"
$macA2=$mac+":A3:E7"
$macB1=$mac+":B0:00"
$macB2=$mac+":B3:E7"
$wwn="20:00:00:25:B5:$ucsID"
$wwn1=$wwn+":F0:00"
$wwn2=$wwn+":F3:E7"
$wwpnA1=$wwn+":A0:00"
$wwpnA2=$wwn+":A3:E7"
$wwpnB1=$wwn+":B0:00"
$wwpnB2=$wwn+":B3:E7"
$uuid="00$ucsID"
$uuida=$uuid+"-000000000000"
$uuidb=$uuid+"-0000000003E7"
$vsanA = Read-Host "Enter vSAN for Fabric A"
$vsanB = Read-Host "Enter vSAN for Fabric B"
$TotalHosts = Read-Host "Enter number of Service Profiles to deploy"

#Cleanup any unneeded stuffs
Get-UcsServerPool | Remove-UcsServerPool -Force
Get-UcsVnicTemplate | Remove-UcsVnicTemplate -Force
Get-UcsMacPool | Remove-UcsMacPool -Force
Get-UcsIpPool | Where-Object {$_.name -ne "ext-mgmt"} | Remove-UcsIpPool -Force
Get-UcsServiceProfile | Remove-UcsServiceProfile -Force
Get-UcsLdapProvider | Remove-UcsLdapProvider -Force
Get-UcsProviderGroup | Remove-UcsProviderGroup -Force
Get-UcsLanCloud | Get-UcsVlan | Where-Object {$_.name -ne "default"} | Remove-UcsVlan -Force
Get-UcsVhbaTemplate | Remove-UcsVhbaTemplate -Force
Get-UcsPowerPolicy | Remove-UcsPowerPolicy -Force
Get-UcsMaintenancePolicy | Where-Object {$_.name -ne "default"} | Remove-UcsMaintenancePolicy -Force
Get-UcsLocalDiskConfigPolicy | Remove-UcsLocalDiskConfigPolicy -Force
Get-UcsBootPolicy | Remove-UcsBootPolicy -Force
Get-UcsBiosPolicy | Remove-UcsBiosPolicy -Force
Get-UcsQosPolicy | Remove-UcsQosPolicy -Force
Get-UcsUuidSuffixPool | Remove-UcsUuidSuffixPool -Force
Get-UcsOrg | Where-Object {$_.Name -ne "root"} | Remove-UcsOrg -Force

# Set NTP Server(s)
Get-UcsNtpServer | Remove-UcsNtpServer -Force
Add-UcsNtpServer ntp.server.com
Set-UcsTimezone -Timezone "Europe/London" -Force
# Add AD Auth
Add-UcsLdapProvider -Name ldap.domain.local -Rootdn "DC=domain,DC=local" -Basedn "OU=Corp Service Accounts,OU=Corp,DC=domain,DC=local" -filter 'sAMAccountName=$userid' -XtraProperty @{Vendor="MS-AD"}
Get-UcsLdapProvider ldap.domain.local | Add-UcsLdapGroupRule -TargetAttr memberOf -Authorization enable -Traversal recursive
Get-UcsLdapGlobalConfig | Add-UcsProviderGroup -Name ldapGroup
Get-UcsProviderGroup -Name ldapGroup | Add-UcsProviderReference -name "ldap.domain.local"
Invoke-UcsXml -XmlQuery "<configConfMo inHierarchical='false'><inConfig><aaaLdapGroup name='CN=GROUP,OU=OU,DC=domain,DC=local' ><aaaUserRole name='admin' /></aaaLdapGroup></inConfig></configConfMo>"

#################
###SNMP Config###
#################

$mo = Get-UcsSvcEp -Descr "" -PolicyOwner "local"
Start-UcsTransaction
$mo_1 = Get-UcsSnmp | Set-UcsSnmp -AdminState "enabled" -Community "SNMPString" -Descr "SNMP Service" -PolicyOwner "local" -SysContact "" -SysLocation "" -XtraProperty @{IsSetSnmpSecure="no"; }
Complete-UcsTransaction

####################
###Network Config###
####################
# Set Up Mac Pools
add-ucsmacpool -name Fabric_A -AssignmentOrder sequential
add-ucsmacpool -name Fabric_B -AssignmentOrder sequential
add-ucsmacmemberblock -Macpool Fabric_A -From $macA1 -To $macA2
add-ucsmacmemberblock -Macpool Fabric_B -From $macB1 -To $macB2

#Set up VLANS
$lc=(get-ucslancloud)
$lc | add-ucsVLAN -Name vlan10 -Id 10
$lc | add-ucsVLAN -Name vlan11 -Id 11
$lc | add-ucsVLAN -Name vlan12 -Id 12
$lc | add-ucsVLAN -Name vlan13 -Id 13
$lc | add-ucsVLAN -Name vlan14 -Id 14
$lc | add-ucsVLAN -Name vlan15 -Id 15

#Get-UcsVnicTemplate | Remove-UcsVnicTemplate -force
Add-UcsVnicTemplate -Name ESX_A_MGMT -SwitchId A -TemplType updating-template -identpoolname Fabric_A -qospolicyname Gold
Add-UcsVnicTemplate -Name ESX_A_VM -SwitchId A -TemplType updating-template -identpoolname Fabric_A -qospolicyname Gold
Add-UcsVnicTemplate -Name ESX_B_MGMT -SwitchId B -TemplType updating-template -identpoolname Fabric_B -qospolicyname Gold
Add-UcsVnicTemplate -Name ESX_B_VM -SwitchId B -TemplType updating-template -identpoolname Fabric_B -qospolicyname Gold

$vlans = Get-UcsVlan
$vnict = Get-UcsVnicTemplate
foreach ($vnic in $vnict){
    $template = $vnic.Name
    foreach ($vlan in $vlans){
    Add-UcsVnicInterface -Name $vlan.Name -vnictemplate $template
    }
    }



# Set Up WWN Pools
get-ucsWWNPool | Remove-UcsWwnPool -Force
add-ucsWWNPool -name WWNPool -purpose node-wwn-assignment -AssignmentOrder sequential
add-ucswwnmemberblock -WWNPool WWNPool -From $wwn1 -To $wwn2

# Set UP WWPN Pools
add-ucsWWNPool -name Fabric_A -purpose port-wwn-assignment -AssignmentOrder sequential
add-ucsWWNPool -name Fabric_B -purpose port-wwn-assignment -AssignmentOrder sequential
add-ucswwnmemberblock -WWNPool Fabric_A -From $wwpnA1 -To $wwpnA2
add-ucswwnmemberblock -WWNPool Fabric_B -From $wwpnB1 -To $wwpnB2

#Setup UUID Pool
Add-UcsUuidSuffixPool -Name default -AssignmentOrder sequential
Add-UcsUuidSuffixBlock -UuidSuffixPool default -From $uuida -To $uuidb

#Add Policies
$power_policy = Add-UcsPowerPolicy -Name NoCap -Prio no-cap -PolicyOwner local
$maint_policy = Add-UcsMaintenancePolicy -Name UserPrompt -Descr "UserAck for changes" -UptimeDisr user-ack
Add-UcsLocalDiskConfigPolicy -Name default -Mode any-configuration -ProtectConfig yes

Start-UcsTransaction
    $BootPolicy = Get-UcsOrg -Level root  | Add-UcsBootPolicy -Descr "ESXi_Default" -EnforceVnicName "no" -Name "ESXi_Default" -RebootOnUpdate "no"
    $BootCD = $BootPolicy | Add-UcsLsbootVirtualMedia  -order 1 -Access read-only
    $BootStorage = $BootPolicy | Add-UcsLsbootStorage -ModifyPresent -Order "2"
    $BootSanImage = $BootStorage | Add-UcsLsbootSanImage -Type "primary" -VnicName "A"
    $BootSanImage | Add-UcsLsbootSanImagePath -Lun 0 -Type "primary" -Wwn "50:06:01:6C:00:00:35:BD"
    $BootSanImage = $BootStorage | Add-UcsLsbootSanImage -Type "secondary" -VnicName "B"
    $BootSanImage | Add-UcsLsbootSanImagePath -Lun 0 -Type "primary" -Wwn "50:06:01:64:00:00:35:BD"
Complete-UcsTransaction

###################
###BIOS Policies###
###################

$bios_policy = Add-UcsBiosPolicy -name test
Set-UcsBiosNUMA -BiosPolicy test -VpNUMAOptimized enabled -Force
Set-UcsBiosLvDdrMode -BiosPolicy test -VpLvDDRMode "performance-mode" -Force
Set-UcsBiosVfSelectMemoryRASConfiguration -BiosPolicy test -VpSelectMemoryRASConfiguration "maximum-performance" -force
Set-UcsBiosTurboBoost -BiosPolicy test -VpIntelTurboBoostTech enabled -Force
Set-UcsBiosEnhancedIntelSpeedStep -BiosPolicy test -VpEnhancedIntelSpeedStepTech enabled -Force
Set-UcsBiosHyperThreading -BiosPolicy test -VpIntelHyperThreadingTech enabled -Force
Set-UcsBiosVfCoreMultiProcessing -BiosPolicy test -VpCoreMultiProcessing all -Force
Set-UcsBiosExecuteDisabledBit -BiosPolicy test -VpExecuteDisableBit enabled -Force
Set-UcsBiosVfIntelVirtualizationTechnology -BiosPolicy test -VpIntelVirtualizationTechnology enabled -force
Set-UcsBiosVfProcessorC1E -BiosPolicy test -VpProcessorC1E disabled -Force
Set-UcsBiosVfProcessorC3Report -BiosPolicy test -VpProcessorC3Report disabled -Force
Set-UcsBiosVfProcessorC6Report -BiosPolicy test -VpProcessorC6Report disabled -Force
Set-UcsBiosVfCPUPerformance -BiosPolicy test -VpCPUPerformance enterprise -Force
Set-UcsBiosIntelDirectedIO -BiosPolicy test -VpIntelVTForDirectedIO enabled -Force    
Set-UcsBiosVfSerialPortAEnable -BiosPolicy test -VpSerialPortAEnable disabled -Force


#Set Up Local disk configuration policy

#add-UcsLocalDiskConfigPolicy -name LocalDisk-RAID1 -mode raid-mirrored -ProtectConfig no


#Set Up Boot Policy for Local Boot
#assign CD-ROM and Local Storage
#
$boot_policy = Add-UCSBootPolicy -Name LocalBoot -Rebootonupdate yes
$boot_policy | add-ucslsbootvirtualmedia -Order 1 -Access read-only
$boot_storage = $boot_policy | add-ucslsbootstorage -order 2
$boot_storage | add-ucslsbootlocalstorage

#Set Up Boot Policy for SAN Boot
#Assign CD-ROM and LUN on Target
#
#
$boot_policy = Add-UCSBootPolicy -Name SANBoot -Rebootonupdate yes
$boot_policy | add-ucslsbootvirtualmedia -Order 1 -Access read-only
$boot_storage = $boot_policy | add-ucslsbootstorage -order 2
$boot_storage | add-ucslsbootsanimage -vnicname Tier_1_Storage -type primary | add-ucslsbootsanimagepath -type primary -lun 0 -wwn 50:0a:09:81:88:8D:1B:65 

# Set up bios policy for boot to display boot scripting
add-ucsbiospolicy -Name Noiseyboot
Set-UcsBiosVfQuietBoot -BiosPolicy Noiseyboot -VpQuietBoot disabled -force

#Set up QOS policy
#still need to define policies.
add-ucsqospolicy -Name Gold
add-ucsqospolicy -Name Silver
add-ucsqospolicy -Name Bronze

#Set Up Vhba template and add vsans
#Get-UcsVhbaTemplate | Remove-UcsVhbaTemplate -force
Get-UcsFiSanCloud -Id "A" | Add-UcsVsan -FcZoneSharingMode "coalesce" -FcoeVlan $vsanA -Id $vsanA -Name $vsanA
Get-UcsFiSanCloud -Id "B" | Add-UcsVsan -FcZoneSharingMode "coalesce" -FcoeVlan $vsanB -Id $vsanB -Name $vsanB
$vhba_update_temp = Add-ucsvhbatemplate -Name ESX_A -SwitchID A -IdentPoolName Fabric_A -MaxDataFieldSize 2048 -TemplType updating-template
$vhba_update_temp | Add-UcsVhbaInterface -Name $vsanA
$vhba_update_temp = Add-ucsvhbatemplate -Name ESX_B -SwitchID B -IdentPoolName Fabric_B -MaxDataFieldSize 2048 -TemplType updating-template
$vhba_update_temp | Add-UcsVhbaInterface -Name $vsanB


Start-UcsTransaction
$mo = Get-UcsOrg -Level root  | Add-UcsServiceProfile -AgentPolicyName "" -BiosProfileName "Noiseyboot" -BootPolicyName "SANBoot" -Descr "" -DynamicConPolicyName "" -ExtIPPoolName "ext-amgmt" -ExtIPState "pooled" -HostFwPolicyName "" -IdentPoolName "default" -LocalDiskPolicyName "default" -MaintPolicyName "UserPrompt" -MgmtAccessPolicyName "" -MgmtFwPolicyName "" -Name "ESX" -PolicyOwner "local" -PowerPolicyName "NoCap" -ScrubPolicyName "" -SolPolicyName "" -SrcTemplName "" -StatsPolicyName "default" -Type "updating-template" -UsrLbl "" -Uuid "0" -VconProfileName ""
$mo_1 = $mo | Add-UcsLsVConAssign -ModifyPresent -AdminVcon "any" -Order "1" -Transport "ethernet" -VnicName "A_MGMT"
$mo_2 = $mo | Add-UcsLsVConAssign -ModifyPresent -AdminVcon "any" -Order "2" -Transport "ethernet" -VnicName "A_VM"
$mo_3 = $mo | Add-UcsLsVConAssign -ModifyPresent -AdminVcon "any" -Order "3" -Transport "ethernet" -VnicName "B_MGMT"
$mo_4 = $mo | Add-UcsLsVConAssign -ModifyPresent -AdminVcon "any" -Order "4" -Transport "ethernet" -VnicName "B_VM"
$mo_5 = $mo | Add-UcsLsVConAssign -ModifyPresent -AdminVcon "any" -Order "5" -Transport "fc" -VnicName "Fabric_A"
$mo_6 = $mo | Add-UcsLsVConAssign -ModifyPresent -AdminVcon "any" -Order "6" -Transport "fc" -VnicName "Fabric_B"
$mo_7 = $mo | Add-UcsVnic -AdaptorProfileName "VMWare" -Addr "derived" -AdminVcon "any" -IdentPoolName "" -Mtu 1500 -Name "A_MGMT" -NwCtrlPolicyName "" -NwTemplName "ESX_A_MGMT" -Order "1" -PinToGroupName "" -QosPolicyName "" -StatsPolicyName "default" -SwitchId "A"
$mo_8 = $mo | Add-UcsVnic -AdaptorProfileName "VMWare" -Addr "derived" -AdminVcon "any" -IdentPoolName "" -Mtu 1500 -Name "A_VM" -NwCtrlPolicyName "" -NwTemplName "ESX_A_VM" -Order "2" -PinToGroupName "" -QosPolicyName "" -StatsPolicyName "default" -SwitchId "A"
$mo_9 = $mo | Add-UcsVnic -AdaptorProfileName "VMWare" -Addr "derived" -AdminVcon "any" -IdentPoolName "" -Mtu 1500 -Name "B_MGMT" -NwCtrlPolicyName "" -NwTemplName "ESX_B_MGMT" -Order "3" -PinToGroupName "" -QosPolicyName "" -StatsPolicyName "default" -SwitchId "A"
$mo_10 = $mo | Add-UcsVnic -AdaptorProfileName "VMWare" -Addr "derived" -AdminVcon "any" -IdentPoolName "" -Mtu 1500 -Name "B_VM" -NwCtrlPolicyName "" -NwTemplName "ESX_B_VM" -Order "4" -PinToGroupName "" -QosPolicyName "" -StatsPolicyName "default" -SwitchId "A"
$mo_11 = $mo | Add-UcsVhba -AdaptorProfileName "VMWare" -Addr "derived" -AdminVcon "any" -IdentPoolName "" -MaxDataFieldSize 2048 -Name "Fabric_A" -NwTemplName "ESX_A" -Order "5" -PersBind "disabled" -PersBindClear "no" -PinToGroupName "" -QosPolicyName "" -StatsPolicyName "default" -SwitchId "A"
$mo_11_1 = $mo_11 | Add-UcsVhbaInterface -ModifyPresent -Name ""
$mo_12 = $mo | Add-UcsVhba -AdaptorProfileName "VMWare" -Addr "derived" -AdminVcon "any" -IdentPoolName "" -MaxDataFieldSize 2048 -Name "Fabric_B" -NwTemplName "ESX_B" -Order "6" -PersBind "disabled" -PersBindClear "no" -PinToGroupName "" -QosPolicyName "" -StatsPolicyName "default" -SwitchId "A"
$mo_12_1 = $mo_12 | Add-UcsVhbaInterface -ModifyPresent -Name ""
$mo_13 = $mo | Add-UcsVnicFcNode -ModifyPresent -Addr "pool-derived" -IdentPoolName "WWNPool"
$mo_14 = $mo | Set-UcsServerPower -State "admin-up" -Force
$mo_15 = $mo | Add-UcsFabricVCon -ModifyPresent -Fabric "NONE" -Id "1" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
$mo_16 = $mo | Add-UcsFabricVCon -ModifyPresent -Fabric "NONE" -Id "2" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
$mo_17 = $mo | Add-UcsFabricVCon -ModifyPresent -Fabric "NONE" -Id "3" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
$mo_18 = $mo | Add-UcsFabricVCon -ModifyPresent -Fabric "NONE" -Id "4" -InstType "auto" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
Complete-UcsTransaction


################################
###Fabric Interconnect Config###
###########################

Start-UcsTransaction
Get-UcsFiSanCloud -Id "A" | Add-UcsFcUplinkPort -ModifyPresent -AdminState "enabled" -PortId 16 -SlotId 2
Get-UcsFiSanCloud -Id "A" | Add-UcsFcUplinkPort -ModifyPresent -AdminState "enabled" -PortId 15 -SlotId 2
Get-UcsFiSanCloud -Id "A" | Add-UcsFcUplinkPort -ModifyPresent -AdminState "enabled" -PortId 14 -SlotId 2
Get-UcsFiSanCloud -Id "A" | Add-UcsFcUplinkPort -ModifyPresent -AdminState "enabled" -PortId 13 -SlotId 2
Get-UcsFiSanCloud -Id "A" | Add-UcsFcUplinkPort -ModifyPresent -AdminState "enabled" -PortId 12 -SlotId 2
Get-UcsFiSanCloud -Id "A" | Add-UcsFcUplinkPort -ModifyPresent -AdminState "enabled" -PortId 11 -SlotId 2
Get-UcsFiSanCloud -Id "A" | Add-UcsFcUplinkPort -ModifyPresent -AdminState "enabled" -PortId 10 -SlotId 2
Get-UcsFiSanCloud -Id "A" | Add-UcsFcUplinkPort -ModifyPresent -AdminState "enabled" -PortId 9 -SlotId 2
Complete-UcsTransaction

Start-UcsTransaction
$mo = Get-UcsFiSanCloud -Id "A" | Add-UcsFcUplinkPortChannel -AdminSpeed "Auto" -AdminState "enabled" -Name "Fabric-A-PC" -PortId 50
$mo_1 = $mo | Add-UcsFabricFcSanPcEp -ModifyPresent -AdminSpeed "auto" -AdminState "enabled" -PortId 15 -SlotId 2
$mo_1 = $mo | Add-UcsFabricFcSanPcEp -ModifyPresent -AdminSpeed "auto" -AdminState "enabled" -PortId 16 -SlotId 2
Complete-UcsTransaction

Start-UcsTransaction
Get-UcsFiSanCloud -Id "B" | Add-UcsFcUplinkPort -ModifyPresent -AdminState "enabled" -PortId 16 -SlotId 2
Get-UcsFiSanCloud -Id "B" | Add-UcsFcUplinkPort -ModifyPresent -AdminState "enabled" -PortId 15 -SlotId 2
Get-UcsFiSanCloud -Id "B" | Add-UcsFcUplinkPort -ModifyPresent -AdminState "enabled" -PortId 14 -SlotId 2
Get-UcsFiSanCloud -Id "B" | Add-UcsFcUplinkPort -ModifyPresent -AdminState "enabled" -PortId 13 -SlotId 2
Get-UcsFiSanCloud -Id "B" | Add-UcsFcUplinkPort -ModifyPresent -AdminState "enabled" -PortId 12 -SlotId 2
Get-UcsFiSanCloud -Id "B" | Add-UcsFcUplinkPort -ModifyPresent -AdminState "enabled" -PortId 11 -SlotId 2
Get-UcsFiSanCloud -Id "B" | Add-UcsFcUplinkPort -ModifyPresent -AdminState "enabled" -PortId 10 -SlotId 2
Get-UcsFiSanCloud -Id "B" | Add-UcsFcUplinkPort -ModifyPresent -AdminState "enabled" -PortId 9 -SlotId 2
Complete-UcsTransaction

Start-UcsTransaction
$mo = Get-UcsFiSanCloud -Id "B" | Add-UcsFcUplinkPortChannel -AdminSpeed "Auto" -AdminState "enabled" -Name "Fabric-B-PC" -PortId 50
$mo_1 = $mo | Add-UcsFabricFcSanPcEp -ModifyPresent -AdminSpeed "auto" -AdminState "enabled" -PortId 15 -SlotId 2
$mo_1 = $mo | Add-UcsFabricFcSanPcEp -ModifyPresent -AdminSpeed "auto" -AdminState "enabled" -PortId 16 -SlotId 2
Complete-UcsTransaction

################################################
###Configure Uplinks from Fabric Interconects###
################################################

Get-UcsFiLanCloud -Id "A" | Add-UcsUplinkPort -AdminSpeed "10gbps" -AdminState "enabled" -FlowCtrlPolicy "default" -Name "" -PortId 1 -SlotId 2
Get-UcsFiLanCloud -Id "A" | Add-UcsUplinkPort -AdminSpeed "10gbps" -AdminState "enabled" -FlowCtrlPolicy "default" -Name "" -PortId 2 -SlotId 2

Start-UcsTransaction
$mo = Get-UcsFiLanCloud -Id "A" | Add-UcsUplinkPortChannel -AdminSpeed "10gbps" -AdminState "enabled" -FlowCtrlPolicy "default" -Name "FI-A-PC" -OperSpeed "10gbps" -PortId 1
$mo_1 = $mo | Add-UcsUplinkPortChannelMember -ModifyPresent -AdminState "enabled" -Name "" -PortId 1 -SlotId 2
$mo_2 = $mo | Add-UcsUplinkPortChannelMember -ModifyPresent -AdminState "enabled" -Name "" -PortId 2 -SlotId 2
Complete-UcsTransaction

Get-UcsFiLanCloud -Id "B" | Add-UcsUplinkPort -AdminSpeed "10gbps" -AdminState "enabled" -FlowCtrlPolicy "default" -Name "" -PortId 1 -SlotId 2
Get-UcsFiLanCloud -Id "B" | Add-UcsUplinkPort -AdminSpeed "10gbps" -AdminState "enabled" -FlowCtrlPolicy "default" -Name "" -PortId 2 -SlotId 2

Start-UcsTransaction
$mo = Get-UcsFiLanCloud -Id "B" | Add-UcsUplinkPortChannel -AdminSpeed "10gbps" -AdminState "enabled" -FlowCtrlPolicy "default" -Name "FI-B-PC" -OperSpeed "10gbps" -PortId 2
$mo_1 = $mo | Add-UcsUplinkPortChannelMember -ModifyPresent -AdminState "enabled" -Name "" -PortId 1 -SlotId 2
$mo_2 = $mo | Add-UcsUplinkPortChannelMember -ModifyPresent -AdminState "enabled" -Name "" -PortId 2 -SlotId 2
Complete-UcsTransaction

#############################
###Deploy Service Profiles###
#############################
$increment=1
do {
Get-UcsServiceProfile -Name ESX -org org-root | Add-UcsServiceProfileFromTemplate -NewName "vmhost00$increment"
$increment++
}
while ($increment -le $TotalHosts)

disconnect-ucs


write-host
write-host
write-host
write-host **** UCS Configuration Complete  ***






 
