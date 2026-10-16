/**
 * Community Additions > Standard Processes.
 *
 * Each entry is a repeatable job an MSP does in a customer tenant, turned into a guided page. To add
 * one, add an entry here and a page under src/pages/community/standard-processes/. `permissions` uses
 * the same patterns as the menu (layouts/config.jsx); the card is only shown to people who have them.
 */
export const standardProcesses = [
  {
    id: 'claude-m365',
    title: 'Claude for Microsoft 365',
    summary:
      "Adds Anthropic's Claude connector for Microsoft 365 to a tenant and limits it to the people you choose.",
    steps: [
      'Adds the two Claude apps to the tenant',
      "A Global Administrator approves Microsoft's consent page",
      'Puts the chosen people in an access group and makes the apps assignment-only',
      'Optionally stops users approving apps themselves and turns on admin consent requests',
    ],
    needs: 'A Global Administrator of the tenant, for the consent step',
    href: '/community/standard-processes/claude-m365',
    permissions: ['Tenant.Application.*'],
    tags: ['AI', 'Entra ID', 'Enterprise apps'],
  },
]
