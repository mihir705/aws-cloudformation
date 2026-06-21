<#
.SYNOPSIS
  Upload CloudFormation templates to S3 and deploy layered stacks.

.DESCRIPTION
  Deployment workflow:
    1. Package templates to S3
    2. Deploy network -> data -> application stacks in order

.PARAMETER Environment
  Target environment: dev, staging, prod

.PARAMETER TemplateBucket
  S3 bucket for nested stack templates (must exist)

.PARAMETER TemplateVersion
  Version prefix for immutable deployments (default: v1)

.PARAMETER Region
  AWS region (default: us-east-1)

.PARAMETER Project
  Project name used in stack naming (default: myapp)

.PARAMETER Layer
  Which stack to deploy: all, network, data, application

.EXAMPLE
  .\deploy.ps1 -Environment dev -TemplateBucket my-cfn-templates -Layer all
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [string]$TemplateBucket,

    [string]$TemplateVersion = 'v1',
    [string]$Region = 'us-east-1',
    [string]$Project = 'myapp',
    [ValidateSet('all', 'network', 'data', 'application')]
    [string]$Layer = 'all'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$CfnRoot = Join-Path $Root 'cloudformation'

function Upload-Templates {
    Write-Host "Uploading templates to s3://${TemplateBucket}/${TemplateVersion}/ ..."
    aws s3 sync "$CfnRoot/modules" "s3://${TemplateBucket}/${TemplateVersion}/modules" --delete --region $Region
    aws s3 sync "$CfnRoot/stacks" "s3://${TemplateBucket}/${TemplateVersion}/stacks" --delete --region $Region
}

function Deploy-Stack {
    param(
        [string]$StackLayer,
        [string]$StackName,
        [string]$TemplateFile,
        [string]$ParametersFile
    )

    Write-Host "Validating $StackLayer template..."
    aws cloudformation validate-template `
        --template-body "file://$TemplateFile" `
        --region $Region | Out-Null

    $paramsPath = Join-Path $CfnRoot "parameters/${StackLayer}-${Environment}.json"
    if (-not (Test-Path $paramsPath)) {
        throw "Parameter file not found: $paramsPath"
    }

    # Inject TemplateBucket into parameters at deploy time
    $params = Get-Content $paramsPath | ConvertFrom-Json
    ($params | Where-Object { $_.ParameterKey -eq 'TemplateBucket' }).ParameterValue = $TemplateBucket
    ($params | Where-Object { $_.ParameterKey -eq 'TemplateVersion' }).ParameterValue = $TemplateVersion
    $tempParams = [System.IO.Path]::GetTempFileName()
    $params | ConvertTo-Json -Depth 5 | Set-Content $tempParams

    Write-Host "Deploying stack: $StackName ..."
    aws cloudformation deploy `
        --stack-name $StackName `
        --template-file $TemplateFile `
        --parameter-overrides file://$tempParams `
        --capabilities CAPABILITY_NAMED_IAM `
        --no-fail-on-empty-changeset `
        --region $Region

    if ($LASTEXITCODE -ne 0) {
        Remove-Item $tempParams -Force
        throw "Stack deployment failed: $StackName (exit code $LASTEXITCODE)"
    }

    Remove-Item $tempParams -Force
    Write-Host "Stack $StackName deployed successfully."
}

Upload-Templates

$stacks = @(
    @{
        Layer      = 'network'
        Name       = "$Project-$Environment-network"
        Template   = Join-Path $CfnRoot 'stacks/network/template.yaml'
    },
    @{
        Layer      = 'data'
        Name       = "$Project-$Environment-data"
        Template   = Join-Path $CfnRoot 'stacks/data/template.yaml'
    },
    @{
        Layer      = 'application'
        Name       = "$Project-$Environment-application"
        Template   = Join-Path $CfnRoot 'stacks/application/template.yaml'
    }
)

foreach ($stack in $stacks) {
    if ($Layer -eq 'all' -or $Layer -eq $stack.Layer) {
        Deploy-Stack -StackLayer $stack.Layer -StackName $stack.Name -TemplateFile $stack.Template
    }
}

Write-Host "Done."
