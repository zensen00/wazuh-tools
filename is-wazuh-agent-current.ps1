#
# is-wazuh-agent-current.ps1
#
# This script is to be used to determine if there is need to call the deploy-wazuh-windows-agent-suite.ps1 script.
# If any of the follwing test families fail, a return code of 1 will be returned.  Otherwise it will return a 0.
# The Sysmon tests will be skipped if -SkipSysmon is selected and the Osquery tests will be skipped if -SkipOsquery is selected.
#
# 1 - Is the agent presently really connected to the Wazuh manager?
# 2 - Is the agent currently a member of all intended Wazuh agent groups?
# 3 - Is the target version of Wazuh agent installed?
# 4 - Is the target version of Sysmon installed
# 5 - Is the target version of Osquery installed
#
# Required parameters:
#
# $WazuhVer		Full Wazuh agent version number, like "3.12.2"
# $OsqueryVer		Full version of Osquery, like "4.2.0" (always N.N.N format)
# $SysmonVer		Full version of Sysmon, like "11.11" (always N.N format)
# $SkipSysmon		Do not examine Sysmon.
# $SkipOsquery		Do not examine Osquery.
# $WazuhGroups		Comma separated list of optional extra Wazuh agent groups. No spaces. Put whole list in quotes.
#
param ( $WazuhVer, 
		$OsqueryVer, 
		$SysmonVer, 
		[switch]$SkipSysmon=$false, 
		[switch]$SkipOsquery=$false,
		$WazuhGroups
);

# If false, there will be no output except a 0 or 1 return value.
$DBG = $false

#
# 1 - Is the agent presently really connected to the Wazuh manager?
#
$file = Get-Content "C:\Program Files (x86)\ossec-agent\ossec-agent.state" -erroraction 'silentlycontinue'
if ( -not ($file -match "'connected'" ) ) {
	if ($DBG) { Write-Output "The Wazuh agent is not connected to the Wazuh manager." }
	return 1
}

#
# 2 - Is the agent currently a member of all intended Wazuh agent groups?
#
$file2 = Get-Content "C:\Program Files (x86)\ossec-agent\shared\merged.mg" -erroraction 'silentlycontinue'
if ($file2 -match "Source\sfile:") {
	$CURR_GROUPS=((((Select-String -Path 'C:\Program Files (x86)\ossec-agent\shared\merged.mg' -Pattern "Source file:") | Select-Object -ExpandProperty Line).Replace("<!-- Source file: ","")).Replace("/agent.conf -->","")) -join ','
} else {
	# If the agent is presently a member of only one agent group, then pull that group name into current group variable.
	$CURR_GROUPS=((((Select-String -Path 'C:\Program Files (x86)\ossec-agent\shared\merged.mg' -Pattern "#") | Select-Object -ExpandProperty Line).Replace("#","")))
}
if ($DBG) { Write-Output "Current agent group membership: $CURR_GROUPS" }

# Blend standard/dynamic groups with custom groups
$WazuhGroupsPrefix = "windows,"
if ( $SkipOsquery -eq $false ) {
	$WazuhGroupsPrefix = $WazuhGroupsPrefix+"osquery,"
}
if ( $SkipSysmon -eq $false ) {
	$WazuhGroupsPrefix = $WazuhGroupsPrefix+"sysmon,"
}
$WazuhGroups = $WazuhGroupsPrefix+$WazuhGroups
$WazuhGroups = $WazuhGroups.TrimEnd(",")
if ($DBG) { Write-Output "Target agent group membership:  $WazuhGroups" }
if ( -not ( $CURR_GROUPS -eq $WazuhGroups ) ) {
	if ($DBG) { Write-Output "Current and expected agent group membership differ." }
	return 1
}

#
# 3 - Is the target version of Wazuh agent installed?
#
$version = [IO.File]::ReadAllText("C:\Program Files (x86)\ossec-agent\VERSION").split("`n")[0].split("v")[1]
if ($DBG) { Write-Output "Current Wazuh agent version is: $version" }
if ($DBG) { Write-Output "Target Wazuh agent version is:  $WazuhVer" }
if ( -not ( $WazuhVer.Trim() -eq $version.Trim() ) ) {
	if ($DBG) { Write-Output "Current and expected Wazuh agent version differ." }
	return 1
}

if ( $SkipSysmon -eq $false ) {
	#
	# 4 - Is the target version of Sysmon installed?
	#
	# Local Sysmon.exe file exists?
	if ( -not (Test-Path -LiteralPath "C:\Program Files (x86)\sysmon-wazuh\Sysmon.exe") ) {
		if ($DBG) { Write-Output "Sysmon appears to not be installed." }
		return 1
	}
	# Local Sysmon.exe file at target version?
	$smver=[System.Diagnostics.FileVersionInfo]::GetVersionInfo("C:\Program Files (x86)\sysmon-wazuh\Sysmon.exe").FileVersion
	if ($DBG) { Write-Output "Current Sysmon version is: $smver" }
	if ($DBG) { Write-Output "Target Sysmon version is:  $SysmonVer" }
	if ( -not ( $smver.Trim() -eq $SysmonVer.Trim() ) ) {
		if ($DBG) { Write-Output "Current and expected Sysmon version differ." }
		return 1
	}
	# Sysmon driver loaded?
	$fltOut = (fltMC.exe) | Out-String
	if ( -not ( $fltOut -match 'SysmonDrv' ) ) {
		if ($DBG) { Write-Output "Sysmon driver is not loaded." }
		return 1
	}
}

if ( $SkipOsquery -eq $false ) {
	#
	# 5 - Is the target version of Osquery installed?
	#
	# Local osqueryd.exe present?
	if ( -not (Test-Path -LiteralPath "C:\Program Files\osquery\osqueryd\osqueryd.exe") ) {
		if ($DBG) { Write-Output "Osquery executable appears to be missing." }
		return 1
	}
	# Correct version?
	$osqver=[System.Diagnostics.FileVersionInfo]::GetVersionInfo("C:\Program Files\osquery\osqueryd\osqueryd.exe").FileVersion
	$osqver = $osqver -replace '\.\d+$',''
	if ($DBG) { Write-Output "Current Osquery version is: $osqver" }
	if ($DBG) { Write-Output "Target Osquery version is:  $OsqueryVer" }
	if ( -not ( $osqver.Trim() -eq $OsqueryVer.Trim() ) ) {
		if ($DBG) { Write-Output "Current and expected Osquery version differ." }
		return 1
	}
	# Actually running?
	if ( -not ( Get-Process -Name "osqueryd" -erroraction 'silentlycontinue' ) ) {
		if ($DBG) { Write-Output "Osquery does not appear to be running." }
		return 1
	}
}

# All relevant tests passed, so return a success code.
return 0
