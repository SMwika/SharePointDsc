[CmdletBinding()]
param(
    [string] $SharePointCmdletModule = (Join-Path $PSScriptRoot "..\Stubs\SharePoint\15.0.4693.1000\Microsoft.SharePoint.PowerShell.psm1" -Resolve)
)

$ErrorActionPreference = 'stop'
Set-StrictMode -Version latest

$RepoRoot = (Resolve-Path $PSScriptRoot\..\..).Path
$Global:CurrentSharePointStubModule = $SharePointCmdletModule 

$ModuleName = "MSFT_xSPAppManagementServiceApp"
Import-Module (Join-Path $RepoRoot "Modules\xSharePoint\DSCResources\$ModuleName\$ModuleName.psm1")

Describe "xSPAppManagementServiceApp" {
    InModuleScope $ModuleName {
        $testParams = @{
            Name = "Test App"
            ApplicationPool = "Test App Pool"
            DatabaseName = "Test_DB"
            DatabaseServer = "TestServer\Instance"
        }
        Import-Module (Join-Path ((Resolve-Path $PSScriptRoot\..\..).Path) "Modules\xSharePoint")

        
        Mock Invoke-xSharePointCommand { 
            return Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $Arguments -NoNewScope
        }
        
        Import-Module $Global:CurrentSharePointStubModule -WarningAction SilentlyContinue

        Context "When no service applications exist in the current farm" {

            Mock Get-SPServiceApplication { return $null }
            Mock New-SPAppManagementServiceApplication { }

            It "returns null from the Get method" {
                Get-TargetResource @testParams | Should BeNullOrEmpty
                Assert-MockCalled Get-SPServiceApplication -ParameterFilter { $Name -eq $testParams.Name } 
            }

            It "returns false when the Test method is called" {
                Test-TargetResource @testParams | Should Be $false
            }

            It "creates a new service application in the set method" {
                Set-TargetResource @testParams
                Assert-MockCalled New-SPAppManagementServiceApplication
            }
        }

        Context "When service applications exist in the current farm but the specific Add-in app does not" {

            Mock Get-SPServiceApplication { return @(@{
                TypeName = "Some other service app type"
            }) }

            It "returns null from the Get method" {
                Get-TargetResource @testParams | Should BeNullOrEmpty
                Assert-MockCalled Get-SPServiceApplication -ParameterFilter { $Name -eq $testParams.Name } 
            }

        }

        Context "When a service application exists and is configured correctly" {
            Mock Get-SPServiceApplication { 
                return @(@{
                    TypeName = "Business Data Connectivity Service Application"
                    DisplayName = $testParams.Name
                    ApplicationPool = @{ Name = $testParams.ApplicationPool }
                    Database = @{
                        Name = $testParams.DatabaseName
                        Server = @{ Name = $testParams.DatabaseServer }
                    }
                })
            }

            It "returns values from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
                Assert-MockCalled Get-SPServiceApplication -ParameterFilter { $Name -eq $testParams.Name } 
            }

            It "returns true when the Test method is called" {
                Test-TargetResource @testParams | Should Be $true
            }
        }

        Context "When a service application exists and the app pool is not configured correctly" {
            Mock Get-SPServiceApplication { 
                $service = @(@{
                    TypeName = "Business Data Connectivity Service Application"
                    DisplayName = $testParams.Name
                    ApplicationPool = @{ Name = "Wrong App Pool Name" }
                    Database = @{
                        Name = $testParams.DatabaseName
                        Server = @{ Name = $testParams.DatabaseServer }
                    }
                })
                    
                $service = $service | Add-Member ScriptMethod Update {
                    $Global:xSPAppServiceUpdateCalled = $true
                } -PassThru 
            return $result 
                return $service
            }
            Mock Get-SPServiceApplicationPool { 
                @{ Name = $testParams.ApplicationPool } }

            It "returns false when the Test method is called" {
                Test-TargetResource @testParams | Should Be $false
            }

            It "calls the update service app cmdlet from the set method" {
                Set-TargetResource @testParams
                Assert-MockCalled Get-SPServiceApplicationPool
                $Global:xSPWebApplicationUpdateWorkflowCalled | Should Be $true
            }
        }
    }
}
