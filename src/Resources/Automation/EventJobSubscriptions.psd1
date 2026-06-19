@{
    CatalogVersion = '1.0'
    Subscriptions = @(
        @{
            Id = 'project-lifecycle-automation'
            Enabled = $true
            EventType = 'ProjectLifecycleStatusChanged'
            JobType = 'ProjectLifecycleAutomation'
            Description = 'Queues internal automation work for project lifecycle changes.'
        }
    )
}