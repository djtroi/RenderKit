Describe 'RenderKit engine contract service' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        . (Join-Path $repositoryRoot 'src/Private/Engine/RenderKit.EngineContractService.ps1')
    }

    It 'creates normalized actor and operation contexts with correlation ids' {
        $correlationId = [guid]::NewGuid().ToString()
        $actor = New-RenderKitActorContext `
            -ActorId 'user-1' `
            -ActorType User `
            -DisplayName 'Alice' `
            -Source 'LocalBroker' `
            -RolesSnapshot @('Admin') `
            -CorrelationId $correlationId

        $context = New-RenderKitOperationContext `
            -OperationName 'NewRenderKitEngineJob' `
            -Actor $actor `
            -CorrelationId $correlationId `
            -Source 'LocalBroker'

        $context.actor.actorId | Should -Be 'user-1'
        $context.actor.rolesSnapshot[0] | Should -Be 'Admin'
        $context.correlationId | Should -Be $correlationId
        $context.causationId | Should -BeNullOrEmpty
    }

    It 'rejects malformed correlation and causation ids' {
        { New-RenderKitCorrelationId -CorrelationId 'not-a-guid' } |
            Should -Throw
        { New-RenderKitCausationId -CausationId 'not-a-guid' } |
            Should -Throw
    }

    It 'creates success results with operation context metadata' {
        $context = New-RenderKitOperationContext -OperationName 'GetRenderKitJobList'

        $result = New-RenderKitResult `
            -Data ([PSCustomObject]@{ count = 0 }) `
            -OperationContext $context

        $result.success | Should -BeTrue
        $result.data.count | Should -Be 0
        $result.error | Should -BeNullOrEmpty
        $result.correlationId | Should -Be $context.correlationId
        $result.actor.actorType | Should -Be 'System'
    }

    It 'creates failure results with registered error codes' {
        $context = New-RenderKitOperationContext -OperationName 'GetRenderKitJobDetail'
        $errorRecord = New-RenderKitError `
            -Code 'RK_JOB_NOT_FOUND' `
            -Message 'The requested job does not exist.' `
            -Details ([PSCustomObject]@{ jobId = 'missing' })

        $result = New-RenderKitResult `
            -Error $errorRecord `
            -OperationContext $context

        $result.success | Should -BeFalse
        $result.data | Should -BeNullOrEmpty
        $result.error.code | Should -Be 'RK_JOB_NOT_FOUND'
        $result.error.category | Should -Be 'Job'
    }

    It 'rejects unregistered error codes' {
        { New-RenderKitError -Code 'RK_UNKNOWN' -Message 'Nope' } |
            Should -Throw
    }

    It 'describes the broker-facing engine facade operations' {
        $catalog = @(Get-RenderKitEngineFacadeOperationCatalog)

        $catalog.Count | Should -BeGreaterThan 5
        @($catalog | Where-Object { $_.Name -eq 'InvokeRenderKitWorkerTick' }).Count |
            Should -Be 1
        @($catalog | Where-Object { $_.MutatesState -and -not $_.RequiresActor }).Count |
            Should -Be 0
    }

    It 'publishes stable error codes for broker contracts' {
        $codes = @((Get-RenderKitErrorCodeCatalog).Code)

        $codes | Should -Contain 'RK_VALIDATION_FAILED'
        $codes | Should -Contain 'RK_ACCESS_CONTEXT_MISSING'
        $codes | Should -Contain 'RK_INTERNAL_ERROR'
        Test-RenderKitErrorCode -Code 'RK_JOB_INVALID_STATE' |
            Should -BeTrue
    }
}