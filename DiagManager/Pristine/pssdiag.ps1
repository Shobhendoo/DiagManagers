
param
(
    [Parameter(ParameterSetName = 'ServiceRelated',Mandatory=$true)]
    [Parameter(Position = 0)]
    [string] $ServiceState = "",

    [Parameter(ParameterSetName = 'Config',Mandatory=$false)]
    [switch] $help,

    [Parameter(ParameterSetName = 'Config',HelpMessage='/I xml_config_file',Mandatory=$false)]
    [string] $I = "pssdiag.xml",

    [Parameter(ParameterSetName = 'Config',HelpMessage='/O output_path',Mandatory=$false)]
    [string] $O = "output",

    [Parameter(ParameterSetName = 'Config',Mandatory=$false)]
    [string] $P = "",

    [Parameter(ParameterSetName = 'Config',Mandatory=$false)]
    [string] $N = "1",

    [Parameter(ParameterSetName = 'Config',Mandatory=$false)]
    [string] $M = [string]::Empty,

    [Parameter(ParameterSetName = 'Config',Mandatory=$false)]
    [switch] $Q ,
    
    [Parameter(ParameterSetName = 'Config',Mandatory=$false)]
    [string] $C = "0",

    [Parameter(ParameterSetName = 'Config',Mandatory=$false)]
    [switch] $G,

    [Parameter(ParameterSetName = 'Config',Mandatory=$false)]
    [switch] $R,

    [Parameter(ParameterSetName = 'Config',Mandatory=$false)]
    [switch] $U,

    [Parameter(ParameterSetName = 'Config',Mandatory=$false)]
    [string] $A = [string]::Empty,

    [Parameter(ParameterSetName = 'Config',Mandatory=$false)]
    [switch] $L,

    [Parameter(ParameterSetName = 'Config',Mandatory=$false)]
    [switch] $X,

    [Parameter(ParameterSetName = 'Config',Mandatory=$false)]
    [string] $B = [string]::Empty,

    [Parameter(ParameterSetName = 'Config',Mandatory=$false)]
    [string] $E = [string]::Empty,

    [Parameter(ParameterSetName = 'Config',Mandatory=$false)]
    [string] $T = [string]::Empty,

    [Parameter(ParameterSetName = 'Config',Mandatory=$false)]
    [switch] $DebugOnParam


)


. ./Confirm-FileAttributes.ps1


function Check-ElevatedAccess
{
    try 
    {
	
        #check for administrator rights
        if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
        {
            Write-Warning "Elevated privilege (run as Admininstrator) is required to run PSSDIAG. Exiting..."
            exit
        }
        
    }

    catch 
    {
        Write-Error "Error occured in $($MyInvocation.MyCommand), $($PSItem.Exception.Message ), line number: $($PSItem.InvocationInfo.ScriptLineNumber)" 
		exit
    }
    

}


