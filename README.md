# DevMachineAutomation
In dynamics 365 for finance and  operations implementation each developer has their own development  machine connected to Azure Dev ops. When developer start working, usual practice is to do get latest from source control , build models which are changed and syncronize database in order to sync their machines to source control . Above powershell script is going to help to do this automation. You can schedule this script as a task on every Dev machine  to do all these things. This script also post messages to Microsoft teams with errors. The Power Shell cmdlets and Windows Shell Extension (x64) needs to be installed from the Team Foundation Server Power tools package for TFS get latest.To enable power shell script execution in AX 7.2 and up machines:
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser
