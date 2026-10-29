import { Chip, Stack } from '@mui/material'
import {
  CheckCircle,
  HelpOutlined,
  RadioButtonUnchecked,
} from '@mui/icons-material'
import { CippClaudePdfCard, claudePdfFileName } from './CippClaudePdfCard'

/**
 * What we recommend having before giving Claude access, from ListClaudeConnector's Readiness.
 * Each item: { key, label, have (true | false | null), detail }.
 * @param {object} readiness
 */
export const claudeReadinessItems = (readiness) => {
  const r = readiness ?? {}
  const backup = r.Backup
  return [
    {
      key: 'backup',
      label: 'Third-party backup',
      have: backup ? Boolean(backup.Found) : null,
      detail: !backup
        ? "Couldn't check"
        : backup.Barracuda
          ? 'Barracuda backup found'
          : backup.Found
            ? (backup.Products ?? []).join(', ')
            : 'No Barracuda or other backup app found',
    },
    {
      key: 'p1',
      label: 'Entra ID P1',
      have: typeof r.EntraP1 === 'boolean' ? r.EntraP1 : null,
      detail:
        r.EntraP1 === true
          ? 'Access can be controlled with a group'
          : r.EntraP1 === false
            ? 'People are added one by one'
            : "Couldn't check",
    },
    {
      key: 'defender',
      label: 'Microsoft Defender',
      have: r.Defender ? Boolean(r.Defender.Found) : null,
      detail: !r.Defender
        ? "Couldn't check"
        : r.Defender.Found
          ? (r.Defender.Products ?? []).join(', ')
          : 'Not in their licences',
    },
    {
      key: 'bp',
      label: 'Business Premium',
      have:
        r.BusinessPremium === true
          ? true
          : r.Suite
            ? true
            : r.Suite === null
              ? false
              : null,
      detail: r.Suite
        ? r.Suite
        : r.Suite === null
          ? 'Not licensed'
          : "Couldn't check",
    },
  ]
}

/**
 * Information for the customer: what they already have, and a branded PDF explaining the access
 * options to send them (ExecClaudeConnectorCustomerPdf).
 */
export const CippClaudeCustomerInfo = ({
  tenant,
  tenantName,
  readiness,
  loading,
}) => {
  const items = claudeReadinessItems(readiness)
  return (
    <CippClaudePdfCard
      url="/api/ExecClaudeConnectorCustomerPdf"
      body={{ tenantFilter: tenant }}
      title="Information for the customer"
      description="A branded PDF to send when a customer asks for Claude: what we recommend having first, filled in from their tenant, the four access levels with pros and cons, and what to reply with."
      dialogTitle="Claude for Microsoft 365: customer information"
      fileName={claudePdfFileName(
        'Claude_for_Microsoft_365',
        tenantName ?? tenant
      )}
    >
      <Stack direction="row" spacing={1} useFlexGap sx={{ flexWrap: 'wrap' }}>
        {items.map((i) => (
          <Chip
            key={i.key}
            variant="outlined"
            color={
              i.have === true
                ? 'success'
                : i.have === false
                  ? 'warning'
                  : 'default'
            }
            icon={
              i.have === true ? (
                <CheckCircle />
              ) : i.have === false ? (
                <RadioButtonUnchecked />
              ) : (
                <HelpOutlined />
              )
            }
            label={
              loading ? `${i.label}: checking…` : `${i.label}: ${i.detail}`
            }
          />
        ))}
      </Stack>
    </CippClaudePdfCard>
  )
}

export default CippClaudeCustomerInfo
