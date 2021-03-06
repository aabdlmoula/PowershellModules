function Write-CommandOverload
{
    <#
    .Synopsis
        Writes a command overload.          
    .Description
        This creates a command that runs another command.  It can optionally drop some parameters, or create new ones. 
    .Example
        Write-CommandOverload -CommandName dir -NewTypeName myCustomDirView      
    .Example
        Write-CommandOverload -CommandName dir -ProcessEachItem { $_ }
    .Link
        creating_command_overloads_with_ezout
    #>
    [CmdletBinding(DefaultParameterSetName='CommandName')]
    param(
    # The command metadata of the command to overload
    [Parameter(Mandatory=$true,ParameterSetName='CommandMetaData')]
    [Management.Automation.CommandMetaData]
    $Command,
    
    # The name of the command to overload
    #|Options Get-Command | ForEach-Object { ($_.ModuleName + $_.PSSnapinName + "\" + $_.Name).TrimStart("\") } 
    [Parameter(Mandatory=$true,
        Position=0,
        ValueFromPipelineByPropertyName=$true,
        ParameterSetName='CommandName')]
    [string]
    $CommandName,
    
    # The module the command to overload is in
    [Parameter(Position=1,
        ValueFromPipelineByPropertyName=$true,
        ParameterSetName='CommandName')]
    [Alias('ModuleName', 'PSSnapinName')]
    [string]
    $Module,
    
    # Any additional parameters to add to the command.
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [Management.Automation.ParameterMetaData[]]
    $AdditionalParameter,
    
    # Any parameters to remove from the command.
    [Parameter(ValueFromPipelineByPropertyName=$true)]    
    [string[]]
    $RemoveParameter,

    # A new type name.  This clears the type name table for each output and replaces it with a new name.  
    # This allows you to change the default view of a built-in command.
    [string]
    $NewTypeName,
    
    # Any script that will be run on each item of output
    [ScriptBlock]
    $ProcessEachItem,
    
    # The name of the command to create.  If no name is specified, the command's name will be used
    [string]
    $Name,
    
    # Any default values to pass to the command
    [Hashtable]
    $DefaultValue   
    )
    
    process {
        if ($psCmdlet.ParameterSetName -eq 'CommandName') {
            $nestedParams = @{} + $psBoundParameters
            if ($psBoundParameters.CommandName -like "*\*") {
                $psBoundParameters.Module = $psBoundParameters.CommandName.Split("\")[0]
                $psBoundParameters.Name = $psBoundParameters.CommandName.Split("\")[1]
            } else {
                $psBoundParameters.Name = $psBoundParameters.CommandName
            }
            
            $null = $nestedParams.Remove('Module'),
                $nestedParams.Remove('CommandName'),
                $psBoundParameters.Remove('CommandName'),
                $psBoundParameters.Remove('DefaultValue'),
                $psBoundParameters.Remove('ProcessEachItem')
            $resolvedCommand = Get-Command @psboundParameters
            
            if (-not $resolvedCommand) { 
                return
            }
            & $myInvocation.MyCommand -Command $resolvedCommand @nestedParams 
        } elseif ($psCmdlet.ParameterSetName -eq 'CommandMetaData') {     
            $MetaData = New-Object Management.Automation.CommandMetaData $Command
            foreach ($rp in $removeParameter) {
                if (-not $rp) { continue }
                $null = $MetaData.Parameters.Remove($rp)
            }
            foreach ($ap in $additionalParameter) {
                if (-not $ap) { continue }
                $null = $MetaData.Parameters.Add($ap.Name, $ap)
            }
            
            
            $beginBlock  = if ($NewTypeName -or $ProcessEachItem){
                [Management.Automation.ProxyCommand]::GetBegin($metaData) -replace '\.Begin\(\$PSCmdlet\)', '.Begin($false)'                
            } else {
                [Management.Automation.ProxyCommand]::GetBegin($metaData)
            }
            
            if (-not $Name) {
                $Name = $command.Name
            }
            
            
            if ($DefaultValue) {
                $defaultValueText = Write-PowerShellHashtable  -InputObject $DefaultValue
                
                $defaultValueText = '$default = ' + $defaultValueText + {
foreach ($kv in $default.GetEnumerator()) {
    $psBoundParameters[$kv.Key] = $kv.Value
}
}
                
                $defaultValueText = $defaultValueText -split ([Environment]::NewLine) -ne "" |
                    ForEach-Object { " " * 8 + $_  + [Environment]::NewLine}                             
                $beginBlock  = $beginBlock -replace '\$scriptCmd =', ($defaultValueText + '$scriptCmd =')
            }
            
            # Indent the block of code.  Yes, this is neurotic.
            $beginBlock = $beginBlock -split ([Environment]::NewLine) -ne "" |
                ForEach-Object { " " * 4 + $_  + [Environment]::NewLine}                             
            
            $endBlock = [Management.Automation.ProxyCommand]::GetEnd($metaData) -split ([Environment]::NewLine) -ne "" |
                ForEach-Object { " " * 4 + $_  + [Environment]::NewLine} 
                
                
            $paramBlock = "$([Management.Automation.ProxyCommand]::GetParamBlock($metaData))" -replace '(\$)\{(\w.+)\}', '$1$2'
            
            
            
            $ProcessBlock  = if ($ProcessEachItem){                
                $embedProcessBlock = $ProcessEachItem.ToString() -split ([Environment]::NewLine) -ne "" |
                    ForEach-Object { " " * 16 + $_  + [Environment]::NewLine}                             
                "
    try {
        `$steppablePipeline.Process(`$_) | 
            ForEach-Object {
$embedProcessBlock
            }
    } catch {
        throw
    }
                "
            } elseif ($NewTypeName) {
                "
    try {
        `$steppablePipeline.Process(`$_) | 
            ForEach-Object {
                `$_.pstypenames.clear()
                `$_.pstypenames.add('$NewTypeName')
                `$_
            }
    } catch {
        throw
    }
                "
            } else {
                [Management.Automation.ProxyCommand]::GetProcess($metaData)
            }
            
            
            $ProcessBlock = $ProcessBlock -split ([Environment]::NewLine) -ne "" |
                ForEach-Object { " " * 4 + $_  + [Environment]::NewLine}

        
"function ${Name} {
    $([Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($MetaData))    
    param(
        $paramBlock
    )
    
    begin {
$BeginBlock
    }
    
    process {
$ProcessBlock
    }
    
    end {
$EndBlock
    }
}
"


        }
    }
} 
