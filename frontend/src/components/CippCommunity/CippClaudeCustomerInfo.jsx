import { useState } from 'react'
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  Chip,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Stack,
  TextField,
  Typography,
} from '@mui/material'
import {
  CheckCircle,
  Download,
  HelpOutlined,
  PictureAsPdf,
  RadioButtonUnchecked,
} from '@mui/icons-material'
import {
  ServerPdfPane,
  downloadServerPdf,
  useServerPdf,
} from '../CippPdf/useServerPdf'

const PDF_URL = '/api/ExecClaudeConnectorCustomerPdf'

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

const fileNameFor = (name) =>
  `Claude_for_Microsoft_365_${String(name || 'customer').replace(/[^a-zA-Z0-9]/g, '_')}.pdf`

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
  const [contactName, setContactName] = useState('')
  const [preparedBy, setPreparedBy] = useState('')
  const [previewOpen, setPreviewOpen] = useState(false)
  const [downloading, setDownloading] = useState(false)
  const [downloadError, setDownloadError] = useState(null)

  const body = {
    tenantFilter: tenant,
    ContactName: contactName.trim(),
    PreparedBy: preparedBy.trim(),
  }
  const pdf = useServerPdf({ url: PDF_URL, body, enabled: previewOpen })
  const fileName = fileNameFor(tenantName ?? tenant)

  const download = () => {
    setDownloading(true)
    setDownloadError(null)
    downloadServerPdf(PDF_URL, body, fileName)
      .catch((status) =>
        setDownloadError(
          `The PDF couldn't be made (${status || 'network error'}).`
        )
      )
      .finally(() => setDownloading(false))
  }

  const items = claudeReadinessItems(readiness)

  return (
    <Card variant="outlined" aria-label="Information for the customer">
      <CardContent>
        <Stack spacing={2}>
          <Box>
            <Typography variant="h6">Information for the customer</Typography>
            <Typography variant="body2" color="text.secondary">
              A branded PDF to send when a customer asks for Claude: what we
              recommend having first, filled in from their tenant, the four
              access levels with pros and cons, and what to reply with.
            </Typography>
          </Box>

          <Stack
            direction="row"
            spacing={1}
            useFlexGap
            sx={{ flexWrap: 'wrap' }}
          >
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

          <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2}>
            <TextField
              size="small"
              label="Addressed to (optional)"
              value={contactName}
              onChange={(e) => setContactName(e.target.value)}
              slotProps={{ htmlInput: { maxLength: 100 } }}
              sx={{ minWidth: 240 }}
            />
            <TextField
              size="small"
              label="From (optional)"
              value={preparedBy}
              onChange={(e) => setPreparedBy(e.target.value)}
              slotProps={{ htmlInput: { maxLength: 100 } }}
              sx={{ minWidth: 240 }}
            />
          </Stack>

          <Stack
            direction="row"
            spacing={1.5}
            useFlexGap
            sx={{ flexWrap: 'wrap' }}
          >
            <Button
              variant="contained"
              startIcon={<PictureAsPdf />}
              onClick={() => setPreviewOpen(true)}
            >
              Preview PDF
            </Button>
            <Button
              variant="outlined"
              startIcon={<Download />}
              onClick={download}
              disabled={downloading}
            >
              {downloading ? 'Making PDF…' : 'Download PDF'}
            </Button>
          </Stack>
          {downloadError && <Alert severity="error">{downloadError}</Alert>}
        </Stack>
      </CardContent>

      <Dialog
        open={previewOpen}
        onClose={() => setPreviewOpen(false)}
        fullWidth
        maxWidth="lg"
      >
        <DialogTitle>
          Claude for Microsoft 365: customer information
        </DialogTitle>
        <DialogContent sx={{ height: '75vh', p: 0 }}>
          <ServerPdfPane
            pdfUrl={pdf.pdfUrl}
            loading={pdf.loading}
            error={pdf.error}
            errorText="The PDF couldn't be made. Check the tenant and try again."
            title="Customer information PDF"
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setPreviewOpen(false)}>Close</Button>
          <Button
            variant="contained"
            startIcon={<Download />}
            disabled={!pdf.pdfUrl}
            onClick={() => pdf.download(fileName)}
          >
            Download
          </Button>
        </DialogActions>
      </Dialog>
    </Card>
  )
}

export default CippClaudeCustomerInfo
