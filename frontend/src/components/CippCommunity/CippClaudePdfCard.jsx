import { useState } from 'react'
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Stack,
  TextField,
  Typography,
} from '@mui/material'
import { Download, PictureAsPdf } from '@mui/icons-material'
import {
  ServerPdfPane,
  downloadServerPdf,
  useServerPdf,
} from '../CippPdf/useServerPdf'

/** A safe file name: `${prefix}_${name}.pdf` with anything but letters and numbers as underscores. */
export const claudePdfFileName = (prefix, name) =>
  `${prefix}_${String(name || 'customer').replace(/[^a-zA-Z0-9]/g, '_')}.pdf`

/**
 * A card that makes a branded PDF for the customer from a server endpoint: optional "Addressed to"
 * and "From" names, Preview (in a dialog) and Download. `body` is sent with the names added.
 */
export const CippClaudePdfCard = ({
  url,
  body,
  title,
  description,
  dialogTitle,
  fileName,
  ariaLabel,
  children,
}) => {
  const [contactName, setContactName] = useState('')
  const [preparedBy, setPreparedBy] = useState('')
  const [previewOpen, setPreviewOpen] = useState(false)
  const [downloading, setDownloading] = useState(false)
  const [downloadError, setDownloadError] = useState(null)

  const request = {
    ...body,
    ContactName: contactName.trim(),
    PreparedBy: preparedBy.trim(),
  }
  const pdf = useServerPdf({ url, body: request, enabled: previewOpen })

  const download = () => {
    setDownloading(true)
    setDownloadError(null)
    downloadServerPdf(url, request, fileName)
      .catch((status) =>
        setDownloadError(
          `The PDF couldn't be made (${status || 'network error'}).`
        )
      )
      .finally(() => setDownloading(false))
  }

  return (
    <Card variant="outlined" aria-label={ariaLabel ?? title}>
      <CardContent>
        <Stack spacing={2}>
          <Box>
            <Typography variant="h6">{title}</Typography>
            <Typography variant="body2" color="text.secondary">
              {description}
            </Typography>
          </Box>
          {children}
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
        <DialogTitle>{dialogTitle ?? title}</DialogTitle>
        <DialogContent sx={{ height: '75vh', p: 0 }}>
          <ServerPdfPane
            pdfUrl={pdf.pdfUrl}
            loading={pdf.loading}
            error={pdf.error}
            errorText="The PDF couldn't be made. Check the tenant and try again."
            title={dialogTitle ?? title}
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

export default CippClaudePdfCard