function FindSQLDiag ()
{

    try
    {
				
        [bool]$is64bit = $false

        [xml]$xmlDocument = Get-Content -Path .\pssdiag.xml
        [string]$sqlver = $xmlDocument.dsConfig.Collection.Machines.Machine.Instances.Instance.ssver
		

        if ($sqlver -eq "10.50")
        {
              $sqlver = "10"
        }


        [string]$plat = $xmlDocument.dsConfig.DiagMgrInfo.IntendedPlatform


        [string] $x86Env = [Environment]::GetEnvironmentVariable( "CommonProgramFiles(x86)");


         #[System.Environment]::Is64BitOperatingSystem

        if ($x86Env -ne $null)
        {
            $is64bit = $true
        }

        $toolsRegStr = ("HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\" + $sqlver+"0\Tools\ClientSetup")
		
	
	
        [string]$toolsBinFolder = Get-ItemPropertyValue -Path $toolsRegStr -Name Path


		#strip "(x86)" in case Powershell goes to HKLM\SOFTWARE\WOW6432Node\Microsoft\Microsoft SQL Server\ under the covers, which it does
		
		$toolsBinFolderx64 = $toolsBinFolder.Replace("Program Files (x86)", "Program Files")

		
		$sqldiagPath = ($toolsBinFolder + "sqldiag.exe")
        $sqldiagPathx64 = ($toolsBinFolderx64 + "sqldiag.exe")
		
		
	
        if ((Test-Path -Path $sqldiagPathx64))
        {
			return $sqldiagPathx64
		}
		
		else
		{
			#path was not valid so checking second path
			
			if ($sqldiagPath -ne $sqldiagPathx64)
			{
				if ((Test-Path -Path $sqldiagPath))
				{
					return $sqldiagPath
				}
			}
			
			Write-Host "Unable to find 'sqldiag.exe' version: $($sqlver)0 on this machine.  Data collection will fail"
			return "Path_Error_"
        }
        
		
    }
    catch 
    {
        Write-Error "Error occured in finding SQLDiag.exe: $($PSItem.Exception.Message ), line number: $($PSItem.InvocationInfo.ScriptLineNumber)" 
		return "Path_Error_"
    }

}




function PrintHelp
{
	 Write-Host " [-I cfgfile] = sets the configuration file, typically either pssdiag.xml or sqldiag.xml.`n"`
        "[-O outputpath] = sets the output folder.  Defaults to startupfolder\SQLDIAG (if the folder does not exist, the collector will attempt to create it) `n" `
        "[-N #] = output folder management at startup #: 1 = overwrite (default), 2 = rename (format is OUTPUT_00001,...00002, etc.) `n" `
        "[-P supportpath] = sets the support path folder.  Defaults to startupfolder if not specified `n" `
        "[-M machine1 [machine2 machineN]|`@machinelistfile] = overrides the machines specified in the config file. When specifying more than one machine, separate each machine name with a space. "`@" specifies a machine list file `n" `
        "[-Q]  = quiet mode -- supresses prompts (e.g., password prompts) `n" `
        "[-C #] = file compression type: 0 = none (default), 1 = NTFS, 2 = CAB `n" `
        "[-G]  = generic mode -- SQL Server connectivity checks are not enforced; machine enumeration includes all servers, not just SQL Servers `n" `
        "[-R]  = registers the collector as a service `n" `
        "[-U]  = unregisters the collector as a service `n" `
        "[-A appname] = sets the application name.  If running as a service, this sets the service name `n" `
        "[-L] = continuous mode -- automatically restarts when shutdown via -X or -E `n" `
        "[-X] = snapshot mode -- takes a snapshot of all configured diagnostics and shuts down immediately `n" `
        "[-B [+]YYYYMMDD_HH:MM:SS] = specifies the date/time to begin collecting data; "+HH:MM:SS" specifies a relative time `n" `
        "[-E [+]YYYYMMDD_HH:MM:SS]  = specifies the date/time to end data collection; "+HH:MM:SS" specifies a relative time `n" `
        "[-T {tcp[,port]|np|lpc|via}] = connects to sql server using the specified protocol `n" `
        "[-Debug] = print some verbose messages for debugging where appropriate `n" `
        "[START], [STOP], [STOP_ABORT] = service commands for a registered (-R) SQLDIAG service `n" `
        ""        -ForegroundColor Green

        exit
}

function main 
{

    [bool] $debug_on = $false

    if ($DebugOnParam -eq $true)
    {
        $debug_on = $true
    }
	
	if (Check-ElevatedAccess -eq $true)
	{
		exit
	}
	

    $validFileAttributes = Confirm-FileAttributes $debug_on
        if (-not($validFileAttributes)){
            Write-Host "File attribute validation FAILED. Exiting..." -ForegroundColor Red
            return
        }
        
    

    [string] $argument_list = ""

    if ($ServiceState -iin "stop", "start", "stop_abort", "/U")
    {
        Write-Host "ServiceState = $ServiceState"
        $argument_list = $ServiceState    
    }
    elseif (($ServiceState -iin "--?", "/?", "?", "--help", "help") -or ($help -eq $true) )
    {
        PrintHelp
    }
    else
    {
        
        # [/I cfgfile] = sets the configuration file, typically either sqldiag.ini or sqldiag.xml.  Default is sqldiag.xml
        $lv_I = "/I " + $I

        # [/O outputpath] = sets the output folder.  Defaults to startupfolder\SQLDIAG (if the folder does not exist, the collector will attempt to create it)
        $lv_O = "/O " + $O
        
        # [/P supportpath] = sets the support path folder.   By default, /P is set to the folder where the SQLdiag executable resides. 
		# The support folder contains SQLdiag support files, such as the XML configuration file, Transact-SQL scripts, and other files that the utility uses during diagnostics collection. 
		# If you use this option to specify an alternate support files path, SQLdiag will automatically copy the support files it requires to the specified folder if they do not already exist.
        $lv_P = "/P " + $P    

        # [/N #] = output folder management at startup #: 1 = overwrite (default), 2 = rename (format is OUTPUT_00001,...00002, etc.)
        $lv_N = "/N " + $N

        # [/M machine1 [machine2 machineN]|@machinelistfile] = overrides the machines specified in the config file. When specifying more than one machine, separate each machine name with a space. "@" specifies a machine list file
        if ([string]::IsNullOrWhiteSpace($M))
        {
            $lv_M = ""
        }
        else 
        {
            $lv_M = "/M " + $M    
        }


        # [/Q]  = quiet mode -- supresses prompts (e.g., password prompts)

        if ($Q -eq $false)
        {
            $lv_Q = ""
        }
        else 
        {
            $lv_Q = "/Q "
        }
        
        # [/C #] = file compression type: 0 = none (default), 1 = NTFS, 2 = CAB

        $lv_C = "/C " + $C
        
        # [/G]  = generic mode -- SQL Server connectivity checks are not enforced; machine enumeration includes all servers, not just SQL Servers
        
        if ($G -eq $false)
        {
            $lv_G = ""
        }
        else 
        {
            $lv_G = "/G "
        }
        
        # [/R]  = registers the collector as a service

        if ($R -eq $false)
        {
            $lv_R = ""
        }
        else 
        {
            $lv_R = "/R "
        }
        
        # [/U]  = unregisters the collector as a service
        
        if ($U -eq $false)
        {
            $lv_U = ""
        }
        else 
        {
            $lv_U = "/U "
        }

        # [/A appname] = sets the application name to DIAG$appname.  If running as a service, this sets the service name to DIAG$appname

        if ([string]::IsNullOrWhiteSpace($A))
        {
            $lv_A = ""
        }
        else 
        {
            $lv_A = "/A " + $A
        }

        # [/L] = continuous mode -- automatically restarts when shutdown via /X or /E
        
        if ($L -eq $false)
        {
            $lv_L = ""
        }
        else 
        {
            $lv_L = "/L "
        }

        
        # [/X] = snapshot mode -- takes a snapshot of all configured diagnostics and shuts down immediately

        if ($X -eq $false)
        {
            $lv_X = ""
        }
        else 
        {
            $lv_X = "/X "
        }

        
        # [/B [+]YYYYMMDD_HH:MM:SS] = specifies the date/time to begin collecting data; "+" specifies a relative time

        if ([string]::IsNullOrWhiteSpace($B))
        {
            $lv_B = ""
        }
        else 
        {
            $lv_B = "/B " + $B
        }
        
        # [/E [+]YYYYMMDD_HH:MM:SS]  = specifies the date/time to end data collection; "+" specifies a relative time
        
        if ([string]::IsNullOrWhiteSpace($E))
        {
            $lv_E = ""
        }
        else 
        {
            $lv_E = "/E " + $E
        }

        # [/T {tcp[,port]|np|lpc|via}] = connects to sql server using the specified protocol

        if ([string]::IsNullOrWhiteSpace($T))
        {
            $lv_T = ""
        }
        else 
        {
            $lv_T = "/T " + $T
        }    


        if ($lv_U -eq "/U ")
        {
            $argument_list = $lv_U
        }
        else 
        {
            # special case if user typed /r instead of -R
            if ($ServiceState -eq "/r")
            {
                $lv_R = "/R "
            }

            $argument_list =  $lv_I + " " + $lv_O  + " " + $lv_P + " " + $lv_N + " " + $lv_M + " " + $lv_Q + " " + $lv_C + " " + $lv_G `
                + " " + $lv_R + " " + $lv_A  + " " + $lv_L  + " " + $lv_X + " " + $lv_B + " " + $lv_E + " " + $lv_T    
        }
        
    }

	# locate the SQLDiag.exe path for this version of PSSDIAG
	[string]$sqldiag_path = FindSQLDiag
	
	if ("Path_Error_" -eq $sqldiag_path)
	{
		#no valid path found to run SQLDiag.exe, so exiting
		exit
	}

		
	#call diagutil.exe 1 for now until counter translation is implemented in this script
	Write-Host "Executing: diagutil.exe 1"
	Start-Process -FilePath "diagutil.exe" -ArgumentList "1" -WindowStyle Normal

    # launch the sqldiag.exe process
    Write-Host "Executing: $sqldiag_path $argument_list"
    Start-Process -FilePath $sqldiag_path -ArgumentList $argument_list -WindowStyle Normal
}


main
