Describe 'RenderKit engine contract snapshot' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:RenderKitModuleRoot = $repositoryRoot
        . (Join-Path $repositoryRoot 'src/Private/Event/RenderKit.EventService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Job/RenderKit.JobService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Engine/RenderKit.EngineContractService.ps1')
    }
    It 'returns a machine-readable host handoff contract' {
        $actor = New-RenderKitActorContext `
            -ActorId 'host-system' `
            -ActorType Service `
            -Source 'LocalBroker'

        $result = Get-RenderKitEngineContractSnapshot -Actor $actor

        $result.success | Should -BeTrue
        $result.data.contractVersion | Should -Be '1.0'
        $result.data.boundary.authenticationOwner | Should -Be 'Host'
        $result.data.schemas.eventStore | Should -Be '1.1'
        $result.data.schemas.jobStore | Should -Be '1.1'
        $result.data.resultEnvelope.fields | Should -Contain 'correlationId'
        $result.data.actorContext.actorTypes | Should -Contain 'Worker'
        @($result.data.operations | Where-Object { $_.Name -eq 'GetRenderKitEngineContractSnapshot' }).Count |
            Should -Be 1
        @($result.data.errorCodes | Where-Object { $_.Code -eq 'RK_ACCESS_CONTEXT_MISSING' }).Count |
            Should -Be 1
    }
}