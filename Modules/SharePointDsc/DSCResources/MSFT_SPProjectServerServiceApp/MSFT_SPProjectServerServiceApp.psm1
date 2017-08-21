function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)] 
        [System.String] 
        $Name,

        [parameter(Mandatory = $true)]
        [System.String] 
        $ApplicationPool,

        [parameter(Mandatory = $false)]
        [System.String] 
        $ProxyName,

        [parameter(Mandatory = $false)] 
        [ValidateSet("Present","Absent")] 
        [System.String] 
        $Ensure = "Present",

        [parameter(Mandatory = $false)] 
        [System.Management.Automation.PSCredential] 
        $InstallAccount
    )

    Write-Verbose -Message "Getting Project Server service app '$Name'"

    $result = Invoke-SPDSCCommand -Credential $InstallAccount `
                                  -Arguments $PSBoundParameters `
                                  -ScriptBlock {
        $params = $args[0]
    
        $serviceApps = Get-SPServiceApplication -Name $params.Name `
                                                -ErrorAction SilentlyContinue
        $nullReturn = @{
            Name            = $params.Name
            ApplicationPool = ""
            ProxyName       = ""
            Ensure          = "Absent"
            InstallAccount  = $params.InstallAccount
        } 
        if ($null -eq $serviceApps) 
        { 
            return $nullReturn
        }
        $serviceApp = $serviceApps | Where-Object -FilterScript { 
            $_.GetType().FullName -eq "Microsoft.Office.Project.Server.Administration.PsiServiceApplication"
        }

        if ($null -eq $serviceApp) 
        { 
            return $nullReturn
        } 
        else 
        {
            $serviceAppProxies = Get-SPServiceApplicationProxy -ErrorAction SilentlyContinue
            if ($null -ne $serviceAppProxies)
            {
                $serviceAppProxy = $serviceAppProxies | Where-Object -FilterScript { 
                    $serviceApp.IsConnected($_)
                }
                if ($null -ne $serviceAppProxy) 
                { 
                    $proxyName = $serviceAppProxy.Name
                }
            }
            
            return @{
                Name            = $serviceApp.DisplayName
                ApplicationPool = $serviceApp.ApplicationPool.Name
                ProxyName       = $proxyName
                Ensure          = "Present"
                InstallAccount  = $params.InstallAccount
            }
        }
    }
    return $result
}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)] 
        [System.String] 
        $Name,

        [parameter(Mandatory = $true)]
        [System.String] 
        $ApplicationPool,

        [parameter(Mandatory = $false)]
        [System.String] 
        $ProxyName,

        [parameter(Mandatory = $false)] 
        [ValidateSet("Present","Absent")] 
        [System.String] 
        $Ensure = "Present",

        [parameter(Mandatory = $false)] 
        [System.Management.Automation.PSCredential] 
        $InstallAccount
    )

    Write-Verbose -Message "Setting Project Server service app '$Name'"

    $result = Get-TargetResource @PSBoundParameters

    if ($result.Ensure -eq "Absent" -and $Ensure -eq "Present") 
    { 
        Write-Verbose -Message "Creating Project Server Service Application $Name"
        Invoke-SPDSCCommand -Credential $InstallAccount `
                            -Arguments $PSBoundParameters `
                            -ScriptBlock {
            $params = $args[0]
        
            $pwaApp = New-SPProjectServiceApplication -Name $params.Name `
                                                      -ApplicationPool $params.ApplicationPool
            if ($params.ContainsKey("ProxyName") -eq $true)
            {
                $pName = $params.ProxyName
            }
            else 
            {
                $pName = "$($params.Name) Proxy"
            }
            
            if ($null -ne $pwaApp)
            {
                $null = New-SPProjectServiceApplicationProxy -Name $pName -ServiceApplication $params.Name
            }
        }
    }
    if ($result.Ensure -eq "Present" -and $Ensure -eq "Present") 
    {
        if ($ApplicationPool -ne $result.ApplicationPool) 
        {
            Write-Verbose -Message "Updating Project Server Service Application $Name"
            Invoke-SPDSCCommand -Credential $InstallAccount `
                                -Arguments $PSBoundParameters `
                                -ScriptBlock {
                $params = $args[0]               

                $appPool = Get-SPServiceApplicationPool -Identity $params.ApplicationPool

                Get-SPServiceApplication -Name $params.Name `
                    | Where-Object -FilterScript { 
                        $_.GetType().FullName -eq "Microsoft.Office.Project.Server.Administration.PsiServiceApplication"
                    } | Set-SPProjectServiceApplication -ApplicationPool $appPool
            }
        }
    }
    
    if ($Ensure -eq "Absent") 
    {
        Write-Verbose -Message "Removing Project Server service application $Name"
        Invoke-SPDSCCommand -Credential $InstallAccount `
                            -Arguments $PSBoundParameters `
                            -ScriptBlock {
            $params = $args[0]
            
            $app = Get-SPServiceApplication -Name $params.Name `
                    | Where-Object -FilterScript { 
                        $_.GetType().FullName -eq "Microsoft.Office.Project.Server.Administration.PsiServiceApplication"
                    }

            $proxies = Get-SPServiceApplicationProxy
            foreach($proxyInstance in $proxies)
            {
                if($app.IsConnected($proxyInstance))
                {
                    $proxyInstance.Delete()
                }
            }

            Remove-SPServiceApplication -Identity $app -Confirm:$false
        }
    }   
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)] 
        [System.String] 
        $Name,

        [parameter(Mandatory = $true)]
        [System.String] 
        $ApplicationPool,

        [parameter(Mandatory = $false)]
        [System.String] 
        $ProxyName,

        [parameter(Mandatory = $false)] 
        [ValidateSet("Present","Absent")] 
        [System.String] 
        $Ensure = "Present",

        [parameter(Mandatory = $false)] 
        [System.Management.Automation.PSCredential] 
        $InstallAccount
    )
    
    Write-Verbose -Message "Testing Project Server service app '$Name'"

    $PSBoundParameters.Ensure = $Ensure

    $CurrentValues = Get-TargetResource @PSBoundParameters

    if ($Ensure -eq "Present")
    {
        return Test-SPDscParameterState -CurrentValues $CurrentValues `
                                        -DesiredValues $PSBoundParameters `
                                        -ValuesToCheck @("ApplicationPool", "Ensure")
    }
    else 
    {
        return Test-SPDscParameterState -CurrentValues $CurrentValues `
                                        -DesiredValues $PSBoundParameters `
                                        -ValuesToCheck @("Ensure")
    }
    
}

Export-ModuleMember -Function *-TargetResource
